/// Кадры раскладки для айтрекера (SNO-F-REC-03, SNO-ALG-REC-02) —
/// чистая часть: что такое кадр, когда его писать и как из него
/// вернуться от точки экрана к месту на странице.
///
/// Кадр раскладки говорит, где в этот миг лежало то, что видно на
/// экране: страница — в каком масштабе и с каким сдвигом, какая рамка
/// обрезки и какая полоса читается, — и что было поверх неё: панели,
/// полоса поиска, панель над выделением, оглавление, диалоги, точка
/// записи. По кадру точка взгляда или касания на экране переводится в
/// зону, а для страницы — в точку страницы в пунктах PDF, без
/// видеозаписи экрана.
///
/// Кадры идут третьим потоком записи — `layout.jsonl`, писателем того
/// же вида, что журнал и поток ввода: сквозной номер `n`, время `t` по
/// часам записи. Координаты — логические пиксели окна, те же, что у
/// потока ввода; у потока взгляда — физические пиксели монитора, и
/// разбор делит их на `dpr` кадра.
///
/// Здесь нет виджетов: зоны собирает слой записи (`layout_probe.dart`),
/// а правила — когда кадр «в движении», когда «устоялся», что в нём
/// лежит и как его читать — проверяются на придуманных числах.
library;

import 'dart:convert';
import 'dart:math' as math;

/// Вид зоны — закрытый перечень (SNO-ALG-REC-02, 08.10.2026).
///
/// Имя в потоке — [wire]. Новый вид заводится здесь и в заметке
/// алгоритма вместе; разбор незнакомый вид считает экраном целиком.
enum LayoutKind {
  /// Место под страницу на экране чтения.
  page('page'),

  /// Верхняя панель чтения.
  panelTop('panel_top'),

  /// Нижняя панель чтения.
  panelBottom('panel_bottom'),

  /// Полоса или панель поиска по книге.
  searchDock('search_dock'),

  /// Панель действий над выделением.
  selectionPanel('selection_panel'),

  /// Окно заметки над страницей (полотно, F-NOTE-06).
  noteWindow('note_window'),

  /// Оглавление.
  toc('toc'),

  /// Участок категории на полке (ET-05).
  shelfCategory('shelf_category'),

  /// Блок книги на полке (ET-05).
  shelfBook('shelf_book'),

  /// Поле поиска по названию на полке (ET-05).
  shelfSearch('shelf_search'),

  /// Список найденного по названию (ET-05).
  shelfResults('shelf_results'),

  /// Навигация между разделами (ET-05).
  nav('nav'),

  /// Полотно карты «Галактика» (ET-05).
  galaxyMap('galaxy_map'),

  /// Карточка книги на карте (ET-05).
  galaxyCard('galaxy_card'),

  /// Диалог, лист снизу, подсказка поверх экрана.
  dialog('dialog'),

  /// Точка записи — её касается экспериментатор.
  recordingDot('recording_dot'),

  /// Экран целиком: редактор рамки, калибровка, завершение, тест.
  screen('screen');

  const LayoutKind(this.wire);

  /// Имя вида в потоке.
  final String wire;
}

/// Число с одним знаком после запятой: координате на экране больше не
/// нужно, а строка короче.
double layoutRound(double value) {
  if (!value.isFinite) {
    return 0;
  }
  return (value * 10).roundToDouble() / 10;
}

/// Число карты — шесть знаков после запятой (шаг 31): координаты
/// карты малы, и десятой доли им мало.
double layoutFine(double value) {
  if (!value.isFinite) {
    return 0;
  }
  return (value * 1000000).roundToDouble() / 1000000;
}

/// Масштаб — пять знаков после запятой: на странице в тысячу пунктов
/// это сотая доля пикселя.
double _roundScale(double value) {
  if (!value.isFinite) {
    return 0;
  }
  return (value * 100000).roundToDouble() / 100000;
}

/// Прямоугольник в логических пикселях окна: `[l, t, w, h]` в потоке.
class LayoutRect {
  /// Создаёт прямоугольник.
  const LayoutRect(this.left, this.top, this.width, this.height);

  /// Прямоугольник по двум углам.
  factory LayoutRect.fromLTRB(
    double left,
    double top,
    double right,
    double bottom,
  ) {
    return LayoutRect(
      math.min(left, right),
      math.min(top, bottom),
      (right - left).abs(),
      (bottom - top).abs(),
    );
  }

