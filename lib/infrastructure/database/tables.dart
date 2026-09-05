import 'package:drift/drift.dart';

/// Колонки, общие для всех синхронизируемых таблиц.
///
/// Имена совпадают с теми, что ожидает `sqlite_crdt`: `hlc` — метка
/// изменения, `node_id` — устройство-автор, `modified` — когда строка
/// легла в эту базу, `is_deleted` — надгробие. Схема задаётся один раз
/// сейчас, чтобы сессия S10 добавляла движок слияния, а не переписывала
/// таблицы с данными живых пользователей.
mixin SyncedRow on Table {
  /// Метка изменения строки.
  TextColumn get hlc => text().withDefault(const Constant<String>(''))();

  /// Устройство, сделавшее изменение.
  TextColumn get nodeId => text().withDefault(const Constant<String>(''))();

  /// Когда изменение записано в эту базу.
  TextColumn get modified => text().withDefault(const Constant<String>(''))();

  /// Надгробие: строка удалена, но остаётся, пока об этом не узнают все
  /// устройства. Физическое удаление — дело сборки мусора.
  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant<bool>(false))();
}

/// Категории полки.
///
/// Объявлена раньше книг намеренно: колонка `category_id` в `books`
/// ссылается на эту таблицу, а drift разрешает ссылки по порядку
/// объявления.
@DataClassName('BookCategoryRow')
class BookCategories extends Table with SyncedRow {
  /// Идентификатор категории.
  TextColumn get id => text()();

  /// Название. Из него же выводятся узор и цвет подложки — см.
  /// `domain/library/category_style.dart`.
  TextColumn get title => text()();

  /// Порядок на полке. Меньше — выше.
  IntColumn get position => integer().withDefault(const Constant<int>(0))();

  /// Когда заведена.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Книги библиотеки.
@DataClassName('BookRow')
class Books extends Table with SyncedRow {
  /// Идентификатор книги.
  TextColumn get id => text()();

  /// Заголовок.
  TextColumn get title => text()();

  /// Автор.
  TextColumn get author => text().nullable()();

  /// Где лежит книга на этом устройстве — источник строкой.
  ///
  /// До S5.1 здесь был голый путь; теперь строка несёт ещё и вид
  /// источника (`file:`, `copy:`, `doc:`), потому что у документа
  /// Android пути нет вовсе. Имя колонки оставлено прежним намеренно:
  /// переписывать таблицу с книгами живых читателей ради названия
  /// колонки дороже, чем прочитать старую строку как путь — а
  /// `BookSource.decode` именно так её и читает.
  TextColumn get filePath => text()();

  /// Размер файла в байтах.
  IntColumn get fileSize => integer()();

  /// Отпечаток содержимого.
  TextColumn get fileHash => text()();

  /// Число страниц.
  IntColumn get pageCount => integer().nullable()();

  /// Язык книги.
  TextColumn get language => text().nullable()();

  /// Есть ли текстовый слой.
  BoolColumn get hasTextLayer => boolean().nullable()();

  /// Путь к кэшу обложки.
  TextColumn get coverPath => text().nullable()();

  /// Когда добавлена.
  DateTimeColumn get addedAt => dateTime()();

  /// Когда открывали в последний раз.
  DateTimeColumn get openedAt => dateTime().nullable()();

  /// Категория полки. `null` — постоянный раздел «Без категории».
  ///
  /// **Внешнего ключа здесь намеренно нет.** Он не смог бы делать свою
  /// работу: категорию мы удаляем надгробием, а не `DELETE`, и каскад при
  /// нём не срабатывает вовсе — книги возвращает в «Без категории»
  /// репозиторий, руками и в одной транзакции. Единственный случай, когда
  /// ключ пригодился бы, — физическая чистка, но и там ссылка в никуда
  /// безопасна: раскладка полки считает неизвестную категорию
  /// отсутствующей и книгу не теряет.
  ///
  /// Побочная выгода честная: колонку с внешним ключом SQLite не даёт
  /// удалить, а значит, миграцию нельзя было бы проверить на настоящем
  /// файле базы — тем самым способом, которым проверяются все прошлые.
  TextColumn get categoryId => text().nullable()();

