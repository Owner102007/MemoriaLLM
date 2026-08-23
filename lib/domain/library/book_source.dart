/// Где лежит книга и как до неё добраться.
///
/// До S5.1 в библиотеке хранился путь к файлу — и на Android это был путь
/// не к книге, а к её копии в кэше приложения: настоящего пути к
/// выбранному документу у приложения с Android 10 нет вовсе. Копия стоила
/// второго объёма книги, а делалась через память и роняла приложение на
/// учебнике в 73 МБ.
///
/// Поэтому место книги описывается не строкой, а источником: обычный путь
/// на Windows, закреплённая ссылка `content://` на Android и — только
/// когда иначе нельзя — потоковая копия в папке приложения.
sealed class BookSource {
  /// Создаёт источник.
  const BookSource();

  /// Вид источника в строке базы.
  static const String _fileKind = 'file';
  static const String _copyKind = 'copy';
  static const String _documentKind = 'doc';

  /// Строка для базы. Разбирается обратно [decode].
  String encode();

  /// Разбирает строку из базы.
  ///
  /// Строка без известного вида читается как обычный путь: именно так в
  /// базе лежат книги, заведённые до S5.1, и терять их из-за смены
  /// формата нельзя. Двоеточие в `C:\books\...` за вид не считается —
  /// виды перечислены поимённо, и `C` в этот список не входит.
  static BookSource decode(String raw) {
    final int colon = raw.indexOf(':');
    if (colon > 0) {
      final String kind = raw.substring(0, colon);
      final String rest = raw.substring(colon + 1);
      switch (kind) {
        case _fileKind:
          return FilePathSource(rest);
        case _copyKind:
          return FilePathSource(rest, owned: true);
        case _documentKind:
          return DocumentUriSource(rest);
      }
    }
    return FilePathSource(raw);
  }
}

/// Обычный файл, который открывается по пути.
///
/// На Windows это сама книга. На Android — копия, сделанная нами: так
/// приходится поступать с провайдерами, чья ссылка не годится для
/// перескоков по файлу (облачные хранилища отдают поток, а не файл).
final class FilePathSource extends BookSource {
  /// Создаёт источник-файл.
  const FilePathSource(this.path, {this.owned = false});

  /// Путь к файлу на этом устройстве.
  final String path;

  /// Копию сделали мы — значит, нам её и убирать, когда книгу снимают
  /// с полки. Чужой файл трогать нельзя ни при каких обстоятельствах.
  final bool owned;

  @override
  String encode() =>
      owned ? '${BookSource._copyKind}:$path' : '${BookSource._fileKind}:$path';

  @override
  bool operator ==(Object other) =>
      other is FilePathSource && other.path == path && other.owned == owned;

  @override
  int get hashCode => Object.hash(path, owned);

  @override
  String toString() => encode();
}

/// Документ Android по закреплённой ссылке `content://`.
///
/// Разрешение на ссылку закрепляется при выборе файла, поэтому книга
/// открывается и через месяц, и после перезагрузки. Файл при этом
/// остаётся там, где его положил читатель, и второго места не занимает.
final class DocumentUriSource extends BookSource {
  /// Создаёт источник-ссылку.
  const DocumentUriSource(this.uri);

  /// Ссылка вида `content://…`.
  final String uri;

  @override
  String encode() => '${BookSource._documentKind}:$uri';

  @override
  bool operator ==(Object other) =>
      other is DocumentUriSource && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;

  @override
  String toString() => encode();
}