  /// Левый край.
  final double left;

  /// Верхний край.
  final double top;

  /// Ширина.
  final double width;

  /// Высота.
  final double height;

  /// Правый край.
  double get right => left + width;

  /// Нижний край.
  double get bottom => top + height;

  /// Лежит ли точка ([x], [y]) внутри — края включительно.
  bool contains(double x, double y) {
    return x >= left && x <= right && y >= top && y <= bottom;
  }

  /// Пересекается ли с прямоугольником [other] хоть чем-то.
  bool overlaps(LayoutRect other) {
    return left < other.right &&
        other.left < right &&
        top < other.bottom &&
        other.top < bottom;
  }

  /// Общая часть с [other]; `null` — общего нет.
  LayoutRect? intersect(LayoutRect other) {
    if (!overlaps(other)) {
      return null;
    }
    return LayoutRect.fromLTRB(
      math.max(left, other.left),
      math.max(top, other.top),
      math.min(right, other.right),
      math.min(bottom, other.bottom),
    );
  }

  /// Тот же прямоугольник, округлённый, как он ляжет в поток.
  LayoutRect get rounded => LayoutRect(
    layoutRound(left),
    layoutRound(top),
    layoutRound(width),
    layoutRound(height),
  );

  /// `[l, t, w, h]` для потока.
  List<double> toJson() => <double>[
    layoutRound(left),
    layoutRound(top),
    layoutRound(width),
    layoutRound(height),
  ];

  /// Читает `[l, t, w, h]`; `null` — не прямоугольник.
  static LayoutRect? fromJson(Object? raw) {
    if (raw is! List<Object?> || raw.length != 4) {
      return null;
    }
    final List<double> values = <double>[];
    for (final Object? value in raw) {
      if (value is! num) {
        return null;
      }
      values.add(value.toDouble());
    }
    return LayoutRect(values[0], values[1], values[2], values[3]);
  }

  @override
  bool operator ==(Object other) {
    return other is LayoutRect &&
        other.left == left &&
        other.top == top &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'LayoutRect($left, $top, $width × $height)';
}

/// Перевод точек одного места экрана в окно: сдвиг и равный по обеим
/// осям масштаб — всё, что бывает между листом и окном приложения.
class LayoutPlace {
  /// Создаёт перевод.
  const LayoutPlace({this.scale = 1, this.dx = 0, this.dy = 0});

  /// Ничего не меняет.
  static const LayoutPlace identity = LayoutPlace();

  /// Во сколько раз точка места больше точки окна.
  final double scale;

  /// Сдвиг по горизонтали.
  final double dx;

  /// Сдвиг по вертикали.
  final double dy;

  /// Точка в окне.
  (double, double) point(double x, double y) {
    return (x * scale + dx, y * scale + dy);
  }

