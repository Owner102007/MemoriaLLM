/// Режим отображения страницы. Смысл режимов — в `CLAUDE.md`: половина
/// страницы увеличивает кегль вдвое, не ломая вёрстку. Реализация — S4.
enum PageDisplayMode {
  /// Страница целиком.
  full,

  /// Половина страницы (или одна колонка из двух).
  half,

  /// Треть страницы.
  third,

  /// Разворот из двух страниц.
  spread,

  /// Половина разворота: верх обеих страниц, потом низ обеих.
  spreadHalf,
}

/// Как листается книга.
///
/// Настройка устройства, а не книги: привычка листать пальцем вбок или
/// прокручивать лентой не меняется от книги к книге.
enum PageFlow {
  /// Непрерывная лента страниц сверху вниз.
  continuous,

  /// Страница за страницей — с читательской рамкой и переходами по
  /// фрагментам.
  paged,
}

/// Светофильтр поверх страницы. Шейдеры появятся в S4.
enum ReadingFilter {
  /// Без фильтра.
  none,

  /// Ночной красный монохром.
  nightRed,

  /// Тёплый: снижение синей составляющей.
  warm,

  /// Сепия.
  sepia,

  /// Инверсия с двойной инверсией картинок.
  invert,
}

/// Ориентация экрана. Настройки чтения хранятся отдельно для каждой:
/// то, что удобно в портрете, в альбоме обычно неудобно.
enum ScreenOrientation {
  /// Портретная.
  portrait,

  /// Альбомная.
  landscape,
}

/// Рамка обрезки полей в долях страницы: `0` — левый верхний угол,
/// `1` — правый нижний.
class CropBox {
  /// Создаёт рамку.
  const CropBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Страница целиком — рамка, ничего не обрезающая.
  static const CropBox full = CropBox(left: 0, top: 0, right: 1, bottom: 1);

  /// Левая граница.
  final double left;

  /// Верхняя граница.
  final double top;

  /// Правая граница.
  final double right;

  /// Нижняя граница.
  final double bottom;

  /// Ширина рамки в долях страницы.
  double get width => right - left;

  /// Высота рамки в долях страницы.
  double get height => bottom - top;

  /// Рамка внутри страницы и не вывернута наизнанку. Автообрезка обязана
  /// проверять себя этим: пустая или перевёрнутая рамка — это чёрный
  /// экран вместо текста.
  bool get isValid =>
      left >= 0 &&
      top >= 0 &&
      right <= 1 &&
      bottom <= 1 &&
      width > 0 &&
      height > 0;

  @override
  bool operator ==(Object other) {
    return other is CropBox &&
        other.left == left &&
        other.top == top &&
        other.right == right &&
        other.bottom == bottom;
  }

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'CropBox($left, $top, $right, $bottom)';
}

/// Позиция чтения.
///
/// Хранится страницей и смещением, а не «номером экрана»: смена режима
/// отображения, поворот экрана или переход на другое устройство не должны
/// сбивать место.
class ReadingPosition {
  /// Создаёт позицию.
  const ReadingPosition({
    required this.bookId,
    required this.page,
    this.fragment = 0,
    this.offset = 0,
    this.progress = 0,
    this.updatedAt,
  });

  /// Книга.
  final String bookId;

  /// Номер страницы, начиная с единицы.
  final int page;

  /// Номер фрагмента внутри страницы для режимов половины и трети.
  final int fragment;

  /// Смещение внутри фрагмента, доля от 0 до 1.
  final double offset;

  /// Доля прочитанного от всей книги, от 0 до 1.
  final double progress;

  /// Когда позиция обновлялась. Заполняется репозиторием при записи.
  final DateTime? updatedAt;

