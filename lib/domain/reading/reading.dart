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

/// Ориентация экрана.
///
/// **Не входные данные геометрии, а способ Android повернуть экран.**
/// Раньше положение экрана подавалось в математику деления страницы, и
/// на ПК, где ориентации нет вовсе, эта математика работала вслепую.
/// Теперь геометрия получает форму области показа числом ([DisplayArea]),
/// а ориентация — это только то, о чём просят систему.
///
/// В схеме базы поле осталось от прежнего решения хранить настройки
/// отдельно для каждого положения экрана. От него отказались: читатель
/// настроил книгу один раз и ждёт её такой же после поворота — и, когда
/// появится синхронизация, на другом устройстве тоже. Настройки книги
/// живут под [ScreenOrientation.portrait]; см. `kSettingsSlot`.
enum ScreenOrientation {
  /// Портретная.
  portrait,

  /// Альбомная.
  landscape,
}

/// Область показа: прямоугольник, в который вписывается лист.
///
/// Единицы не важны — важна только форма, — поэтому одна и та же величина
/// описывает и экран телефона, и окно на ПК. Именно этим она лучше
/// [ScreenOrientation]: у окна ориентации нет, а форма есть всегда, и
/// геометрия деления страницы обслуживает обе платформы одной функцией.
class DisplayArea {
  /// Создаёт область показа.
  const DisplayArea({required this.width, required this.height});

  /// Область неизвестна: экран ещё не разложен.
  ///
  /// Нужна не для красоты: пока область не измерена, выбирать раскладку не
  /// из чего, и честнее сказать «не знаю», чем принять решение по
  /// выдуманным числам.
  static const DisplayArea unknown = DisplayArea(width: 0, height: 0);

  /// Ширина.
  final double width;

  /// Высота.
  final double height;

  /// Есть ли что измерять.
  bool get isKnown =>
      width.isFinite && height.isFinite && width > 0 && height > 0;

  /// Широкая и низкая.
  bool get isLandscape => width > height;

  /// Положение экрана, соответствующее этой форме.
  ScreenOrientation get orientation =>
      isLandscape ? ScreenOrientation.landscape : ScreenOrientation.portrait;

  /// Та же область, повёрнутая на четверть оборота.
  DisplayArea get turned => DisplayArea(width: height, height: width);

  /// Та же область в заданном положении экрана.
  ///
  /// Стороны берутся по длине, а не переставляются как попало: повернув
  /// телефон, читатель получает ту же пару чисел в другом порядке, и
  /// выбор раскладки от этого не должен скакать.
  DisplayArea oriented(ScreenOrientation orientation) {
    final double short = width < height ? width : height;
    final double long = width < height ? height : width;
    return orientation == ScreenOrientation.landscape
        ? DisplayArea(width: long, height: short)
        : DisplayArea(width: short, height: long);
  }

  @override
  bool operator ==(Object other) {
    return other is DisplayArea &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'DisplayArea(${width}x$height)';
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

/// Под каким ключом лежат настройки книги.
///
/// Один на книгу. Поле ориентации в схеме осталось от прежнего деления
/// и заполняется всегда одинаково: менять таблицу с данными живых
/// читателей ради снятого признака дороже, чем не пользоваться колонкой.
const ScreenOrientation kSettingsSlot = ScreenOrientation.portrait;

/// Насколько по умолчанию гаснет то, что сейчас не читается.
const double kDefaultDimOutside = 0.6;

/// Сильнее этого гасить нельзя.
///
/// Полная чернота вернула бы обрезку, от которой мы и уходим: смысл
/// затемнения в том, что страница остаётся видна целиком и читатель
/// понимает, где он на ней стоит.
const double kMaxDimOutside = 0.9;

/// Приводит силу затемнения к допустимому диапазону.
double clampDimOutside(double value) {
  if (!value.isFinite || value <= 0) {
    return 0;
  }
  return value > kMaxDimOutside ? kMaxDimOutside : value;
}

/// Настройки чтения одной книги.
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
    this.stripFit = 1,
    this.dimOutside = kDefaultDimOutside,
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

  /// Насколько уменьшена полоса: 1 — вписана в экран вплотную.
  ///
  /// Меньше единицы означает запас по краям: крайняя строка полосы уходит
  /// от закруглённого угла и выреза камеры. Подбирается он один раз — под
  /// кегль этой книги и это устройство, — и повторять подбор на каждой
  /// странице читатель не должен, поэтому значение живёт в настройках
  /// книги. Страница при этом **перерисовывается** мельче, а не
  /// сжимается растром: текст остаётся резким.
  final double stripFit;

  /// Насколько гаснет часть страницы, которую сейчас не читают.
  ///
  /// В режимах половины и трети страница видна целиком: читаемая полоса
  /// занимает максимум экрана, а всё остальное уходит в тень. Так место
  /// на странице остаётся понятным — сколько прочитано, сколько осталось
  /// до конца листа, — и при этом глаз не цепляется за соседние строки.
  final double dimOutside;

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
    double? stripFit,
    double? dimOutside,
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
      stripFit: stripFit ?? this.stripFit,
      dimOutside: dimOutside ?? this.dimOutside,
    );
  }
}

/// Прогресс и настройки чтения. Реализация живёт в `infrastructure`.
abstract interface class ReadingRepository {
  /// Позиция в книге или `null`, если книгу ещё не открывали.
  Future<ReadingPosition?> position(String bookId);

  /// Живая позиция: пригодится индикатору прогресса в библиотеке.
  Stream<ReadingPosition?> watchPosition(String bookId);

  /// Живые позиции всех книг разом, ключ — идентификатор книги.
  ///
  /// Полка показывает прогресс на каждой карточке. Отдельный запрос на
  /// книгу означал бы на библиотеке в триста книг триста живых запросов
  /// к базе одновременно — тот случай, когда правильная по виду мелочь
  /// складывается в неработающий экран.
  Stream<Map<String, ReadingPosition>> watchPositions();

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