  /// Прямоугольник в окне.
  LayoutRect rect(LayoutRect local) {
    final (double left, double top) = point(local.left, local.top);
    final (double right, double bottom) = point(local.right, local.bottom);
    return LayoutRect.fromLTRB(left, top, right, bottom);
  }
}

/// Страница листа в кадре: где на экране её левый верхний угол и
/// каков её размер в пунктах PDF.
class LayoutPage {
  /// Создаёт страницу.
  const LayoutPage({
    required this.page,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Номер страницы в книге, считая с единицы.
  final int page;

  /// Левый край страницы на экране, пиксели окна.
  final double x;

  /// Верхний край страницы на экране, пиксели окна.
  final double y;

  /// Ширина страницы, пункты PDF.
  final double width;

  /// Высота страницы, пункты PDF.
  final double height;

  /// Для потока.
  Map<String, Object?> toJson() => <String, Object?>{
    'page': page,
    'x': layoutRound(x),
    'y': layoutRound(y),
    'w': layoutRound(width),
    'h': layoutRound(height),
  };
}

/// Соседний лист, видный рядом со своим (F-READ-12, F-READ-13).
class LayoutNeighbour {
  /// Создаёт соседа.
  const LayoutNeighbour({required this.after, required this.rect});

  /// Сосед после листа (справа или снизу); иначе — до него.
  final bool after;

  /// Что от него видно, пиксели окна.
  final LayoutRect rect;

  /// Для потока.
  Map<String, Object?> toJson() => <String, Object?>{
    'side': after ? 'after' : 'before',
    'rect': rect.toJson(),
  };
}

/// Где лежит лист книги на экране (SNO-ALG-REC-02, шаг 2).
///
/// Перевод в точку страницы: `x_pt = (x − page.x) / scale`,
/// `y_pt = (y − page.y) / scale`, ось `y` растёт вниз (`y_down`).
/// Страница разворота — своя запись в [pages]; вторая начинается там,
/// где кончилась первая.
class SheetGeometry {
  /// Создаёт геометрию.
  const SheetGeometry({
    required this.scale,
    required this.pages,
    required this.sheet,
    required this.content,
    required this.strip,
    required this.stripIndex,
    required this.strips,
    this.neighbours = const <LayoutNeighbour>[],
  });

  /// Пикселей окна на пункт PDF — вместе с тем, что читатель добавил
  /// щипком.
  final double scale;

  /// Страницы листа.
  final List<LayoutPage> pages;

  /// Лист целиком.
  final LayoutRect sheet;

  /// Рамка обрезки листа — то, что считается содержимым.
  final LayoutRect content;

  /// Читаемая полоса (фрагмент): всё, что на листе вне неё, затемнено.
  final LayoutRect strip;

  /// Номер полосы, считая с единицы.
  final int stripIndex;

  /// Сколько полос у листа в этом режиме.
  final int strips;

  /// Что видно от соседних листов.
  final List<LayoutNeighbour> neighbours;

  /// Та же геометрия в окне, если её место переведено [place].
  SheetGeometry placed(LayoutPlace place) {
    if (identical(place, LayoutPlace.identity)) {
      return this;
    }
    final List<LayoutPage> moved = <LayoutPage>[];
    for (final LayoutPage page in pages) {
      final (double x, double y) = place.point(page.x, page.y);
      moved.add(
        LayoutPage(
          page: page.page,
          x: x,
          y: y,
          width: page.width,
          height: page.height,
        ),
      );
    }
    return SheetGeometry(
      scale: scale * place.scale,
      pages: moved,
      sheet: place.rect(sheet),
      content: place.rect(content),
      strip: place.rect(strip),
      stripIndex: stripIndex,
      strips: strips,
      neighbours: <LayoutNeighbour>[
        for (final LayoutNeighbour neighbour in neighbours)
          LayoutNeighbour(
            after: neighbour.after,
            rect: place.rect(neighbour.rect),
          ),
      ],
    );
  }

  /// Для потока.
  Map<String, Object?> toJson() => <String, Object?>{
    'y_down': true,
    'scale': _roundScale(scale),
    'pages': <Object?>[for (final LayoutPage page in pages) page.toJson()],
    'rect': sheet.toJson(),
    'content': content.toJson(),
    'strip': strip.toJson(),
    'strip_index': stripIndex,
    'strips': strips,
    'neighbours': <Object?>[
      for (final LayoutNeighbour neighbour in neighbours) neighbour.toJson(),
    ],
  };
}

/// Доли листа: рамка обрезки и полоса приходят от экрана чтения так.
class SheetBox {
  /// Создаёт прямоугольник в долях листа.
  const SheetBox(this.left, this.top, this.right, this.bottom);

  /// Лист целиком.
  static const SheetBox full = SheetBox(0, 0, 1, 1);

  /// Левая граница, доля ширины листа.
  final double left;

  /// Верхняя граница, доля высоты листа.
  final double top;

  /// Правая граница.
  final double right;

  /// Нижняя граница.
  final double bottom;
}

/// Геометрия листа на месте, где его рисует экран чтения
/// (SNO-ALG-REC-02, шаг 2) — до перевода в окно.
///
/// Лист — страницы [pages] рядом, по верхнему краю; точка листа
/// `(x, y)` в пунктах PDF ложится на место так же, как у просмотрщика:
/// `((left + x · scale) · zoom + dx, (top + y · scale) · zoom + dy)` —
/// раскладка листа ([scale], [left], [top]) плюс то, что читатель
/// добавил щипком при отпертом замке ([zoom], [dx], [dy]).
SheetGeometry sheetGeometry({
  required List<({int page, double width, double height})> pages,
  required double scale,
  required double left,
  required double top,
  double zoom = 1,
  double dx = 0,
  double dy = 0,
  SheetBox content = SheetBox.full,
  SheetBox strip = SheetBox.full,
  int stripIndex = 1,
  int strips = 1,
  List<LayoutNeighbour> neighbours = const <LayoutNeighbour>[],
}) {
  final double effective = scale * zoom;
  final double originX = left * zoom + dx;
  final double originY = top * zoom + dy;
  double sheetWidth = 0;
  double sheetHeight = 0;
  final List<LayoutPage> placed = <LayoutPage>[];
  for (final ({int page, double width, double height}) page in pages) {
    placed.add(
      LayoutPage(
        page: page.page,
        x: originX + sheetWidth * effective,
        y: originY,
        width: page.width,
        height: page.height,
      ),
    );
    sheetWidth += page.width;
    sheetHeight = math.max(sheetHeight, page.height);
  }
  LayoutRect part(SheetBox box) {
    return LayoutRect.fromLTRB(
      originX + box.left * sheetWidth * effective,
      originY + box.top * sheetHeight * effective,
      originX + box.right * sheetWidth * effective,
      originY + box.bottom * sheetHeight * effective,
    );
  }

  return SheetGeometry(
    scale: effective,
    pages: placed,
    sheet: part(SheetBox.full),
    content: part(content),
    strip: part(strip),
    stripIndex: stripIndex,
    strips: strips,
    neighbours: neighbours,
  );
}

/// Сколько логических пикселей от метки ещё считается попаданием в
/// неё, если сама метка меньше (SNO-ALG-REC-02, шаг 3; шаг 31).
///
/// Столько же ловит нажатие звезда на карте (`kHitRadius`, ALG-MAP-13):
/// по кадру касание звезды узнаётся так же, как его узнало приложение.
const double kLayoutMarkReach = 24;

/// Метка внутри зоны: точка с радиусом — звезда на карте (шаг 31).
///
/// Места меток рисует не дерево виджетов, а художник полотна, поэтому
/// их отдаёт сама зона ([LayoutRegion.marks]), а в окно переводит слой
/// записи — тем же переводом, что и место зоны.
class LayoutMark {
  /// Создаёт метку.
  const LayoutMark({
    required this.id,
    required this.x,
    required this.y,
    required this.r,
  });

  /// Чья метка: у звезды — отпечаток книги.
  final String id;

  /// Середина, пиксели окна.
  final double x;

  /// Середина, пиксели окна.
  final double y;

  /// Радиус, пиксели окна.
  final double r;

  /// Для потока.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'x': layoutRound(x),
    'y': layoutRound(y),
    'r': layoutRound(r),
  };
}

/// Зона в кадре: вид, имя, место в окне, порядок наложения.
///
/// С шага 31 (ET-05) у зоны бывают ещё [clipped] — часть зоны спрятана
/// краем прокрутки, и в кадре только видимая часть, — [info] — что ещё
/// известно о зоне (категория книги, сдвиг полки, камера карты) — и
/// [marks] — точки внутри неё (звёзды карты).
class LayoutRegion {
  /// Создаёт зону.
  const LayoutRegion({
    required this.kind,
    required this.rect,
    this.id = '',
    this.z = 0,
    this.clipped = false,
    this.info = const <String, Object?>{},
    this.marks = const <LayoutMark>[],
  });

