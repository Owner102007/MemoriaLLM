import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/map/map_builder.dart';
import 'package:memoria/sno/index/shelf_reading.dart';

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

  @override
  ShelfReadingProgress get progress => _shown;

  @override
  ShelfIndexSummary? get summary => _result;

  @override
  void start({Duration delay = Duration.zero}) {
    starts++;
  }

  /// Показывает ход [progress] и итог [summary].
  void show(ShelfReadingProgress progress, {ShelfIndexSummary? summary}) {
    _shown = progress;
    _result = summary;
    notifyListeners();
  }
}
