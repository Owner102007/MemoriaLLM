/// Эталонное состояние и сброс (SNO-F-CFG-04, SNO-ALG-CFG-02).
///
/// Записи разных тестировщиков исследования СНО2026 сравнимы, только
/// если каждый начинал с одной и той же полки: те же категории в том же
/// порядке, те же книги на тех же местах, те же настройки. Это состояние
/// и есть эталон.
///
/// **Эталон — полка, какой её кладёт архив с литературой.** Он
/// запоминается сам, когда архив разложен ([ReferenceKeeper.remember]),
/// и складывается из раскладки архива, а не из полки, какой её застали
/// ([extendReference]): из одного архива у всех устройств он выходит
/// одинаковым, а расставленный руками — нет. Перестановки после
/// распаковки в эталон не попадают; второй архив его дополняет, а не
/// заменяет.
///
/// **Сброс** ([ReferenceKeeper.reset]) стирает всё, что оставил
/// предыдущий тестировщик, — прогресс, цитаты, заметки, закладки,
/// настройки книг и приложения — и возвращает полку к эталону. Книги,
/// текст страниц, посчитанные рамки и обложки остаются: заново ничего
/// не распаковывается.
///
/// Эталон лежит в общей таблице настроек одной записью — тем же JSON,
/// что задуман для пакета литературы (`sno2026-reference/1`). В базе, а
/// не файлом: сброс и эталон меняются одной транзакцией, а раздел
/// «Тестирование» проверяется без диска.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../application/data/app_data.dart';
import '../domain/library/book.dart';
import '../domain/library/book_category.dart';
import '../domain/library/book_source.dart';
import '../domain/library/book_storage.dart';
import '../domain/library/ids.dart';
import '../domain/library/shelf.dart';
import '../domain/library/shelf_archive.dart';
import '../domain/settings/app_settings.dart';
import '../infrastructure/database/app_database.dart';

/// Версия записи эталона.
const String kReferenceSchema = 'sno2026-reference/1';

/// Ключи сборки ветви в общей таблице настроек.
abstract final class SnoSettingsKeys {
  /// Эталонное состояние — JSON ([ReferenceState.encode]).
  static const String reference = 'sno.reference_state';

  /// Когда устройство в последний раз сбросили к эталону: время в UTC.
  ///
  /// Попадёт в снимок начала записи (этап 2): по нему видно, с чистого
  /// ли состояния начинал тестировщик.
  static const String lastReset = 'sno.state_reset';
}

/// Настройки, которые сброс не трогает: это не след читателя.
///
/// Идентификатор устройства обязан пережить сброс — по нему записи
/// одного устройства узнаются при разборе; часы идут только вперёд;
/// версия правила «есть ли текст» — служебная отметка разборки.
const Set<String> _keptSettings = <String>{
  SettingsKeys.nodeId,
  SettingsKeys.lastHlc,
  SettingsKeys.deviceTextRule,
  SnoSettingsKeys.reference,
  SnoSettingsKeys.lastReset,
};

/// Настройки, которых нет в снимке состояния: их пишет само приложение,
/// а не читатель, и после сброса они появляются снова.
const Set<String> _serviceSettings = <String>{
  ..._keptSettings,
  SettingsKeys.promptsSeeded,
};

/// Книга на своём месте полки.
class ShelfBook {
  /// Создаёт место книги.
  const ShelfBook({
    required this.fingerprint,
    required this.title,
    required this.category,
    required this.position,
  });

  /// Отпечаток файла: по нему книга одна и та же на всех устройствах.
  final String fingerprint;

  /// Название — чтобы назвать книгу словами, когда её файл пропал.
  final String title;

  /// Название категории; `null` — «Без категории».
  final String? category;

  /// Место в категории, считая с нуля.
  final int position;

  /// Запись для JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'fingerprint': fingerprint,
    'title': title,
    'category': category,
    'position': position,
  };

  /// Название в сравнение не входит: место книги — это категория и
  /// порядок, а не то, как её назвали.
  @override
  bool operator ==(Object other) =>
      other is ShelfBook &&
      other.fingerprint == fingerprint &&
      other.category == category &&
      other.position == position;

  @override
  int get hashCode => Object.hash(fingerprint, category, position);

  @override
  String toString() => 'ShelfBook($category, $position, $title)';
}

/// Полка словами: категории по порядку и место каждой книги.
class ShelfState {
  /// Создаёт описание полки.
  const ShelfState({required this.categories, required this.books});