  /// Вид.
  final LayoutKind kind;

  /// Имя внутри вида: какой диалог, какая книга; пусто — одна такая.
  final String id;

  /// Место в окне.
  final LayoutRect rect;

  /// Порядок наложения: больше — выше; зоны кадра — 0, 1, 2…
  final int z;

  /// Зона видна не вся: её подрезал край прокрутки, и [rect] — видимая
  /// часть.
  final bool clipped;

  /// Что ещё известно о зоне; значения — то, что ложится в JSON.
  final Map<String, Object?> info;

  /// Точки внутри зоны.
  final List<LayoutMark> marks;

  /// Та же зона на месте [z] порядка наложения.
  LayoutRegion atZ(int z) {
    return LayoutRegion(
      kind: kind,
      rect: rect,
      id: id,
      z: z,
      clipped: clipped,
      info: info,
      marks: marks,
    );
  }

  /// Для потока.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.wire,
    'id': id,
    'rect': rect.toJson(),
    'z': z,
    if (clipped) 'clip': true,
    if (info.isNotEmpty) 'info': info,
    if (marks.isNotEmpty)
      'marks': <Object?>[for (final LayoutMark mark in marks) mark.toJson()],
  };

  @override
  bool operator ==(Object other) {
    return other is LayoutRegion &&
        jsonEncode(other.toJson()) == jsonEncode(toJson());
  }

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// Метка зоны [region], в которую попала точка ([x], [y]): ближайшая
/// из тех, до чьей середины не дальше её радиуса или
/// [kLayoutMarkReach]; при равном расстоянии — первая. `null` — мимо
/// всех (SNO-ALG-REC-02, шаг 5; шаг 31).
LayoutMark? layoutMarkAt(LayoutRegion region, double x, double y) {
  LayoutMark? best;
  double bestSquare = double.infinity;
  for (final LayoutMark mark in region.marks) {
    final double dx = mark.x - x;
    final double dy = mark.y - y;
    final double square = dx * dx + dy * dy;
    final double reach = math.max(mark.r, kLayoutMarkReach);
    if (square <= reach * reach && square < bestSquare) {
      best = mark;
      bestSquare = square;
    }
  }
  return best;
}

/// Окно в кадре: размер в логических пикселях, их плотность и
/// положение экрана.
class LayoutViewport {
  /// Создаёт окно.
  const LayoutViewport({
    required this.width,
    required this.height,
    required this.dpr,
  });

