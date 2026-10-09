/// Кадры раскладки на экране (SNO-F-REC-03, SNO-ALG-REC-02) — зоны в
/// дереве виджетов и слой, который их собирает.
///
/// Зона помечается обёрткой [LayoutProbe] с видом и именем; лист книги —
/// [LayoutSheetProbe] с его геометрией. Пока запись идёт, слой записи
/// ([LayoutLayer]) после каждого кадра отрисовки снимает места видимых
/// зон в координатах окна и решает правилами [LayoutPacer], писать ли
/// кадр. Вне записи слой не заведён, а обёртки — пустые: в основном
/// приложении над ними нет [LayoutScope], и они ничего не делают.
///
/// Шаг 31 (ET-05): зона, которую прячет край прокрутки, ложится в кадр
/// только видимой частью и с пометкой `clip`, а целиком спрятанная — не
/// ложится вовсе; обёртка отдаёт ещё сведения о зоне (`info`) и точки
/// внутри неё (`marks`) — звёзды карты.
library;

import 'dart:async';

import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, RenderExcludeSemantics;
import 'package:flutter/widgets.dart';

import 'layout_frames.dart';
import 'session.dart';

/// Доска зон: кто помечен и где он сейчас.
///
/// Живёт столько, сколько слой записи; обёртки встают на неё и уходят с
/// неё сами, а снимает места только идущая запись.
class LayoutBoard {
  final Set<_ProbeState> _probes = <_ProbeState>{};
  final Set<_SheetProbeState> _sheets = <_SheetProbeState>{};

  /// Сколько зон помечено сейчас — для проверок.
  int get probes => _probes.length;

  /// Снимает, что видно в окне [root] размером [viewport].
  ///
  /// Зона, которой не видно — экран под другим маршрутом, неоткрытая
  /// вкладка, панель, которая уехала за край, — в снимок не входит.
  LayoutSnapshot sample(RenderBox root, LayoutViewport viewport) {
    final LayoutRect window = LayoutRect(0, 0, viewport.width, viewport.height);
    final List<({List<int> path, LayoutRegion region})> found =
        <({List<int> path, LayoutRegion region})>[];
    for (final _ProbeState probe in _probes) {
      if (!probe.widget.active) {
        continue;
      }
      final RenderBox? box = probe.box;
      final _Seen? seen = _seen(box, root);
      if (seen == null || !seen.rect.overlaps(window)) {
        continue;
      }
      found.add((
        path: seen.path,
        region: LayoutRegion(
          kind: probe.widget.kind,
          id: probe.widget.id,
          rect: seen.rect.rounded,
          clipped: seen.clipped,
          info: _info(probe),
          marks: _marks(probe, seen),
        ),
      ));
    }
    // Порядок наложения — порядок отрисовки: кто нарисован позже, тот
    // выше. Он же порядок обхода дерева.
    found.sort((a, b) => _comparePaths(a.path, b.path));
    final List<LayoutRegion> regions = <LayoutRegion>[
      for (int i = 0; i < found.length; i++) found[i].region.atZ(i),
    ];
    SheetGeometry? sheet;
    for (final _SheetProbeState probe in _sheets) {
      final RenderBox? box = probe.box;
      if (box == null || _seen(box, root) == null) {
        continue;
      }
      final SheetGeometry? local = _geometry(probe);
      if (local == null) {
        continue;
      }
      sheet = local.placed(_placeOf(box, root));
      break;
    }
    return LayoutSnapshot(viewport: viewport, regions: regions, sheet: sheet);
  }

  /// Сведения зоны; не посчитались — зона без них, а не упавший кадр.
  static Map<String, Object?> _info(_ProbeState probe) {
    final Map<String, Object?> Function()? info = probe.widget.info;
    if (info == null) {
      return const <String, Object?>{};
    }
    try {
      return info();
    } on Object {
      return const <String, Object?>{};
    }
  }