  /// Названия категорий в порядке полки.
  final List<String> categories;

  /// Книги: сначала «Без категории», затем категории по порядку, внутри
  /// — по местам.
  final List<ShelfBook> books;

  /// Та же ли это полка: те же категории в том же порядке и те же
  /// книги на тех же местах.
  bool sameAs(ShelfState other) {
    if (categories.length != other.categories.length ||
        books.length != other.books.length) {
      return false;
    }
    for (int i = 0; i < categories.length; i++) {
      if (categories[i] != other.categories[i]) {
        return false;
      }
    }
    final List<ShelfBook> mine = ordered();
    final List<ShelfBook> theirs = other.ordered();
    for (int i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) {
        return false;
      }
    }
    return true;
  }

  /// Книги в порядке полки, с местами подряд от нуля в каждой категории.
  ///
  /// Сравнивать две полки можно только так: «0, 1, 3» и «0, 1, 2» —
  /// один и тот же порядок, записанный разными числами.
  List<ShelfBook> ordered() {
    final Map<String, int> order = <String, int>{
      for (int i = 0; i < categories.length; i++) categories[i]: i,
    };
    int rank(ShelfBook book) {
      final String? category = book.category;
      if (category == null) {
        return -1;
      }
      // Категория, которой на полке нет, — после всех названных.
      return order[category] ?? categories.length;
    }

    final List<ShelfBook> sorted = <ShelfBook>[...books];
    // Сортировка списка в Dart неустойчива, поэтому книги с равными
    // местами разводит отпечаток — порядок обязан быть одним и тем же.
    sorted.sort((ShelfBook a, ShelfBook b) {
      final int byCategory = rank(a).compareTo(rank(b));
      if (byCategory != 0) {
        return byCategory;
      }
      final int byName = (a.category ?? '').compareTo(b.category ?? '');
      if (byName != 0) {
        return byName;
      }
      final int byPlace = a.position.compareTo(b.position);
      return byPlace != 0 ? byPlace : a.fingerprint.compareTo(b.fingerprint);
    });
    final List<ShelfBook> result = <ShelfBook>[];
    String? current;
    int next = 0;
    for (int i = 0; i < sorted.length; i++) {
      final ShelfBook book = sorted[i];
      if (i == 0 || book.category != current) {
        current = book.category;
        next = 0;
      }
      result.add(
        ShelfBook(
          fingerprint: book.fingerprint,
          title: book.title,
          category: book.category,
          position: next++,
        ),
      );
    }
    return result;
  }

  /// Запись для JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'categories': <Object?>[
      for (int i = 0; i < categories.length; i++)
        <String, Object?>{'name': categories[i], 'order': i},
    ],
    'books': <Object?>[for (final ShelfBook book in books) book.toJson()],
  };
}

/// Полка, как её видит читатель в порядке «Как расставил».
///
/// Чистая функция над списками: тем же кодом строится и эталон, и
/// снимок текущего состояния, поэтому «совпадает ли устройство с
/// эталоном» — сравнение двух одинаково построенных описаний.
ShelfState shelfStateOf({
  required List<BookCategory> categories,
  required List<Book> books,
}) {
  final List<BookCategory> ordered = <BookCategory>[...categories]
    ..sort(compareCategories);
  final Map<String, String> titles = <String, String>{
    for (final BookCategory category in ordered) category.id: category.title,
  };
  final Map<String?, List<Book>> groups = <String?, List<Book>>{};
  for (final Book book in books) {
    final String? id = book.categoryId;
    // Книга в категории, которой нет, на полке стоит в «Без категории».
    final String? slot = id != null && titles.containsKey(id) ? id : null;
    groups.putIfAbsent(slot, () => <Book>[]).add(book);
  }
  final List<ShelfBook> placed = <ShelfBook>[];
  void place(String? categoryId) {
    final List<Book> group = sortBooks(
      groups[categoryId] ?? const <Book>[],
      ShelfSort.manual,
    );
    for (int i = 0; i < group.length; i++) {
      placed.add(
        ShelfBook(
          fingerprint: group[i].fileHash,
          title: group[i].title,
          category: categoryId == null ? null : titles[categoryId],
          position: i,
        ),
      );
    }
  }

  place(null);
  for (final BookCategory category in ordered) {
    place(category.id);
  }
  return ShelfState(
    categories: <String>[
      for (final BookCategory category in ordered) category.title,
    ],
    books: placed,
  );
}

