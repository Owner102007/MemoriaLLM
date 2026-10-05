/// Где лежит запись сессии (SNO-F-REC-01, SNO-ALG-REC-01).
///
/// Запись — папка с потоками: журнал `events.jsonl`, снимок состояния,
/// сведения о записи. Пока сессия не завершена, папка лежит среди
/// незавершённых; завершённая переезжает к остальным записям и ждёт
/// упаковки в архив (SNO-F-REC-05).
///
/// Здесь только договор: настоящая реализация пишет на диск
/// (`file_store.dart`), а экраны и правила записи проверяются на
/// памяти.
library;

/// Имя файла журнала в папке записи.
const String kEventsFile = 'events.jsonl';

/// Имя снимка состояния в начале записи.
const String kSnapshotStartFile = 'snapshot_start.json';

/// Имя снимка состояния в конце записи (SNO-ALG-REC-03): тем же кодом,
/// что снимок начала, плюс места чтения, цитаты и заметки целиком.
const String kSnapshotEndFile = 'snapshot_end.json';

/// Имя файла сведений о записи: участник, устройство, сборка, часы,
/// остановка. Из него соберётся манифест архива.
const String kRecordingFile = 'recording.json';

/// Сколько последних строк журнала читает восстановление после сбоя.
const int kTailLines = 20;

/// Журнал, открытый на дозапись.
abstract interface class JournalFile {
  /// Дописывает [text] в конец и сбрасывает на диск.
  Future<void> append(String text);

  /// Закрывает файл.
  Future<void> close();
}

/// Хранилище записей.
abstract interface class RecordingStore {
  /// Место записей — путь, по которому спрашивают свободное место.
  Future<String> location();

  /// Заводит папку незавершённой записи и отдаёт её имя.
  ///
  /// [wanted] — желаемое имя; занятое получает хвост `-2`, `-3`.
  Future<String> create(String wanted);

  /// Открывает журнал записи [folder] на дозапись.
  Future<JournalFile> openJournal(String folder);

  /// Кладёт в папку записи файл [name] целиком.
  Future<void> put(String folder, String name, String content);

  /// Лежит ли в папке записи файл [name].
  Future<bool> has(String folder, String name);

  /// Последние целые строки журнала записи [folder], не больше [count],
  /// в порядке записи; пусто — журнала нет или целых строк в нём нет.
  ///
  /// Оборванный хвост — строка без перевода строки в конце — при этом
  /// отрезается: приложение умерло посреди записи, и дописывать за
  /// обрывком нельзя. Зовётся только тогда, когда журнал не открыт.
  Future<List<String>> lastLines(String folder, {int count = kTailLines});

  /// Убирает папку незавершённой записи, которая так и не началась.
  Future<void> discard(String folder);

  /// Переносит запись из незавершённых к завершённым.
  Future<void> finish(String folder);
}