  /// Точки зоны в окне: тем же переводом, что место зоны. Точка, чей
  /// круг не задевает видимую часть зоны, в кадр не идёт.
  static List<LayoutMark> _marks(_ProbeState probe, _Seen seen) {
    final List<LayoutMark> Function()? marks = probe.widget.marks;
    if (marks == null) {
      return const <LayoutMark>[];
    }
    final List<LayoutMark> local;
    try {
      local = marks();
    } on Object {
      return const <LayoutMark>[];
    }
    final LayoutRect rect = seen.rect;
    final List<LayoutMark> placed = <LayoutMark>[];
    for (final LayoutMark mark in local) {
      final (double x, double y) = seen.place.point(mark.x, mark.y);
      final double r = mark.r * seen.place.scale;
      if (x + r < rect.left ||
          x - r > rect.right ||
          y + r < rect.top ||
          y - r > rect.bottom) {
        continue;
      }
      placed.add(LayoutMark(id: mark.id, x: x, y: y, r: r));
    }
    return placed;
  }

  static SheetGeometry? _geometry(_SheetProbeState probe) {
    try {
      return probe.widget.geometry();
    } on Object {
      // Геометрия не посчиталась — кадр без листа, а не упавший экран.
      return null;
    }
  }

  /// Где [box] в окне [root] и его путь в дереве; `null` — его не
  /// видно.
  ///
  /// Шаг 31: список держит строки и за своим краем — запас прокрутки, —
  /// и служба доступности их обходит. Поэтому место зоны обрезается
  /// каждой прокруткой, через которую она видна; ничего не осталось —
  /// зоны не видно.
  static _Seen? _seen(RenderBox? box, RenderBox root) {
    if (box == null || !box.attached || !box.hasSize) {
      return null;
    }
    final List<int> path = <int>[];
    final List<RenderBox> scrolls = <RenderBox>[];
    RenderObject child = box;
    RenderObject? parent = child.parent;
    while (parent != null && !identical(child, root)) {
      if (!_onStage(parent, child)) {
        return null;
      }
      if (parent is RenderBox &&
          parent is RenderAbstractViewport &&
          parent.hasSize) {
        scrolls.add(parent);
      }
      path.add(_indexOf(parent, child));
      child = parent;
      parent = child.parent;
    }
    if (!identical(child, root)) {
      // Не под слоем записи: другое окно или уже снятое дерево.
      return null;
    }
    final Matrix4 matrix = box.getTransformTo(root);
    final Rect drawn = MatrixUtils.transformRect(
      matrix,
      Offset.zero & box.size,
    );
    LayoutRect rect = LayoutRect(
      drawn.left,
      drawn.top,
      drawn.width,
      drawn.height,
    );
    bool clipped = false;
    for (final RenderBox scroll in scrolls) {
      final Rect edge = MatrixUtils.transformRect(
        scroll.getTransformTo(root),
        Offset.zero & scroll.size,
      );
      final LayoutRect? inside = rect.intersect(
        LayoutRect(edge.left, edge.top, edge.width, edge.height),
      );
      if (inside == null) {
        return null;
      }
      // Сравнение с допуском: общая часть, посчитанная заново, может
      // разойтись с целым прямоугольником в последнем знаке.
      if (inside.left > rect.left + 0.05 ||
          inside.top > rect.top + 0.05 ||
          inside.right < rect.right - 0.05 ||
          inside.bottom < rect.bottom - 0.05) {
        clipped = true;
        rect = inside;
      }
    }
    return _Seen(
      rect: rect,
      path: path.reversed.toList(),
      clipped: clipped,
      place: _placeOf(box, root),
    );
  }

  /// Перевод места листа [box] в окно [root]: сдвиг и масштаб.
  static LayoutPlace _placeOf(RenderBox box, RenderBox root) {
    final Matrix4 matrix = box.getTransformTo(root);
    final Offset origin = MatrixUtils.transformPoint(matrix, Offset.zero);
    final Offset unit = MatrixUtils.transformPoint(matrix, const Offset(1, 0));
    final double scale = (unit - origin).distance;
    return LayoutPlace(
      scale: scale > 0 ? scale : 1,
      dx: origin.dx,
      dy: origin.dy,
    );
  }