/// Эталонное состояние: полка и время, когда она запомнена.
///
/// Настроек в эталоне нет: настройки эталона — настройки только что
/// установленной сборки, то есть отсутствие записей в таблице настроек.
class ReferenceState {
  /// Создаёт эталон.
  const ReferenceState({required this.shelf, required this.savedAt});

  /// Эталонная полка.
  final ShelfState shelf;

  /// Когда эталон запомнен или дополнен в последний раз.
  final DateTime savedAt;

  /// Запись эталона.
  String encode() {
    return jsonEncode(<String, Object?>{
      'schema': kReferenceSchema,
      'saved_at': savedAt.toUtc().toIso8601String(),
      ...shelf.toJson(),
      'settings': const <String, Object?>{},
    });
  }

  /// Читает запись; `null` — записи нет или она не читается.
  ///
  /// Испорченная запись — то же, что её отсутствие: сбрасывать к
  /// полуправде нельзя, а эталон запомнится заново следующим архивом.
  static ReferenceState? decode(String? text) {
    if (text == null || text.isEmpty) {
      return null;
    }
    try {
      final Object? raw = jsonDecode(text);
      if (raw is! Map<String, Object?> || raw['schema'] != kReferenceSchema) {
        return null;
      }
      final Object? categories = raw['categories'];
      final Object? books = raw['books'];
      final Object? savedAt = raw['saved_at'];
      if (categories is! List<Object?> ||
          books is! List<Object?> ||
          savedAt is! String) {
        return null;
      }
      final List<String> titles = <String>[];
      for (final Object? item in categories) {
        if (item is! Map<String, Object?>) {
          return null;
        }
        final Object? name = item['name'];
        if (name is! String) {
          return null;
        }
        titles.add(name);
      }
      final List<ShelfBook> placed = <ShelfBook>[];
      for (final Object? item in books) {
        if (item is! Map<String, Object?>) {
          return null;
        }
        final Object? fingerprint = item['fingerprint'];
        final Object? title = item['title'];
        final Object? category = item['category'];
        final Object? position = item['position'];
        if (fingerprint is! String ||
            position is! int ||
            (category != null && category is! String)) {
          return null;
        }
        placed.add(
          ShelfBook(
            fingerprint: fingerprint,
            title: title is String ? title : '',
            category: category is String ? category : null,
            position: position,
          ),
        );
      }
      return ReferenceState(
        shelf: ShelfState(categories: titles, books: placed),
        savedAt: DateTime.parse(savedAt),
      );
    } on FormatException {
      return null;
    }
  }
}

/// Снимок текущего состояния устройства.
class StateSnapshot {
  /// Создаёт снимок.
  const StateSnapshot({
    required this.shelf,
    required this.settings,
    required this.traces,
  });

  /// Полка сейчас.
  final ShelfState shelf;

  /// Настройки, которые выставил читатель: тема, порядок полки, зоны,
  /// клавиши, отметки «подсказку уже видел».
  final Map<String, String> settings;

  /// Сколько записей оставил читатель: места чтения, цитаты, заметки,
  /// закладки, настройки книг, запросы.
  final int traces;

  /// Совпадает ли устройство с эталоном: та же полка, настройки не
  /// тронуты, следов читателя нет.
  bool matches(ReferenceState reference) {
    return traces == 0 && settings.isEmpty && shelf.sameAs(reference.shelf);
  }
}

/// Чем кончился сброс.
class ResetReport {
  /// Создаёт отчёт.
  const ResetReport({
    required this.at,
    required this.matches,
    this.missing = const <String>[],
  });

  /// Когда сброшено.
  final DateTime at;

  /// Совпадает ли состояние после сброса с эталоном.
  final bool matches;

  /// Книги эталона, у которых нет файла: их возвращает повторное
  /// добавление архива с литературой.
  final List<String> missing;
}

/// Сколько книг без файла названо в итоге сброса поимённо.
const int kNamedMissing = 3;

/// Что сказать экспериментатору после сброса.
String describeReset(ResetReport report) {
  if (report.missing.isEmpty) {
    return report.matches
        ? 'Сброшено. Состояние совпадает с эталоном.'
        : 'Сброшено, но состояние отличается от эталона: добавьте архив '
              'с литературой ещё раз.';
  }
  final String named = report.missing
      .take(kNamedMissing)
      .map((String title) => '«$title»')
      .join(', ');
  final int rest = report.missing.length - kNamedMissing;
  final String all = rest > 0 ? '$named и ещё $rest' : named;
  return 'Сброшено. Нет файла у книг: ${report.missing.length} — $all. '
      'Добавьте архив с литературой ещё раз.';
}