  /// Ширина, логические пиксели.
  final double width;

  /// Высота, логические пиксели.
  final double height;

  /// Физических пикселей на логический.
  final double dpr;

  /// Положение экрана: шире, чем выше, — альбомное.
  String get orientation => width > height ? 'landscape' : 'portrait';

  /// Для потока.
  Map<String, Object?> toJson() => <String, Object?>{
    'w': layoutRound(width),
    'h': layoutRound(height),
    'dpr': _roundScale(dpr),
    'orientation': orientation,
  };

  @override
  bool operator ==(Object other) {
    return other is LayoutViewport &&
        other.width == width &&
        other.height == height &&
        other.dpr == dpr;
  }

  @override
  int get hashCode => Object.hash(width, height, dpr);
}

/// Что видно на экране в один миг: окно, зоны и лист книги.
///
/// Два снимка равны, когда равно всё, что ляжет в поток: координаты
/// сравниваются округлёнными, и движение меньше десятой доли пикселя
/// изменением не считается.
class LayoutSnapshot {
  /// Создаёт снимок.
  LayoutSnapshot({
    required this.viewport,
    required List<LayoutRegion> regions,
    this.sheet,
  }) : regions = List<LayoutRegion>.unmodifiable(regions),
       _key = _keyOf(viewport, regions, sheet);

  /// Окно.
  final LayoutViewport viewport;

  /// Зоны снизу вверх.
  final List<LayoutRegion> regions;

  /// Лист книги; `null` — книга не на экране.
  final SheetGeometry? sheet;

  final String _key;

  static String _keyOf(
    LayoutViewport viewport,
    List<LayoutRegion> regions,
    SheetGeometry? sheet,
  ) {
    final StringBuffer key = StringBuffer()
      ..write(viewport.toJson())
      ..write('|');
    for (final LayoutRegion region in regions) {
      key
        ..write(region.toJson())
        ..write(';');
    }
    if (sheet != null) {
      key.write(sheet.toJson());
    }
    return key.toString();
  }

  /// Тело строки потока — без номера, времени и экрана: их ставит
  /// запись.
  Map<String, Object?> toJson({required bool moving}) => <String, Object?>{
    'moving': moving,
    'viewport': viewport.toJson(),
    'sheet': ?sheet?.toJson(),
    'regions': <Object?>[
      for (final LayoutRegion region in regions) region.toJson(),
    ],
  };

  @override
  bool operator ==(Object other) {
    return other is LayoutSnapshot && other._key == _key;
  }