  /// Видит ли [parent] своего ребёнка [child] на экране.
  ///
  /// Тех, кого не видно, не обходит и сама служба доступности: экран под
  /// закрывшим его маршрутом, неоткрытая вкладка `IndexedStack`, ветка
  /// `Offstage`, строки списка за краем. Поэтому вопрос задаётся ей. Одно
  /// исключение — `ExcludeSemantics`: он прячет ветку от диктора, а не от
  /// глаз.
  static bool _onStage(RenderObject parent, RenderObject child) {
    if (parent is RenderExcludeSemantics) {
      return true;
    }
    bool found = false;
    parent.visitChildrenForSemantics((RenderObject other) {
      if (identical(other, child)) {
        found = true;
      }
    });
    return found;
  }

  static int _indexOf(RenderObject parent, RenderObject child) {
    int index = 0;
    int found = 0;
    parent.visitChildren((RenderObject other) {
      if (identical(other, child)) {
        found = index;
      }
      index++;
    });
    return found;
  }

  static int _comparePaths(List<int> a, List<int> b) {
    final int common = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < common; i++) {
      if (a[i] != b[i]) {
        return a[i].compareTo(b[i]);
      }
    }
    return a.length.compareTo(b.length);
  }
}

/// Что слой увидел у одной зоны: место в окне (видимая часть), путь в
/// дереве, подрезана ли она прокруткой и перевод её точек в окно.
class _Seen {
  const _Seen({
    required this.rect,
    required this.path,
    required this.clipped,
    required this.place,
  });

  final LayoutRect rect;
  final List<int> path;
  final bool clipped;
  final LayoutPlace place;
}

/// Доска зон над приложением: её ставит слой записи.
class LayoutScope extends InheritedWidget {
  /// Создаёт область.
  const LayoutScope({required this.board, required super.child, super.key});

  /// Доска.
  final LayoutBoard board;

  /// Доска над [context]; `null` — записи в сборке нет.
  static LayoutBoard? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LayoutScope>()?.board;
  }

  @override
  bool updateShouldNotify(LayoutScope oldWidget) {
    return !identical(oldWidget.board, board);
  }
}

/// Зона кадра раскладки (SNO-F-REC-03): вид [kind], имя [id].
///
/// Обёртка ничего не рисует и нажатий не ловит. Вне записи — и в
/// основном приложении, где над ней нет [LayoutScope], — она пустая.
/// [info] и [marks] спрашиваются, только когда слой снимает кадр.
class LayoutProbe extends StatefulWidget {
  /// Создаёт зону.
  const LayoutProbe({
    required this.kind,
    required this.child,
    this.id = '',
    this.active = true,
    this.info,
    this.marks,
    super.key,
  });

  /// Что ещё известно о зоне — значения, которые ложатся в JSON
  /// (шаг 31): категория книги, сдвиг полки, камера карты.
  final Map<String, Object?> Function()? info;

  /// Точки внутри зоны в её собственных координатах (шаг 31): звёзды
  /// карты, которые рисует художник, а не виджеты.
  final List<LayoutMark> Function()? marks;

  /// Вид.
  final LayoutKind kind;

  /// Имя внутри вида.
  final String id;

  /// Видна ли зона: панель, которая уезжает за край, — нет.
  final bool active;

  /// Что помечено.
  final Widget child;

  @override
  State<LayoutProbe> createState() => _ProbeState();
}

class _ProbeState extends State<LayoutProbe> {
  final GlobalKey _target = GlobalKey();
  LayoutBoard? _board;

  RenderBox? get box {
    final RenderObject? object = _target.currentContext?.findRenderObject();
    return object is RenderBox ? object : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final LayoutBoard? board = LayoutScope.maybeOf(context);
    if (!identical(board, _board)) {
      _board?._probes.remove(this);
      _board = board;
      board?._probes.add(this);
    }
  }

  @override
  void dispose() {
    _board?._probes.remove(this);
    _board = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _target, child: widget.child);
  }
}

/// Лист книги в кадре раскладки (SNO-ALG-REC-02, шаг 2).
///
/// Стоит на месте листа — во весь его размер — и знает геометрию листа
/// в координатах этого места ([geometry]); в окно её переводит слой
/// записи. Ничего не рисует и нажатий не ловит.
class LayoutSheetProbe extends StatefulWidget {
  /// Создаёт лист.
  const LayoutSheetProbe({required this.geometry, super.key});

  /// Геометрия листа на месте обёртки; `null` — листа сейчас нет.
  final SheetGeometry? Function() geometry;

  @override
  State<LayoutSheetProbe> createState() => _SheetProbeState();
}

