import '../../domain/reading/text_geometry.dart';

/// Выделенный кусок книги — то, с чем работает панель действий.
///
/// Хранит и текст, и место: текст уходит в цитату, в заметку и в промпт,
/// а место нужно, чтобы поставить панель над выделением и чтобы достать
/// вокруг него абзац-контекст.
class BookSelection {
  /// Создаёт выделение.
  const BookSelection({
    required this.pageNumber,
    required this.start,
    required this.end,
    required this.text,
    this.rects = const <TextBox>[],
  });

  /// Страница, начиная с единицы.
  final int pageNumber;

  /// Начало в тексте страницы.
  final int start;

  /// Конец в тексте страницы, не включая.
  final int end;

  /// Сам выделенный текст.
  final String text;

  /// Прямоугольники выделения в долях страницы, по строкам.
  final List<TextBox> rects;

  /// Есть ли что показывать и с чем работать.
  bool get isEmpty => text.trim().isEmpty || end <= start;

  @override
  bool operator ==(Object other) {
    return other is BookSelection &&
        other.pageNumber == pageNumber &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(pageNumber, start, end);

  @override
  String toString() => 'BookSelection(стр. $pageNumber, $start..$end)';
}