  /// Место книги на полке внутри своей категории.
  ///
  /// Имеет смысл только в ручном порядке («Как расставил»); остальные
  /// сортировки его не читают, но и не стирают — расстановка ждёт
  /// возврата к ручному порядку, а не пропадает при первом же
  /// переключении.
  IntColumn get shelfPosition =>
      integer().withDefault(const Constant<int>(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Позиция чтения, по одной строке на книгу.
@DataClassName('ReadingProgressRow')
class ReadingProgress extends Table with SyncedRow {
  /// Книга.
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();

  /// Страница, начиная с единицы.
  IntColumn get page => integer().withDefault(const Constant<int>(1))();

  /// Фрагмент внутри страницы.
  IntColumn get fragment => integer().withDefault(const Constant<int>(0))();

  /// Смещение внутри фрагмента, доля от 0 до 1.
  RealColumn get offsetInFragment =>
      real().withDefault(const Constant<double>(0))();

  /// Доля прочитанного от книги.
  RealColumn get progress => real().withDefault(const Constant<double>(0))();

  /// Когда позиция обновлялась.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{bookId};
}

/// Настройки чтения книги в конкретной ориентации экрана.
@DataClassName('BookSettingsRow')
class BookSettings extends Table with SyncedRow {
  /// Книга.
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();

  /// Ориентация экрана.
  TextColumn get orientation => text()();

  /// Режим отображения.
  TextColumn get displayMode => text()();

  /// Обрезать поля автоматически.
  BoolColumn get autoCrop =>
      boolean().withDefault(const Constant<bool>(true))();

  /// Игнорировать колонтитулы при автообрезке.
  BoolColumn get ignoreRunningHeads =>
      boolean().withDefault(const Constant<bool>(true))();

  /// Левая граница рамки, выставленной руками.
  RealColumn get cropLeft => real().nullable()();

  /// Верхняя граница ручной рамки.
  RealColumn get cropTop => real().nullable()();

  /// Правая граница ручной рамки.
  RealColumn get cropRight => real().nullable()();

  /// Нижняя граница ручной рамки.
  RealColumn get cropBottom => real().nullable()();

  /// Светофильтр.
  TextColumn get filter => text()();

  /// Сила фильтра.
  RealColumn get filterIntensity =>
      real().withDefault(const Constant<double>(0))();

  /// Яркость.
  RealColumn get brightness => real().withDefault(const Constant<double>(1))();

  /// Контраст.
  RealColumn get contrast => real().withDefault(const Constant<double>(1))();

  /// Гамма.
  RealColumn get gamma => real().withDefault(const Constant<double>(1))();

  /// Насколько уменьшена полоса: 1 — вписана в экран вплотную.
  RealColumn get stripFit => real().withDefault(const Constant<double>(1))();

  /// Насколько гаснет часть страницы вне читаемой полосы.
  ///
  /// Значение по умолчанию продублировано числом намеренно: генератор
  /// drift переносит выражение в сгенерированный файл дословно, и ссылка
  /// на `kDefaultDimOutside` утащила бы за собой доменный импорт.
  RealColumn get dimOutside =>
      real().withDefault(const Constant<double>(0.6))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{bookId, orientation};
}

/// Цитаты.
@DataClassName('QuoteRow')
class Quotes extends Table with SyncedRow {
  /// Идентификатор.
  TextColumn get id => text()();

  /// Книга.
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();

  /// Страница.
  IntColumn get page => integer()();

  /// Текст цитаты.
  TextColumn get content => text()();

  /// Абзац вокруг выделения.
  TextColumn get context => text().nullable()();

  /// Цвет маркера.
  IntColumn get color => integer().nullable()();

  /// Когда сохранена.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Заметки читателя.
@DataClassName('NoteRow')
class Notes extends Table with SyncedRow {
  /// Идентификатор.
  TextColumn get id => text()();

  /// Книга.
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();

  /// Цитата, к которой привязана заметка.
  TextColumn get quoteId =>
      text().nullable().references(Quotes, #id, onDelete: KeyAction.setNull)();

  /// Страница.
  IntColumn get page => integer()();

  /// Текст заметки.
  TextColumn get body => text()();

  /// Когда создана.
  DateTimeColumn get createdAt => dateTime()();

  /// Когда изменялась.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Закладки.
@DataClassName('BookmarkRow')
class Bookmarks extends Table with SyncedRow {
  /// Идентификатор.
  TextColumn get id => text()();

  /// Книга.
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();

  /// Страница.
  IntColumn get page => integer()();

  /// Фрагмент внутри страницы.
  IntColumn get fragment => integer().withDefault(const Constant<int>(0))();

  /// Подпись.
  TextColumn get label => text().nullable()();

  /// Когда поставлена.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// История запросов к языковой модели. Она же кэш ответов.
@DataClassName('LlmQueryRow')
class LlmQueries extends Table with SyncedRow {
  /// Идентификатор.
  TextColumn get id => text()();

  /// Книга, если запрос сделан во время чтения.
  TextColumn get bookId =>
      text().nullable().references(Books, #id, onDelete: KeyAction.cascade)();

  /// Задача: `meaning` или `translate`.
  TextColumn get task => text()();

  /// Выделенный текст.
  TextColumn get selection => text()();

  /// Абзац вокруг выделения.
  TextColumn get context => text().nullable()();

  /// Язык книги.
  TextColumn get sourceLanguage => text().nullable()();

  /// Язык перевода.
  TextColumn get targetLanguage => text().nullable()();

  /// Ответ модели.
  TextColumn get answer => text().nullable()();

  /// Кто отвечал: `cloud` или `local`.
  TextColumn get source => text().nullable()();

  /// Имя модели.
  TextColumn get model => text().nullable()();

  /// Задержка ответа в миллисекундах.
  IntColumn get latencyMs => integer().nullable()();

  /// Текст ошибки.
  TextColumn get error => text().nullable()();

  /// Когда сделан запрос.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Файлы устройства, найденные обходом (S5.5).
///
/// **Полей CRDT здесь нет, и это решение, а не забывчивость.** Перечень
/// файлов на диске читателя не создавал никто: он не цитата и не заметка,
/// а слепок чужого устройства. В облако он не уезжает — как и индекс
/// поиска, построенный по нему. Второму устройству этот список
/// бесполезен: там другой диск.
///
/// Строка живёт на путь, а не на книгу: один и тот же файл лежит на
/// телефоне в трёх местах, и склеиваются такие записи по отпечатку —
/// уже при показе, в `groupDeviceFiles`.
@DataClassName('DeviceFileRow')
class DeviceFiles extends Table {
  /// Полный путь к файлу — он же ключ.
  TextColumn get path => text()();

  /// Размер в байтах.
  IntColumn get size => integer()();

  /// Время последнего изменения файла.
  DateTimeColumn get modifiedAt => dateTime()();

  /// Когда файл в последний раз попадался обходу.
  DateTimeColumn get seenAt => dateTime()();

  /// Отпечаток содержимого; пусто — ещё не считали.
  TextColumn get fingerprint => text().nullable()();

  /// Заголовок из метаданных PDF.
  TextColumn get title => text().nullable()();

  /// Автор из метаданных PDF.
  TextColumn get author => text().nullable()();

  /// Докуда дошла разборка: `name`, `meta` или `text`.
  TextColumn get stage => text().withDefault(const Constant<String>('name'))();

  /// Есть ли текстовый слой; пусто — ещё не смотрели.
  BoolColumn get hasTextLayer => boolean().nullable()();

  /// Файла не было на месте при последнем обходе.
  BoolColumn get missing =>
      boolean().withDefault(const Constant<bool>(false))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{path};
}

/// Локальные настройки приложения. Без полей CRDT: они не
/// синхронизируются намеренно — см. `AppSettingsRepository`.
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  /// Ключ.
  TextColumn get settingKey => text()();

  /// Значение.
  TextColumn get settingValue => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{settingKey};
}