class _SheetProbeState extends State<LayoutSheetProbe> {
  final GlobalKey _target = GlobalKey();
  LayoutBoard? _board;

  RenderBox? get box {
    final RenderObject? object = _target.currentContext?.findRenderObject();
    return object is RenderBox ? object : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final LayoutBoard? board = LayoutScope.maybeOf(context);
    if (!identical(board, _board)) {
      _board?._sheets.remove(this);
      _board = board;
      board?._sheets.add(this);
    }
  }

  @override
  void dispose() {
    _board?._sheets.remove(this);
    _board = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: SizedBox.expand(key: _target));
  }
}

/// Слой, который пишет кадры раскладки, пока запись идёт
/// (SNO-F-REC-03).
///
/// После каждого кадра отрисовки снимает места зон доски в окне
/// ([LayoutBoard.sample]) и отдаёт снимок правилам [LayoutPacer]:
/// начало изменения — кадр «в движении» сразу, конец — устоявшийся
/// через [kLayoutSettle] тишины. Обратного вызова после кадра нет, пока
/// запись не идёт: слой заводит старт записи и снимает её остановка.
class LayoutLayer {
  /// Создаёт слой.
  LayoutLayer({
    required RecordingSession session,
    required LayoutBoard board,
    required RenderBox? Function() root,
    required LayoutViewport Function() viewport,
  }) : _session = session,
       _board = board,
       _root = root,
       _viewport = viewport;

  final RecordingSession _session;
  final LayoutBoard _board;
  final RenderBox? Function() _root;
  final LayoutViewport Function() _viewport;
  final LayoutPacer _pacer = LayoutPacer();

  /// Когда по часам записи случилось последнее изменение: устоявшийся
  /// кадр помечен им, а не мигом, когда отсчитанная тишина кончилась, —
  /// раскладка такой стала тогда.
  int? _changedAt;
  bool _attached = false;
  bool _armed = false;
  Timer? _settle;

  /// Сколько слоёв сейчас слушает кадры отрисовки — для проверок:
  /// вне записи ни одного.
  static int listening = 0;

  /// Начинает слушать.
  void attach() {
    if (_attached) {
      return;
    }
    _attached = true;
    listening++;
    _arm();
    // Первый снимок — без ожидания пользователя: кадр отрисовки
    // заказывается сам.
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Перестаёт слушать; то, что не успело устояться, дописывается.
  void detach() {
    if (!_attached) {
      return;
    }
    _attached = false;
    listening--;
    _settle?.cancel();
    _settle = null;
    _flush();
  }

  void _arm() {
    if (_armed || !_attached) {
      return;
    }
    _armed = true;
    WidgetsBinding.instance.addPostFrameCallback(_afterFrame);
  }

  void _afterFrame(Duration stamp) {
    _armed = false;
    if (!_attached) {
      return;
    }
    _arm();
    final LayoutTracker? tracker = _session.layout;
    final RenderBox? root = _root();
    if (tracker == null || root == null || !root.hasSize) {
      return;
    }
    // Остановка записи дописывает то, что не успело устояться, — до
    // своей строки, тем же мигом.
    tracker.beforeFinish = () => _flushInto(tracker);
    final LayoutSnapshot snapshot = _board.sample(root, _viewport());
    final LayoutSnapshot? moving = _pacer.observe(
      snapshot,
      stamp.inMilliseconds,
    );
    if (moving != null) {
      tracker.frame(moving, t: _session.layoutNow, moving: true);
    }
    if (_pacer.changed) {
      _changedAt = _session.layoutNow;
      _settle?.cancel();
      _settle = Timer(kLayoutSettle, _flush);
    }
  }

  /// Тишина простояла — или слой снимают: устоявшийся кадр, если есть
  /// что писать.
  void _flush() {
    final LayoutTracker? tracker = _session.layout;
    if (tracker != null) {
      _flushInto(tracker);
    }
  }

  void _flushInto(LayoutTracker tracker) {
    _settle?.cancel();
    _settle = null;
    final LayoutSnapshot? settled = _pacer.settle();
    final int at = _changedAt ?? _session.layoutNow;
    _changedAt = null;
    if (settled != null) {
      tracker.frame(settled, t: at, moving: false);
    }
  }
}