/// Время словами для раздела «Тестирование»: «04.10 в 18:20».
String describeMoment(DateTime moment) {
  final DateTime local = moment.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)} в '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Эталон словами: «Категорий: 5, книг: 34 · запомнено 04.10 в 18:20».
String describeReference(ReferenceState reference) {
  return 'Категорий: ${reference.shelf.categories.length}, '
      'книг: ${reference.shelf.books.length} · '
      'запомнено ${describeMoment(reference.savedAt)}';
}

/// Дополняет эталон книгами разложенного архива (SNO-ALG-CFG-02).
///
/// Эталон складывается из раскладки архива, а не из полки, какой её
/// застали: книга встаёт в категорию, которую ей назначил архив, за
/// книгами, уже записанными в эту категорию. Так эталон выходит одним
/// и тем же на любом устройстве — и на том, где книги успели
/// переставить, и на том, где архив добавляли прежней сборкой.
///
/// Книга, уже записанная в эталон, своего места не меняет: первый
/// архив, положивший её, главнее. Категории идут в том порядке, в каком
/// получили первую книгу; название категории — в написании эталона.
///
/// Отдаёт [known], если добавить нечего; `null` — эталона нет и
/// запоминать нечего.
ReferenceState? extendReference(
  ReferenceState? known,
  Iterable<ArchivePlacement> placed,
  DateTime now,
) {
  final List<String> categories = <String>[...?known?.shelf.categories];
  final List<ShelfBook> books = <ShelfBook>[...?known?.shelf.books];
  final Map<String, String> spelling = <String, String>{
    for (final String title in categories) title.toLowerCase(): title,
  };
  final Set<String> recorded = <String>{
    for (final ShelfBook book in books) book.fingerprint,
  };
  final Map<String?, int> counts = <String?, int>{};
  for (final ShelfBook book in books) {
    counts[book.category] = (counts[book.category] ?? 0) + 1;
  }
  bool grown = false;
  for (final ArchivePlacement item in placed) {
    if (!recorded.add(item.fingerprint)) {
      continue;
    }
    final String? asked = item.category;
    String? category;
    if (asked != null) {
      category = spelling[asked.toLowerCase()];
      if (category == null) {
        category = asked;
        spelling[asked.toLowerCase()] = asked;
        categories.add(asked);
      }
    }
    final int place = counts[category] ?? 0;
    counts[category] = place + 1;
    books.add(
      ShelfBook(
        fingerprint: item.fingerprint,
        title: item.title,
        category: category,
        position: place,
      ),
    );
    grown = true;
  }
  if (!grown) {
    return known;
  }
  final ShelfState shelf = ShelfState(categories: categories, books: books);
  return ReferenceState(
    shelf: ShelfState(categories: categories, books: shelf.ordered()),
    savedAt: now,
  );
}

/// Хранит эталон, снимает состояние и сбрасывает к эталону
/// (SNO-ALG-CFG-02).
class ReferenceKeeper {
  /// Создаёт хранителя.
  ///
  /// [newId] и [now] подменяются в тестах.
  ReferenceKeeper({
    required AppData data,
    required BookStorage storage,
    String Function()? newId,
    DateTime Function()? now,
  }) : _data = data,
       _storage = storage,
       _newId = newId ?? newLibraryId,
       _now = now ?? DateTime.now;

  final AppData _data;
  final BookStorage _storage;
  final String Function() _newId;
  final DateTime Function() _now;

  /// Запомненный эталон; `null` — эталона ещё нет.
  Future<ReferenceState?> reference() async {
    return ReferenceState.decode(
      await _data.settings.read(SnoSettingsKeys.reference),
    );
  }

  /// Когда устройство сбрасывали в последний раз; `null` — никогда.
  Future<DateTime?> lastReset() async {
    final String? stored = await _data.settings.read(SnoSettingsKeys.lastReset);
    return stored == null ? null : DateTime.tryParse(stored);
  }