  @override
  int get hashCode => _key.hashCode;
}

/// Сколько тишины после последнего изменения делает кадр устоявшимся.
const Duration kLayoutSettle = Duration(milliseconds: 100);

/// Не чаще скольких миллисекунд пишется кадр «в движении»: пять в
/// секунду.
const int kLayoutMovingGapMs = 200;

/// Когда писать кадр (SNO-ALG-REC-02, шаг 1; 08.10.2026).
///
/// Снимки приходят после каждого кадра отрисовки, пока запись идёт.
/// Первый снимок изменения — кадр `moving: true` сразу, без ожидания;
/// пока изменения идут, следующие «в движении» — не чаще пяти в
/// секунду; через [kLayoutSettle] тишины — устоявшийся кадр, один на
/// всё изменение. Первый снимок записи «в движении» не бывает: он
/// пишется устоявшимся, как только простоял.
///
/// Время — миллисекунды кадров отрисовки: «в движении» меряется ими, а
/// тишину отсчитывает слой записи своим таймером и зовёт [settle].
class LayoutPacer {
  LayoutSnapshot? _current;
  LayoutSnapshot? _settled;
  int? _movingAt;
  bool _started = false;

  /// Пришёл снимок [snapshot] кадра отрисовки в миг [ms].
  ///
  /// Отвечает снимком для кадра «в движении» — или `null`, если его
  /// писать не надо. [changed] после вызова говорит, было ли это
  /// изменение и надо ли заново отсчитывать тишину.
  LayoutSnapshot? observe(LayoutSnapshot snapshot, int ms) {
    if (snapshot == _current) {
      changed = false;
      return null;
    }
    _current = snapshot;
    changed = true;
    if (!_started) {
      // Первый снимок записи: двигаться ему не от чего.
      _started = true;
      return null;
    }
    final int? at = _movingAt;
    if (at != null && ms - at < kLayoutMovingGapMs) {
      return null;
    }
    _movingAt = ms;
    return snapshot;
  }

  /// Было ли последнее [observe] изменением.
  bool changed = false;

  /// Тишина простояла: устоявшийся кадр — или `null`, если с прошлого
  /// устоявшегося ничего не случилось.
  LayoutSnapshot? settle() {
    final LayoutSnapshot? current = _current;
    final bool moved = _movingAt != null;
    _movingAt = null;
    if (current == null || (current == _settled && !moved)) {
      return null;
    }
    _settled = current;
    return current;
  }

  /// Есть ли изменение, которое ещё не легло устоявшимся кадром.
  bool get pending {
    final LayoutSnapshot? current = _current;
    return current != null && (current != _settled || _movingAt != null);
  }
}

/// Куда уходит готовая строка потока кадров.
typedef LayoutSink = void Function(Map<String, Object?> line);

/// Сборщик потока кадров (SNO-F-REC-03): номер строки, время, тело.
///
/// Экран, книгу, страницу и полосу ставит запись — по своему знанию о
/// том, где участник ([LayoutSink] сессии).
class LayoutTracker {
  /// Создаёт сборщик; строки уходят в [emit].
  LayoutTracker(this._emit);

  final LayoutSink _emit;
  int _n = 0;
  bool _finished = false;

  /// Сколько номеров выдано: столько строк обязано лежать в потоке.
  int get count => _n;

  /// Что дописать перед концом потока: кадр, который ещё не устоялся.
  /// Его ставит слой, который снимает кадры.
  void Function()? beforeFinish;

  /// Поток кончается — остановкой записи: недописанное дописывается, а
  /// дальше кадры не пишутся.
  void finish() {
    final void Function()? last = beforeFinish;
    beforeFinish = null;
    last?.call();
    _finished = true;
  }

  /// Пишет кадр [snapshot] в миг [t] по часам записи.
  void frame(LayoutSnapshot snapshot, {required int t, required bool moving}) {
    if (_finished) {
      return;
    }
    _n++;
    _emit(<String, Object?>{
      'n': _n,
      't': t,
      ...snapshot.toJson(moving: moving),
    });
  }
}

/// Что лежало в точке экрана по кадру (SNO-ALG-REC-02, шаг 5).
class LayoutHit {
  /// Создаёт ответ.
  const LayoutHit({
    required this.zone,
    this.id = '',
    this.page,
    this.xPt,
    this.yPt,
    this.dimmed = false,
    this.info = const <String, Object?>{},
    this.mark,
  });

  /// Вид зоны ([LayoutKind.wire]); для листа ещё `neighbour` — соседний
  /// лист, `background` — фон вокруг листа, `outside` — мимо окна.
  final String zone;

