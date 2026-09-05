import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/infrastructure/pdf/pdf_info.dart';

/// Метаданные PDF — вторая ступень поиска.
///
/// Разбор намеренно терпимый: полноценно прочитать PDF значит написать
/// половину PDFium ради строки заголовка. Поэтому проверяется не полнота,
/// а честность — находим что можем, а чего не можем, честно не находим.
void main() {
  Uint8List bytes(String text) => Uint8List.fromList(text.codeUnits);

  group('обычный словарь Info', () {
    test('заголовок и автор читаются', () {
      final PdfInfo info = parsePdfInfo(
        bytes(
          '%PDF-1.7\n'
          '7 0 obj\n<< /Title (Pikovaya dama) /Author (Pushkin) >>\nendobj\n'
          'trailer\n<< /Info 7 0 R /Root 1 0 R >>\n',
        ),
      );
      expect(info.title, 'Pikovaya dama');
      expect(info.author, 'Pushkin');
      expect(info.isEmpty, isFalse);
    });

    test('в строку идут все четыре поля', () {
      final PdfInfo info = parsePdfInfo(
        bytes(
          '3 0 obj\n<< /Title (Kniga) /Author (Avtor) /Subject (Tema) '
          '/Keywords (odin dva) >>\nendobj\n'
          'trailer\n<< /Info 3 0 R >>\n',
        ),
      );
      expect(info.searchable, 'Kniga Avtor Tema odin dva');
    });

    test('экранированные скобки не рвут строку', () {
      final PdfInfo info = parsePdfInfo(
        bytes(
          '1 0 obj\n<< /Title (Kniga \\(vtoraya\\) chast) >>\nendobj\n'
          'trailer\n<< /Info 1 0 R >>\n',
        ),
      );
      expect(info.title, 'Kniga (vtoraya) chast');
    });

    test('вложенные скобки считаются', () {
      final PdfInfo info = parsePdfInfo(
        bytes(
          '1 0 obj\n<< /Title (Kniga (vtoraya) chast) >>\nendobj\n'
          'trailer\n<< /Info 1 0 R >>\n',
        ),
      );
      expect(info.title, 'Kniga (vtoraya) chast');
    });

    test('восьмеричное экранирование разбирается', () {
      // \101 — это `A`.
      final PdfInfo info = parsePdfInfo(
        bytes(
          '1 0 obj\n<< /Title (\\101BC) >>\nendobj\ntrailer\n<< /Info 1 0 R >>',
        ),
      );
      expect(info.title, 'ABC');
    });

    test('перевод строки внутри значения схлопывается', () {
      final PdfInfo info = parsePdfInfo(
        bytes(
          '1 0 obj\n<< /Title (Kniga\\ndva) >>\nendobj\n'
          'trailer\n<< /Info 1 0 R >>',
        ),
      );
      expect(info.title, 'Kniga dva');
    });
  });

  group('кириллица', () {
    test('UTF-16BE с меткой читается', () {
      // Так лежит любой русский заголовок: PDFDocEncoding кириллицы не
      // знает вовсе, и генераторы пишут её шестнадцатеричной строкой.
      final String title = _utf16Hex('Пиковая дама');
      final PdfInfo info = parsePdfInfo(
        bytes(
          '1 0 obj\n<< /Title <$title> >>\nendobj\ntrailer\n<< /Info 1 0 R >>',
        ),
      );
      expect(info.title, 'Пиковая дама');
    });

    test('шестнадцатеричная строка без метки читается как есть', () {
      final PdfInfo info = parsePdfInfo(
        bytes(
          '1 0 obj\n<< /Title <414243> >>\nendobj\ntrailer\n<< /Info 1 0 R >>',
        ),
      );
      expect(info.title, 'ABC');
    });
  });

  group('чего разбор не умеет', () {
    test('без Info и без Title метаданных нет', () {
      final PdfInfo info = parsePdfInfo(bytes('%PDF-1.4\ntrailer\n<< >>\n'));
      expect(info.isEmpty, isTrue);
      expect(info.title, isNull);
    });

    test('пустой заголовок считается отсутствующим', () {
      final PdfInfo info = parsePdfInfo(
        bytes('1 0 obj\n<< /Title () >>\nendobj\ntrailer\n<< /Info 1 0 R >>'),
      );
      expect(info.title, isNull);
    });

    test('мусор вместо файла не роняет разбор', () {
      expect(parsePdfInfo(bytes('не pdf вовсе')).isEmpty, isTrue);
      expect(parsePdfInfo(Uint8List(0)).isEmpty, isTrue);
    });

    test('словарь без Title находится прямым путём', () {
      // Ссылки на Info нет, но заголовок в файле есть — терпимый разбор
      // обязан его найти.
      final PdfInfo info = parsePdfInfo(
        bytes('9 0 obj\n<< /Type /Catalog /Title (Nayden) >>\nendobj\n'),
      );
      expect(info.title, 'Nayden');
    });

    test('последняя ссылка на Info главнее первой', () {
      // Файл дописывали: у него два трейлера, и верить надо последнему.
      final PdfInfo info = parsePdfInfo(
        bytes(
          '1 0 obj\n<< /Title (Staroe) >>\nendobj\n'
          'trailer\n<< /Info 1 0 R >>\n'
          '2 0 obj\n<< /Title (Novoe) >>\nendobj\n'
          'trailer\n<< /Info 2 0 R >>\n',
        ),
      );
      expect(info.title, 'Novoe');
    });
  });
}

/// Шестнадцатеричная строка PDF в UTF-16BE с меткой порядка байтов.
String _utf16Hex(String text) {
  final StringBuffer out = StringBuffer('FEFF');
  for (final int unit in text.codeUnits) {
    out.write(unit.toRadixString(16).padLeft(4, '0').toUpperCase());
  }
  return out.toString();
}
