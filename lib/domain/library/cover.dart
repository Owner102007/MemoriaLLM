import 'dart:typed_data';

import 'book.dart';
import 'stable_hash.dart';

/// Ширина обложки в пикселях.
///
/// Блок полки — около 190 логических точек, и на телефоне с тройной
/// плотностью это 570 настоящих пикселей. Рисовать столько ради картинки
/// размером с ладонь незачем: 384 хватает, чтобы обложка не выглядела
/// мылом, и вчетверо дешевле по памяти и месту, чем полноразмерная.
const int kCoverWidth = 384;

/// Выше этого обложку не рисуем.
///
/// Страница бывает в пропорции 1:5 — свиток, схема, разложенная карта.
/// Рисовать её в полную ширину значит получить картинку впятеро тяжелее
/// обычной обложки. Такая страница рисуется **у́же**, сохраняя пропорции:
/// сплющить её нельзя ни в коем случае — обложка тем и полезна, что
/// повторяет книгу.
const int kCoverMaxHeight = kCoverWidth * 2;

/// Хранилище готовых обложек.
///
/// Обложка — это кэш, а не данные читателя: она рисуется из книги и в
/// облако не уезжает. Поэтому хранилище отдельно от базы и умеет ровно
/// четыре вещи.
abstract interface class CoverStore {
  /// Путь к готовой обложке или `null`, если её ещё не рисовали.
  Future<String?> read(String key);

  /// Кладёт обложку и возвращает путь к ней.
  Future<String> write(String key, Uint8List png);

  /// Убирает обложку книги, снятой с полки.
  Future<void> remove(String key);

  /// Стирает весь кэш обложек и возвращает, сколько файлов убрано.
  Future<int> clear();
}

/// Ключ обложки в кэше.
///
/// Считается по **отпечатку** книги, а не по её идентификатору: одна и та
/// же книга, выбранная заново после переезда файла, не должна рисоваться
/// второй раз. Ширина входит в ключ, чтобы смена размера обложки в
/// будущей версии не показывала читателю старые мелкие картинки.
String coverKeyFor(Book book, {int width = kCoverWidth}) {
  final String hash = book.fileHash.isEmpty ? book.id : book.fileHash;
  final String safe = hash.replaceAll(RegExp('[^A-Za-z0-9_-]'), '');
  // Настоящий отпечаток — шестнадцатеричная строка, и чистка его не
  // трогает. Но полагаться на это нельзя: если из ключа что-то вырезали,
  // две разные книги могли схлопнуться в одно имя файла — и вторая
  // получила бы обложку первой. Тогда к остатку добавляется хеш
  // исходной строки, и различие возвращается.
  final String stem = safe.length == hash.length && safe.isNotEmpty
      ? safe
      : '${safe}x${stableHash(hash).toRadixString(16)}';
  return '$stem-w$width';
}

/// Размер обложки в пикселях.
class CoverSize {
  /// Создаёт размер.
  const CoverSize(this.width, this.height);

  /// Ширина.
  final int width;

  /// Высота.
  final int height;

  @override
  bool operator ==(Object other) =>
      other is CoverSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'CoverSize(${width}x$height)';
}

/// Размер обложки при заданных пропорциях первой страницы.
///
/// Пропорции страницы сохраняются всегда: слишком высокая страница
/// рисуется у́же положенного, а не сплющивается. Возвращает `null`, если
/// страница вырожденная: рисовать нечего, и честнее показать заглушку с
/// названием, чем чёрный прямоугольник.
CoverSize? coverSizeFor({
  required double pageWidth,
  required double pageHeight,
  int width = kCoverWidth,
}) {
  if (!pageWidth.isFinite ||
      !pageHeight.isFinite ||
      pageWidth <= 0 ||
      pageHeight <= 0 ||
      width < 1) {
    return null;
  }
  final double ratio = pageHeight / pageWidth;
  int coverWidth = width;
  int coverHeight = (coverWidth * ratio).round();
  if (coverHeight > kCoverMaxHeight) {
    coverHeight = kCoverMaxHeight;
    coverWidth = (coverHeight / ratio).round();
  }
  if (coverWidth < 1 || coverHeight < 1) {
    return null;
  }
  return CoverSize(coverWidth, coverHeight);
}