  /// Копия с изменёнными полями.
  ReadingPosition copyWith({
    int? page,
    int? fragment,
    double? offset,
    double? progress,
    DateTime? updatedAt,
  }) {
    return ReadingPosition(
      bookId: bookId,
      page: page ?? this.page,
      fragment: fragment ?? this.fragment,
      offset: offset ?? this.offset,
      progress: progress ?? this.progress,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReadingPosition &&
        other.bookId == bookId &&
        other.page == page &&
        other.fragment == fragment &&
        other.offset == offset &&
        other.progress == progress;
  }

  @override
  int get hashCode => Object.hash(bookId, page, fragment, offset, progress);
}

/// Настройки чтения одной книги в одной ориентации экрана.
class BookReadingSettings {
  /// Создаёт настройки.
  const BookReadingSettings({
    required this.bookId,
    required this.orientation,
    this.displayMode = PageDisplayMode.full,
    this.autoCrop = false,
    this.ignoreRunningHeads = true,
    this.manualCrop,
    this.filter = ReadingFilter.none,
    this.filterIntensity = 0,
    this.brightness = 1,
    this.contrast = 1,
    this.gamma = 1,
  });

  /// Книга.
  final String bookId;

  /// Ориентация экрана.
  final ScreenOrientation orientation;

  /// Режим отображения.
  final PageDisplayMode displayMode;

  /// Обрезать поля автоматически.
  ///
  /// По умолчанию выключено: страница показывается ровно такой, какой её
  /// свёрстали, со всеми полями. Обрезка — отдельная возможность для
  /// того, кто её осознанно захотел, а не поведение по умолчанию, из-за
  /// которого книга каждый раз выглядит чуть иначе.
  final bool autoCrop;

  /// Не считать колонтитулы содержимым при автообрезке.
  final bool ignoreRunningHeads;

  /// Рамка, выставленная руками. Если задана, она главнее автообрезки.
  final CropBox? manualCrop;

  /// Светофильтр.
  final ReadingFilter filter;

  /// Сила фильтра, от 0 до 1.
  final double filterIntensity;

  /// Яркость: 1 — как есть, меньше — темнее системного минимума.
  final double brightness;

  /// Контраст: 1 — как есть. Больше нужно бледным сканам.
  final double contrast;

  /// Гамма: 1 — как есть.
  final double gamma;

  /// Копия с изменёнными полями.
  BookReadingSettings copyWith({
    PageDisplayMode? displayMode,
    bool? autoCrop,
    bool? ignoreRunningHeads,
    CropBox? manualCrop,
    ReadingFilter? filter,
    double? filterIntensity,
    double? brightness,
    double? contrast,
    double? gamma,
  }) {
    return BookReadingSettings(
      bookId: bookId,
      orientation: orientation,
      displayMode: displayMode ?? this.displayMode,
      autoCrop: autoCrop ?? this.autoCrop,
      ignoreRunningHeads: ignoreRunningHeads ?? this.ignoreRunningHeads,
      manualCrop: manualCrop ?? this.manualCrop,
      filter: filter ?? this.filter,
      filterIntensity: filterIntensity ?? this.filterIntensity,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      gamma: gamma ?? this.gamma,
    );
  }
}

/// Прогресс и настройки чтения. Реализация живёт в `infrastructure`.
abstract interface class ReadingRepository {
  /// Позиция в книге или `null`, если книгу ещё не открывали.
  Future<ReadingPosition?> position(String bookId);

  /// Живая позиция: пригодится индикатору прогресса в библиотеке.
  Stream<ReadingPosition?> watchPosition(String bookId);

  /// Сохраняет позицию.
  Future<void> savePosition(ReadingPosition position);

  /// Настройки чтения. Если их ещё нет, возвращает значения по умолчанию,
  /// а не `null`: у экрана чтения всегда должен быть валидный режим.
  Future<BookReadingSettings> settings(
    String bookId,
    ScreenOrientation orientation,
  );

  /// Сохраняет настройки чтения.
  Future<void> saveSettings(BookReadingSettings settings);
}