  /// Снимок текущего состояния.
  Future<StateSnapshot> snapshot() async {
    final AppDatabase db = _data.database;
    final Map<String, String> settings = <String, String>{
      for (final AppSettingRow row in await db.select(db.appSettings).get())
        if (!_serviceSettings.contains(row.settingKey))
          row.settingKey: row.settingValue,
    };
    final int traces =
        (await db.select(db.readingProgress).get()).length +
        (await db.select(db.bookSettings).get()).length +
        (await db.select(db.quotes).get()).length +
        (await db.select(db.notes).get()).length +
        (await db.select(db.bookmarks).get()).length +
        (await db.select(db.llmQueries).get()).length;
    return StateSnapshot(
      shelf: await _shelf(),
      settings: settings,
      traces: traces,
    );
  }

  Future<ShelfState> _shelf() async {
    return shelfStateOf(
      categories: await _data.categories.categories(),
      books: await _data.library.books(),
    );
  }

  /// Запоминает эталон после того, как архив разложен.
  ///
  /// [placed] — книги архива, стоящие на полке, с местом, которое им
  /// назначил архив ([extendReference]). Возвращает действующий эталон;
  /// `null` — запоминать нечего.
  Future<ReferenceState?> remember(Iterable<ArchivePlacement> placed) async {
    final ReferenceState? known = await reference();
    final ReferenceState? next = extendReference(known, placed, _now());
    if (next == null || identical(next, known)) {
      return known;
    }
    return _save(next);
  }

  Future<ReferenceState> _save(ReferenceState reference) async {
    await _data.settings.write(SnoSettingsKeys.reference, reference.encode());
    return reference;
  }

  /// Сбрасывает устройство к эталону.
  ///
  /// Одной транзакцией: половина сброса хуже, чем его отсутствие.
  /// Удаление — настоящее, не надгробиями: синхронизации в сборке ветви
  /// нет, и следов предыдущего тестировщика остаться не должно.
  ///
  /// Не трогает книги и то, что из них выведено: файлы, текст страниц,
  /// посчитанные рамки, обложки; идентификатор устройства; сам эталон.
  ///
  /// Бросает [StateError], если эталона нет: сбрасывать не к чему.
  Future<ResetReport> reset() async {
    final ReferenceState? reference = await this.reference();
    if (reference == null) {
      throw StateError('эталон не запомнен: сбрасывать не к чему');
    }
    final AppDatabase db = _data.database;
    final List<BookRow> rows = await db.select(db.books).get();

    // Какая строка отвечает за книгу: стоящая на полке, а если книгу
    // сняли — снятая последней.
    final Map<String, BookRow> chosen = <String, BookRow>{};
    for (final BookRow row in rows) {
      final BookRow? other = chosen[row.fileHash];
      if (other == null || _preferred(row, other)) {
        chosen[row.fileHash] = row;
      }
    }

    // Файлы проверяются до транзакции: это диск, а не база.
    final List<String> missing = <String>[];
    final Map<String, BookRow> placed = <String, BookRow>{};
    final Set<String> revived = <String>{};
    for (final ShelfBook book in reference.shelf.books) {
      final BookRow? row = chosen[book.fingerprint];
      if (row == null) {
        missing.add(book.title);
        continue;
      }
      final bool available = await _available(row);
      if (!available) {
        missing.add(row.title);
      } else if (row.isDeleted) {
        // Книгу сняли с полки, а файл её цел — она возвращается.
        revived.add(row.id);
      }
      placed[book.fingerprint] = row;
    }
    final Set<String> kept = <String>{
      for (final BookRow row in placed.values) row.id,
    };
    // Книги сверх эталона на полке остаются — в «Без категории», за
    // книгами эталона: сброс стирает следы читателя, а не библиотеку.
    final List<BookRow> loose = <BookRow>[
      for (final BookRow row in rows)
        if (!row.isDeleted && !kept.contains(row.id)) row,
    ]..sort(_byShelfPlace);
    final DateTime moment = _now();

    await db.transaction(() async {
      await _eraseTraces(db);
      final Map<String, String> categoryIds = await _restoreCategories(
        db,
        reference.shelf.categories,
        moment,
      );

      // Надгробия книг, которым в эталоне места нет, — тоже след.
      for (final BookRow row in rows) {
        if (row.isDeleted && !kept.contains(row.id)) {
          final gone = db.delete(db.books);
          gone.where((tbl) => tbl.id.equals(row.id));
          await gone.go();
        }
      }
      for (final String id in revived) {
        final back = db.update(db.books);
        back.where((tbl) => tbl.id.equals(id));
        await back.write(const BooksCompanion(isDeleted: Value<bool>(false)));
      }

      int looseFrom = 0;
      final List<BookPlacement> placements = <BookPlacement>[];
      for (final ShelfBook book in reference.shelf.books) {
        final String? category = book.category;
        if (category == null) {
          looseFrom++;
        }
        final BookRow? row = placed[book.fingerprint];
        if (row == null) {
          continue;
        }
        placements.add(
          BookPlacement(
            bookId: row.id,
            categoryId: category == null
                ? null
                : categoryIds[category.toLowerCase()],
            position: book.position,
          ),
        );
      }
      for (final BookRow row in loose) {
        placements.add(
          BookPlacement(
            bookId: row.id,
            categoryId: null,
            position: looseFrom++,
          ),
        );
      }
      await _data.library.placeBooks(placements);

      // «Когда открывали» — тоже след читателя: по нему полка стоит в
      // порядке «Сначала недавние». Возвращается время добавления.
      for (final BookRow row in rows) {
        if (!row.isDeleted || revived.contains(row.id)) {
          await _data.library.markOpened(row.id, row.addedAt);
        }
      }
      await _data.settings.write(
        SnoSettingsKeys.lastReset,
        moment.toUtc().toIso8601String(),
      );
    });

    // Сброс состоялся: всё, что дальше, отчёт о нём не отменяет.
    bool matches = false;
    try {
      // Функции к выделению из коробки — как у только что установленной
      // сборки: отметка об их заведении стёрта вместе с настройками.
      await _data.prompts.seedDefaultsOnce();
      matches = (await snapshot()).matches(reference);
    } on Object {
      // Сверка не удалась — сказано «отличается», а не «не сброшено».
    }
    return ResetReport(at: moment, matches: matches, missing: missing);
  }

