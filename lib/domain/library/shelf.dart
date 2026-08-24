/// Раскладка полки: как книги делятся на категории и как ложатся в сетку.
///
/// Всё здесь — чистая математика над списками и числами, без единого
/// виджета. Поэтому «сколько книг помещается в строку», «где стоит кнопка
/// плюса» и «в каком порядке идут книги» проверяются обычными
/// юнит-тестами, а экран остаётся тонким.
library;

import 'dart:math' as math;

import 'book.dart';
import 'book_category.dart';

/// Порядок книг внутри категории.
enum ShelfSort {
  /// Сначала те, что читали последними.
  recent,

  /// По названию.
  title,

  /// Сначала недавно добавленные.
  added,

  /// Сначала начатые и не дочитанные.
  progress,

  /// Как расставил читатель.
  ///
  /// Появляется сам при первом же перетаскивании книги: иначе
  /// перетаскивание было бы обманом — при сортировке «по названию» книга
  /// вернулась бы на место в тот же миг (решение владельца, 24.08.2026).
  manual,
}

/// Подпись сортировки для меню.
String shelfSortTitle(ShelfSort sort) {
  switch (sort) {
    case ShelfSort.recent:
      return 'Сначала недавние';
    case ShelfSort.title:
      return 'По названию';
    case ShelfSort.added:
      return 'Сначала добавленные';
    case ShelfSort.progress:
      return 'Сначала начатые';
    case ShelfSort.manual:
      return 'Как расставил';
  }
}

/// Сортировка по сохранённому имени.
///
/// Неизвестное имя откатывается к порядку по умолчанию: настройка могла
/// приехать с устройства, где стоит версия новее.
ShelfSort shelfSortFromName(String? name) {
  for (final ShelfSort sort in ShelfSort.values) {
    if (sort.name == name) {
      return sort;
    }
  }
  return ShelfSort.recent;
}

/// Один участок полки: категория и её книги.
class ShelfSection {
  /// Создаёт участок.
  const ShelfSection({
    required this.id,
    required this.title,
    required this.books,
    required this.category,
  });

  /// Идентификатор категории; [kUncategorizedId] у книг без категории.
  final String id;

  /// Название, которое видит читатель.
  final String title;

  /// Книги в выбранном порядке.
  final List<Book> books;

  /// Сама категория или `null` для раздела «Без категории»: его нельзя
  /// ни переименовать, ни удалить, и меню у него другое.
  final BookCategory? category;

  /// Постоянный ли это раздел «Без категории».
  bool get isUncategorized => category == null;

  /// Сколько блоков занимает участок: книги плюс кнопка «+».
  int get blockCount => books.length + 1;
}

/// Собирает полку: разделы в порядке категорий, книги — в выбранном.
///
/// Раздел «Без категории» стоит первым и показывается, только если в нём
/// есть книги или на полке вообще нет категорий. Пустой безымянный
/// прямоугольник над аккуратными категориями выглядит поломкой, а вот
/// пустая **своя** категория остаётся видна всегда: её завели руками, и
/// исчезнуть она не имеет права.
///
/// Книга, чья категория удалена или неизвестна, попадает в «Без
/// категории», а не пропадает с полки: потерять книгу из-за строчки в
/// базе нельзя ни при каких обстоятельствах.
List<ShelfSection> buildShelf({
  required List<BookCategory> categories,
  required List<Book> books,
  required ShelfSort sort,
  Map<String, double> progress = const <String, double>{},
}) {
  final List<BookCategory> ordered = <BookCategory>[...categories]
    ..sort(compareCategories);
  final Set<String> known = <String>{
    for (final BookCategory category in ordered) category.id,
  };

  final Map<String, List<Book>> byCategory = <String, List<Book>>{
    kUncategorizedId: <Book>[],
    for (final BookCategory category in ordered) category.id: <Book>[],
  };
  for (final Book book in books) {
    final String? id = book.categoryId;
    final String slot = id != null && known.contains(id)
        ? id
        : kUncategorizedId;
    byCategory[slot]!.add(book);
  }

  final List<Book> loose = sortBooks(
    byCategory[kUncategorizedId]!,
    sort,
    progress: progress,
  );
  return <ShelfSection>[
    if (loose.isNotEmpty || ordered.isEmpty)
      ShelfSection(
        id: kUncategorizedId,
        title: kUncategorizedTitle,
        books: loose,
        category: null,
      ),
    for (final BookCategory category in ordered)
      ShelfSection(
        id: category.id,
        title: category.title,
        books: sortBooks(byCategory[category.id]!, sort, progress: progress),
        category: category,
      ),
  ];
}

