import 'dart:typed_data';

import 'text_geometry.dart';

/// Что именно помешало открыть книгу.
///
/// Различать причины нужно не ради полноты, а ради правила изящной
/// деградации: «нужен пароль» — это диалог ввода пароля, «файл повреждён» —
/// честное сообщение, «файла нет» — предложение найти его заново. Одно
/// общее «не удалось открыть» превращает три разных разговора с читателем
/// в один бесполезный.
enum DocumentProblem {
  /// Файла нет по указанному пути.
  missing,

  /// Файл нулевой длины.
  empty,

  /// Файл не разбирается: обрублен, испорчен или это вовсе не PDF.
  damaged,

  /// Файл зашифрован, нужен пароль.
  passwordRequired,

  /// Пароль есть, но неверный.
  wrongPassword,

  /// Всё остальное.
  unknown,
}

/// Книгу открыть не удалось.
class DocumentOpenException implements Exception {
  /// Создаёт исключение.
  const DocumentOpenException(this.problem, this.path, {this.cause});

  /// Причина.
  final DocumentProblem problem;

  /// Путь к файлу.
  final String path;

  /// Исходная ошибка движка, если она была.
  final Object? cause;

  @override
  String toString() => 'DocumentOpenException($problem, $path)';
}

/// Размеры страницы в точках PDF (1/72 дюйма) — уже с учётом поворота
/// страницы, заданного в файле.
class PageGeometry {
  /// Создаёт геометрию страницы.
  const PageGeometry({
    required this.width,
    required this.height,
    this.quarterTurns = 0,
  });

  /// Ширина в точках.
  final double width;

  /// Высота в точках.
  final double height;

  /// Поворот страницы, заданный в файле, четвертями оборота (0…3).
  final int quarterTurns;

  /// Альбомная ли страница.
  bool get isLandscape => width > height;

  @override
  bool operator ==(Object other) {
    return other is PageGeometry &&
        other.width == width &&
        other.height == height &&
        other.quarterTurns == quarterTurns;
  }

  @override
  int get hashCode => Object.hash(width, height, quarterTurns);

  @override
  String toString() => 'PageGeometry(${width}x$height, turns: $quarterTurns)';
}

/// Отрендеренная страница: сырые пиксели BGRA.
///
/// Нужна не читалке — она рисует страницы сама, — а обложкам (S5),
/// попиксельной автообрезке сканов (S4) и корпус-тестам, которые проверяют,
/// что страница вообще рисуется.
class PageRaster {
  /// Создаёт растр.
  const PageRaster({
    required this.width,
    required this.height,
    required this.pixels,
  });

  /// Ширина растра в пикселях.
  final int width;

  /// Высота растра в пикселях.
  final int height;

  /// Пиксели в порядке BGRA, по четыре байта на пиксель.
  final Uint8List pixels;

  /// Растр непустой и его размер сходится с заявленным.
  bool get isConsistent =>
      width > 0 && height > 0 && pixels.length == width * height * 4;
}

/// Узел оглавления.
class OutlineEntry {
  /// Создаёт узел.
  const OutlineEntry({
    required this.title,
    this.pageNumber,
    this.children = const <OutlineEntry>[],
  });

  /// Заголовок.
  final String title;

  /// Страница, на которую ведёт пункт, начиная с единицы.
  ///
  /// `null` означает, что назначение в файле есть, но разобрать его не
  /// удалось: такой пункт показывается, но не нажимается.
  final int? pageNumber;

  /// Вложенные пункты.
  final List<OutlineEntry> children;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! OutlineEntry ||
        other.title != title ||
        other.pageNumber != pageNumber ||
        other.children.length != children.length) {
      return false;
    }
    for (int i = 0; i < children.length; i++) {
      if (other.children[i] != children[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(title, pageNumber, children.length);

  @override
  String toString() => 'OutlineEntry($title -> $pageNumber)';
}

/// Открытый документ глазами приложения.
///
/// Интерфейс намеренно узкий: он описывает то, что читалке нужно от PDF,
/// и ничего не знает ни про PDFium, ни про виджеты. Благодаря этому
/// сценарии чтения тестируются подставным документом, а корпус-тесты
/// гоняют настоящий движок через ту же дверь, что и приложение.
abstract interface class ReaderDocument {
  /// Откуда документ открыт — путь к файлу или иной идентификатор.
  String get sourceName;

  /// Число страниц. Всегда больше нуля у успешно открытого документа.
  int get pageCount;

  /// Геометрия страницы, [pageNumber] начинается с единицы.
  PageGeometry geometry(int pageNumber);

  /// Текст страницы. Пустая строка означает, что текста на странице нет.
  Future<String> pageText(int pageNumber);

  /// Прямоугольники символов страницы в долях отображаемой страницы.
  ///
  /// Нужны читательской рамке: по ним считается прямоугольник содержимого
  /// и ищутся колонки. Пробелы и переводы строк не возвращаются — концевые
  /// пробелы строк растянули бы рамку до самого края поля, ради которого
  /// всё и затевалось.
  ///
  /// Пустой список означает страницу без текстового слоя: для неё рамка
  /// считается по пикселям рендера.
  Future<List<TextBox>> pageTextBoxes(int pageNumber);

  /// Оглавление. Пустой список — оглавления в файле нет.
  Future<List<OutlineEntry>> outline();

  /// Рисует страницу в растр заданного размера.
  ///
  /// Возвращает `null`, если движок не смог отрисовать страницу.
  Future<PageRaster?> renderPage(
    int pageNumber, {
    required int width,
    required int height,
  });

  /// Закрывает документ и освобождает память движка.
  Future<void> close();
}

/// Открывает файл и отдаёт [ReaderDocument]. Реализация — в
/// `infrastructure`, чтобы тесты сценариев могли подставить свою.
abstract interface class DocumentOpener {
  /// Открывает файл.
  ///
  /// Бросает [DocumentOpenException] с разобранной причиной; молча вернуть
  /// «пустой документ» нельзя — читателю нужно сказать, что случилось.
  Future<ReaderDocument> open(String path, {String? password});
}

/// Есть ли в документе текстовый слой.
///
/// Проверяются первые [probePages] страниц, а не одна: у сканов первая
/// страница часто обложка, а у книг с текстом — титул без текста вовсе.
/// И не все страницы: на книге в тысячу страниц это заметная пауза при
/// импорте ради ответа, который виден уже на пятой.
Future<bool> hasTextLayer(ReaderDocument document, {int probePages = 5}) async {
  final int limit = document.pageCount < probePages
      ? document.pageCount
      : probePages;
  for (int page = 1; page <= limit; page++) {
    final String text = await document.pageText(page);
    if (text.trim().isNotEmpty) {
      return true;
    }
  }
  return false;
}