  /// Имя зоны.
  final String id;

  /// Страница — когда точка на странице.
  final int? page;

  /// Точка страницы в пунктах PDF, ось `y` вниз.
  final double? xPt;

  /// Точка страницы в пунктах PDF, ось `y` вниз.
  final double? yPt;

  /// Точка на странице, но вне читаемой полосы — в затемнении.
  final bool dimmed;

  /// Что ещё известно о зоне ([LayoutRegion.info]): у книги полки —
  /// категория, у строки найденного — её место в списке.
  final Map<String, Object?> info;

  /// Метка зоны, в которую попала точка ([layoutMarkAt]): у карты —
  /// отпечаток книги звезды; `null` — мимо меток или их нет.
  final String? mark;
}

/// Где в кадре точка ([x], [y]) окна (SNO-ALG-REC-02, шаг 5).
///
/// Зона поверх страницы важнее страницы: из зон, в которые точка
/// попала, берётся верхняя ([LayoutRegion.z]); ответ несёт её [info] и
/// метку под точкой ([layoutMarkAt]) — звезду карты. Если верхняя — место
/// под страницу и лист есть, точка переводится в страницу: на странице
/// — `page` с точкой в пунктах (в затемнении — `dimmed`), на соседнем
/// листе — `neighbour`, рядом — `background`. Та же формула — в
/// разборе на Python (`eye/sno_eye/layout.py`), и обе сверяются с одним
/// эталоном (`test/goldens/layout_frame.json`).
LayoutHit locateInFrame({
  required LayoutViewport viewport,
  required List<LayoutRegion> regions,
  required SheetGeometry? sheet,
  required double x,
  required double y,
}) {
  if (x < 0 || y < 0 || x > viewport.width || y > viewport.height) {
    return const LayoutHit(zone: 'outside');
  }
  LayoutRegion? top;
  for (final LayoutRegion region in regions) {
    if (region.rect.contains(x, y) && (top == null || region.z > top.z)) {
      top = region;
    }
  }
  if (top != null && (top.kind != LayoutKind.page || sheet == null)) {
    return LayoutHit(
      zone: top.kind.wire,
      id: top.id,
      info: top.info,
      mark: layoutMarkAt(top, x, y)?.id,
    );
  }
  if (sheet == null) {
    return const LayoutHit(zone: 'screen');
  }
  for (final LayoutPage page in sheet.pages) {
    final double xPt = (x - page.x) / sheet.scale;
    final double yPt = (y - page.y) / sheet.scale;
    if (xPt >= 0 && xPt <= page.width && yPt >= 0 && yPt <= page.height) {
      return LayoutHit(
        zone: LayoutKind.page.wire,
        id: top?.id ?? '',
        page: page.page,
        xPt: xPt,
        yPt: yPt,
        dimmed: !sheet.strip.contains(x, y),
      );
    }
  }
  for (final LayoutNeighbour neighbour in sheet.neighbours) {
    if (neighbour.rect.contains(x, y)) {
      return LayoutHit(
        zone: 'neighbour',
        id: neighbour.after ? 'after' : 'before',
      );
    }
  }
  return const LayoutHit(zone: 'background');
}

/// Кадр, прочитанный из строки потока — для разбора и проверок.
class LayoutFrame {
  /// Создаёт кадр.
  const LayoutFrame({
    required this.viewport,
    required this.regions,
    this.sheet,
    this.n = 0,
    this.t = 0,
    this.moving = false,
  });

  /// Номер строки.
  final int n;

  /// Время по часам записи.
  final int t;

  /// Кадр «в движении».
  final bool moving;

  /// Окно.
  final LayoutViewport viewport;

  /// Зоны.
  final List<LayoutRegion> regions;

  /// Лист книги; `null` — книги на экране нет.
  final SheetGeometry? sheet;

  /// Что лежало в точке ([x], [y]) окна.
  LayoutHit locate(double x, double y) {
    return locateInFrame(
      viewport: viewport,
      regions: regions,
      sheet: sheet,
      x: x,
      y: y,
    );
  }