/// Книги в выбранном порядке. Исходный список не меняется.
///
/// У каждого порядка есть запасная ступень — название, — потому что
/// книги, у которых главный признак совпал (не открывались вовсе,
/// добавлены одной пачкой, не начаты), иначе перетасовывались бы при
/// каждой перерисовке.
List<Book> sortBooks(
  List<Book> books,
  ShelfSort sort, {
  Map<String, double> progress = const <String, double>{},
}) {
  final List<Book> result = <Book>[...books];
  int byTitle(Book a, Book b) {
    final int byName = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return byName != 0 ? byName : a.id.compareTo(b.id);
  }

  switch (sort) {
    case ShelfSort.recent:
      result.sort((Book a, Book b) {
        final DateTime? left = a.openedAt;
        final DateTime? right = b.openedAt;
        if (left == null && right == null) {
          return byTitle(a, b);
        }
        // Не открывавшаяся книга — не «самая старая», а книга без ответа
        // на этот вопрос: её место в конце, а не среди прошлогодних.
        if (left == null) {
          return 1;
        }
        if (right == null) {
          return -1;
        }
        final int byTime = right.compareTo(left);
        return byTime != 0 ? byTime : byTitle(a, b);
      });
    case ShelfSort.title:
      result.sort(byTitle);
    case ShelfSort.added:
      result.sort((Book a, Book b) {
        final int byTime = b.addedAt.compareTo(a.addedAt);
        return byTime != 0 ? byTime : byTitle(a, b);
      });
    case ShelfSort.manual:
      result.sort((Book a, Book b) {
        final int byPlace = a.shelfPosition.compareTo(b.shelfPosition);
        // Книги, которых читатель ещё не касался, стоят с одним и тем же
        // нулевым местом. Разводить их названием, а не случаем: полка,
        // выглядящая по-разному при каждом открытии, — поломка.
        return byPlace != 0 ? byPlace : byTitle(a, b);
      });
    case ShelfSort.progress:
      result.sort((Book a, Book b) {
        // Начатая и не дочитанная — впереди; дочитанная и не начатая
        // равно «сейчас не читаю», и обе уходят назад.
        final double left = _readingWeight(progress[a.id] ?? 0);
        final double right = _readingWeight(progress[b.id] ?? 0);
        final int byWeight = right.compareTo(left);
        return byWeight != 0 ? byWeight : byTitle(a, b);
      });
  }
  return result;
}

double _readingWeight(double progress) {
  if (!progress.isFinite || progress <= 0.001 || progress >= 0.999) {
    return 0;
  }
  return progress;
}

/// Куда встанут книги, если [moved] положить перед книгой [before].
///
/// Одна функция на оба случая — и перестановку внутри категории, и
/// перенос в чужую, — потому что разницы между ними по существу нет:
/// книга вынимается оттуда, где лежала, и вставляется туда, куда её
/// положили. [before] — книга, **перед** которой встаёт перетаскиваемая;
/// `null` означает «в конец». Место названо книгой, а не числом, нарочно:
/// номер пришлось бы поправлять на единицу при переносе вперёд внутри
/// одной категории, и это ровно та арифметика, в которой ошибаются.
///
/// [target] — книги категории назначения **в том порядке, в каком их
/// видит читатель**. Если [moved] среди них, она сначала вынимается.
///
/// Возвращает расстановку для всей категории целиком: места
/// перенумеровываются подряд с нуля. Половинчатая запись — «этой книге
/// новое место, остальным как было» — рано или поздно даёт две книги на
/// одном месте, и полка начинает переставляться сама собой.
List<BookPlacement> placeBefore({
  required List<Book> target,
  required Book moved,
  required Book? before,
  required String? categoryId,
}) {
  final List<Book> rest = <Book>[
    for (final Book book in target)
      if (book.id != moved.id) book,
  ];
  final int at;
  if (before == null) {
    at = rest.length;
  } else if (before.id == moved.id) {
    // Книгу положили на неё же — она остаётся там, где стояла. Экран
    // такой промах не пропускает вовсе, но функция обязана вести себя
    // разумно и без него: «никуда не двигать» здесь очевиднее, чем
    // «отправить в конец».
    final int here = target.indexWhere((Book book) => book.id == moved.id);
    at = here < 0 ? rest.length : here.clamp(0, rest.length);
  } else {
    // Ориентира больше нет: полка перестроилась, пока книгу несли, —
    // цель уехала в другую категорию или её сняли. Это повод положить
    // книгу в конец, а не уронить приложение.
    final int found = rest.indexWhere((Book book) => book.id == before.id);
    at = found >= 0 ? found : rest.length;
  }
  rest.insert(at, moved);
  return <BookPlacement>[
    for (int i = 0; i < rest.length; i++)
      BookPlacement(bookId: rest[i].id, categoryId: categoryId, position: i),
  ];
}

