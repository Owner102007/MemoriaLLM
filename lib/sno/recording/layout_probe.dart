/// Кадры раскладки на экране (SNO-F-REC-03, SNO-ALG-REC-02) — зоны в
/// дереве виджетов и слой, который их собирает.
///
/// Зона помечается обёрткой [LayoutProbe] с видом и именем; лист книги —
/// [LayoutSheetProbe] с его геометрией. Пока запись идёт, слой записи
/// ([LayoutLayer]) после каждого кадра отрисовки снимает места видимых
/// зон в координатах окна и решает правилами [LayoutPacer], писать ли
/// кадр. Вне записи слой не заведён, а обёртки — пустые: в основном
/// приложении над ними нет [LayoutScope], и они ничего не делают.
library;

import 'dart:async';

import 'package:flutter/rendering.dart' show RenderExcludeSemantics;
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
      final ({LayoutRect rect, List<int> path})? seen = _seen(box, root);
      if (seen == null || !seen.rect.overlaps(window)) {
        continue;
      }
      found.add((
        path: seen.path,
        region: LayoutRegion(
          kind: probe.widget.kind,
          id: probe.widget.id,
          rect: seen.rect.rounded,
        ),
      ));
    }
    // Порядок наложения — порядок отрисовки: кто нарисован позже, тот
    // выше. Он же порядок обхода дерева.
    found.sort((a, b) => _comparePaths(a.path, b.path));
    final List<LayoutRegion> regions = <LayoutRegion>[
      for (int i = 0; i < found.length; i++)
        LayoutRegion(
          kind: found[i].region.kind,
          id: found[i].region.id,
          rect: found[i].region.rect,
          z: i,
        ),
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
  static ({LayoutRect rect, List<int> path})? _seen(
    RenderBox? box,
    RenderBox root,
  ) {
    if (box == null || !box.attached || !box.hasSize) {
      return null;
    }
    final List<int> path = <int>[];
    RenderObject child = box;
    RenderObject? parent = child.parent;
    while (parent != null && !identical(child, root)) {
      if (!_onStage(parent, child)) {
        return null;
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
    final Rect rect = MatrixUtils.transformRect(matrix, Offset.zero & box.size);
    return (
      rect: LayoutRect(rect.left, rect.top, rect.width, rect.height),
      path: path.reversed.toList(),
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
class LayoutProbe extends StatefulWidget {
  /// Создаёт зону.
  const LayoutProbe({
    required this.kind,
    required this.child,
    this.id = '',
    this.active = true,
    super.key,
  });

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