  /// Читает строку потока; `null` — не кадр.
  static LayoutFrame? fromJson(Map<String, Object?> raw) {
    final Object? view = raw['viewport'];
    if (view is! Map<String, Object?>) {
      return null;
    }
    final double? width = _number(view['w']);
    final double? height = _number(view['h']);
    if (width == null || height == null) {
      return null;
    }
    final List<LayoutRegion> regions = <LayoutRegion>[];
    final Object? zones = raw['regions'];
    if (zones is List<Object?>) {
      for (final Object? zone in zones) {
        if (zone is! Map<String, Object?>) {
          continue;
        }
        final LayoutRect? rect = LayoutRect.fromJson(zone['rect']);
        if (rect == null) {
          continue;
        }
        final Object? z = zone['z'];
        final Object? id = zone['id'];
        final Object? info = zone['info'];
        regions.add(
          LayoutRegion(
            kind: _kind(zone['kind']),
            id: id is String ? id : '',
            rect: rect,
            z: z is int ? z : 0,
            clipped: zone['clip'] == true,
            info: info is Map<String, Object?>
                ? info
                : const <String, Object?>{},
            marks: _marks(zone['marks']),
          ),
        );
      }
    }
    final Object? n = raw['n'];
    final Object? t = raw['t'];
    return LayoutFrame(
      n: n is int ? n : 0,
      t: t is int ? t : 0,
      moving: raw['moving'] == true,
      viewport: LayoutViewport(
        width: width,
        height: height,
        dpr: _number(view['dpr']) ?? 1,
      ),
      regions: regions,
      sheet: _sheet(raw['sheet']),
    );
  }

  static double? _number(Object? value) {
    return value is num ? value.toDouble() : null;
  }

  static List<LayoutMark> _marks(Object? raw) {
    if (raw is! List<Object?>) {
      return const <LayoutMark>[];
    }
    final List<LayoutMark> marks = <LayoutMark>[];
    for (final Object? item in raw) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      final Object? id = item['id'];
      final double? x = _number(item['x']);
      final double? y = _number(item['y']);
      final double? r = _number(item['r']);
      if (id is String && x != null && y != null && r != null) {
        marks.add(LayoutMark(id: id, x: x, y: y, r: r));
      }
    }
    return marks;
  }

  /// Незнакомый вид — экран целиком.
  static LayoutKind _kind(Object? wire) {
    for (final LayoutKind kind in LayoutKind.values) {
      if (kind.wire == wire) {
        return kind;
      }
    }
    return LayoutKind.screen;
  }

  static SheetGeometry? _sheet(Object? raw) {
    if (raw is! Map<String, Object?>) {
      return null;
    }
    final double? scale = _number(raw['scale']);
    final LayoutRect? sheet = LayoutRect.fromJson(raw['rect']);
    final LayoutRect? content = LayoutRect.fromJson(raw['content']);
    final LayoutRect? strip = LayoutRect.fromJson(raw['strip']);
    final Object? pages = raw['pages'];
    if (scale == null ||
        sheet == null ||
        content == null ||
        strip == null ||
        pages is! List<Object?>) {
      return null;
    }
    final List<LayoutPage> placed = <LayoutPage>[];
    for (final Object? page in pages) {
      if (page is! Map<String, Object?>) {
        continue;
      }
      final Object? number = page['page'];
      final double? x = _number(page['x']);
      final double? y = _number(page['y']);
      final double? w = _number(page['w']);
      final double? h = _number(page['h']);
      if (number is! int || x == null || y == null || w == null || h == null) {
        continue;
      }
      placed.add(LayoutPage(page: number, x: x, y: y, width: w, height: h));
    }
    final List<LayoutNeighbour> neighbours = <LayoutNeighbour>[];
    final Object? around = raw['neighbours'];
    if (around is List<Object?>) {
      for (final Object? neighbour in around) {
        if (neighbour is! Map<String, Object?>) {
          continue;
        }
        final LayoutRect? rect = LayoutRect.fromJson(neighbour['rect']);
        if (rect != null) {
          neighbours.add(
            LayoutNeighbour(after: neighbour['side'] == 'after', rect: rect),
          );
        }
      }
    }
    final Object? index = raw['strip_index'];
    final Object? strips = raw['strips'];
    return SheetGeometry(
      scale: scale,
      pages: placed,
      sheet: sheet,
      content: content,
      strip: strip,
      stripIndex: index is int ? index : 1,
      strips: strips is int ? strips : 1,
      neighbours: neighbours,
    );
  }
}