  Future<bool> _available(BookRow row) async {
    try {
      return await _storage.available(BookSource.decode(row.filePath));
    } on Object {
      return false;
    }
  }

  /// Стирает всё, что оставил читатель.
  Future<void> _eraseTraces(AppDatabase db) async {
    await db.delete(db.llmQueries).go();
    await db.delete(db.notes).go();
    await db.delete(db.quotes).go();
    await db.delete(db.bookmarks).go();
    await db.delete(db.bookSettings).go();
    await db.delete(db.readingProgress).go();
    await db.delete(db.selectionPrompts).go();
    final settings = db.delete(db.appSettings);
    settings.where((tbl) => tbl.settingKey.isNotIn(_keptSettings));
    await settings.go();
  }

  /// Возвращает категориям эталонные названия и порядок.
  ///
  /// Категория эталона находится по названию, без регистра; нет её —
  /// заводится. Категории, которых в эталоне нет, уходят: их завёл
  /// читатель. Отдаёт идентификаторы по названиям в нижнем регистре.
  Future<Map<String, String>> _restoreCategories(
    AppDatabase db,
    List<String> titles,
    DateTime moment,
  ) async {
    final removed = db.delete(db.bookCategories);
    removed.where((tbl) => tbl.isDeleted.equals(true));
    await removed.go();

    final List<BookCategory> live = await _data.categories.categories();
    final Map<String, BookCategory> byTitle = <String, BookCategory>{};
    for (final BookCategory category in live) {
      byTitle.putIfAbsent(category.title.toLowerCase(), () => category);
    }
    final Map<String, String> ids = <String, String>{};
    for (int i = 0; i < titles.length; i++) {
      final String title = titles[i];
      final BookCategory? known = byTitle[title.toLowerCase()];
      final BookCategory category = known == null
          ? BookCategory(
              id: _newId(),
              title: title,
              position: i,
              createdAt: moment,
            )
          : known.copyWith(title: title, position: i);
      await _data.categories.save(category);
      ids[title.toLowerCase()] = category.id;
    }
    final Set<String> wanted = ids.values.toSet();
    for (final BookCategory category in live) {
      if (!wanted.contains(category.id)) {
        final extra = db.delete(db.bookCategories);
        extra.where((tbl) => tbl.id.equals(category.id));
        await extra.go();
      }
    }
    return ids;
  }
}

/// Какая из двух строк одной книги отвечает за неё при сбросе.
bool _preferred(BookRow row, BookRow other) {
  if (row.isDeleted != other.isDeleted) {
    return !row.isDeleted;
  }
  return row.modified.compareTo(other.modified) > 0;
}

/// Порядок «Как расставил» над строками книг.
int _byShelfPlace(BookRow a, BookRow b) {
  final int byPlace = a.shelfPosition.compareTo(b.shelfPosition);
  if (byPlace != 0) {
    return byPlace;
  }
  final int byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
}
