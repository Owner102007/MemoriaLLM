import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/map/map_builder.dart';
import 'package:memoria/application/map/shelf_reading.dart';

import 'fake_reading.dart';
import 'recording_fakes.dart';

/// Подготовка книг, состоянием которой распоряжается тест
/// (SNO-F-IDX-04).
///
/// Настоящий проход здесь не идёт: проверяется, что экран показывает
/// по его ходу и итогу, когда просит начать и когда велит постоять.
class ShownReading extends ShelfReading {
  /// Создаёт подготовку поверх базы теста.
  ShownReading(AppData data)
    : super(
        library: data.library,
        opener: FakeDocumentOpener(FakeReaderDocument.blank(1)),
        texts: data.pageTexts,
        settings: MemorySettings(),
        map: MapBuilder(
          library: data.library,
          categories: data.categories,
          texts: data.pageTexts,
          store: data.bookMap,
        ),
      );

  ShelfReadingProgress _shown = const ShelfReadingProgress();
  ShelfIndexSummary? _result;

  /// Сколько раз экран просил начать подготовку.
  int starts = 0;

  /// Сколько раз читатель нажал «Остановить» (F-MAP-11).
  int stops = 0;

  bool _halted = false;

  @override
  bool get stopped => _halted;

  /// Показанный ход идёт — значит, и проход идёт, как у настоящего.
  @override
  bool get running => _shown.busy;

  @override
  void stop() {
    stops++;
    _halted = true;
    show(const ShelfReadingProgress());
  }

  @override
  ShelfReadingProgress get progress => _shown;

  @override
  ShelfIndexSummary? get summary => _result;

  @override
  void start({Duration delay = Duration.zero}) {
    starts++;
    _halted = false;
  }

  /// Показывает ход [progress] и итог [summary].
  void show(ShelfReadingProgress progress, {ShelfIndexSummary? summary}) {
    _shown = progress;
    _result = summary;
    notifyListeners();
  }
}