/// Ничего не меняется, если книгу положили туда же, где она лежала.
///
/// Экран спрашивает об этом до записи: перетаскивание, кончившееся
/// ничем, не должно ни трогать базу, ни включать ручной порядок, ни
/// показывать читателю сообщение о том, чего не случилось.
bool placementChangesNothing(List<Book> target, List<BookPlacement> next) {
  if (next.length != target.length) {
    return false;
  }
  for (int i = 0; i < target.length; i++) {
    final Book book = target[i];
    final BookPlacement placement = next[i];
    if (book.id != placement.bookId ||
        book.categoryId != placement.categoryId ||
        book.shelfPosition != placement.position) {
      return false;
    }
  }
  return true;
}

/// Ширина блока, к которой стремится полка, в логических точках.
///
/// Число выбрано так, чтобы на телефоне в портрете вышло ровно три блока
/// в строке — как задумано, — а на широком окне ПК обложки не
/// раздувались до афиш, а просто стало больше книг в строке.
const double kShelfTargetBlock = 190.0;

/// Меньше трёх блоков в строке не бывает никогда.
///
/// Три — это и есть «строка категории» из постановки: узкий экран не
/// вправе превратить полку в столбик.
const int kShelfMinColumns = 3;

/// Больше этого в строку не ставим даже на очень широком экране.
const int kShelfMaxColumns = 10;

/// Сколько блоков помещается в строку при заданной ширине участка.
int shelfColumnsFor(double width) {
  if (!width.isFinite || width <= 0) {
    return kShelfMinColumns;
  }
  final int fit = (width / kShelfTargetBlock).floor();
  return fit.clamp(kShelfMinColumns, kShelfMaxColumns);
}

/// Сколько строк займут блоки при заданном числе колонок.
int shelfRowsFor(int blocks, int columns) {
  if (blocks <= 0) {
    return 0;
  }
  final int cols = columns < 1 ? 1 : columns;
  return (blocks + cols - 1) ~/ cols;
}

/// Отношение высоты блока к ширине.
///
/// Блок — это обложка плюс подпись под ней. Обложка книги близка к 1:1.4
/// (А-формат), подпись занимает ещё около трети ширины блока.
const double kShelfBlockAspect = 1.72;

/// Толщина корешка книги, доля от 0 до 1.
///
/// Брошюра и том обязаны выглядеть по-разному ещё до того, как читатель
/// прочтёт подпись. Считается по числу страниц, а если его ещё не знаем —
/// по размеру файла: у скана страниц мало, а мегабайтов много, и наоборот.
/// Шкала логарифмическая: разница между 20 и 200 страницами заметна
/// глазу, между 2000 и 2200 — нет.
double spineThickness(Book book) {
  final int pages = book.pageCount ?? 0;
  if (pages > 0) {
    return _logScale(pages.toDouble(), 16, 1600);
  }
  final int bytes = book.fileSize;
  if (bytes > 0) {
    return _logScale(bytes / (1024 * 1024), 0.2, 120);
  }
  return 0.25;
}

double _logScale(double value, double low, double high) {
  if (!value.isFinite || value <= 0) {
    return 0;
  }
  final double t =
      (math.log(value) - math.log(low)) / (math.log(high) - math.log(low));
  return t.clamp(0.0, 1.0);
}
