import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/recording/journal_check.dart';

/// SNO-F-REC-13: самопроверка журнала записи — чистое правило.
///
/// Журнал здесь — байты, собранные руками: что лежит на диске после
/// остановки записи, проверка читает именно так.
void main() {
  /// Строки журнала с номерами [seqs], каждая с переводом строки.
  List<int> journal(List<int> seqs, {String tail = ''}) {
    final StringBuffer text = StringBuffer();
    for (final int seq in seqs) {
      text.write('{"seq":$seq,"t":${seq * 1000},"type":"page.shown"}\n');
    }
    text.write(tail);
    return utf8.encode(text.toString());
  }

  group('SNO-F-REC-13: журнал сверяется сам с собой', () {
    test('SNO-F-REC-13: все номера на месте, хвост цел — запись цела', () {
      final JournalCheck check = checkJournal(
        journal(<int>[1, 2, 3, 4, 5]),
        expected: 5,
      );

      expect(check.lines, 5);
      expect(check.gaps, 0);
      expect(check.torn, isFalse);
      expect(check.intact, isTrue);
      expect(check.late, isFalse);
    });

    test('SNO-F-REC-13: пропущенный номер найден', () {
      final JournalCheck check = checkJournal(
        journal(<int>[1, 2, 4, 5]),
        expected: 5,
      );

      expect(check.lines, 4);
      expect(check.gaps, 1);
      expect(check.intact, isFalse);
    });

    test('SNO-F-REC-13: события, посчитанные записью, но не дошедшие до '
        'диска, — пропуски', () {
      // Запись посчитала семь событий, а на диске пять: два последних
      // не легли.
      final JournalCheck check = checkJournal(
        journal(<int>[1, 2, 3, 4, 5]),
        expected: 7,
      );

      expect(check.lines, 5);
      expect(check.gaps, 2);
      expect(check.intact, isFalse);
    });

    test('SNO-F-REC-13: оборванный хвост найден и в счёт строк не идёт', () {
      final JournalCheck check = checkJournal(
        journal(<int>[1, 2, 3], tail: '{"seq":4,"t":40'),
        expected: 4,
      );

      expect(check.lines, 3);
      expect(check.torn, isTrue);
      // Четвёртое событие запись посчитала, а целой строки у него нет.
      expect(check.gaps, 1);
      expect(check.intact, isFalse);
    });

    test('SNO-F-REC-13: строка-мусор — целая, но её номера нет', () {
      // За обрывком успели дописать перевод строки: строка целая, но
      // не разбирается.
      final List<int> bytes = utf8.encode(
        '{"seq":1,"t":0,"type":"recording.start"}\n'
        '{"seq":2,"t":10\n'
        '{"seq":3,"t":20,"type":"page.shown"}\n',
      );

      final JournalCheck check = checkJournal(bytes, expected: 3);

      expect(check.lines, 3);
      expect(check.gaps, 1);
      expect(check.torn, isFalse);
      expect(check.intact, isFalse);
    });

    test('SNO-F-REC-13: сколько событий было, неизвестно — пропуски ищутся '
        'между первым и последним номером', () {
      final JournalCheck whole = checkJournal(
        journal(<int>[1, 2, 3]),
        late: true,
      );
      expect(whole.intact, isTrue);
      expect(whole.late, isTrue);

      final JournalCheck holed = checkJournal(
        journal(<int>[1, 2, 5]),
        late: true,
      );
      expect(holed.gaps, 2);
    });

    test('SNO-F-REC-13: пустой журнал цел, а журнал из одного обрывка — '
        'нет', () {
      final JournalCheck empty = checkJournal(const <int>[]);
      expect(empty.lines, 0);
      expect(empty.intact, isTrue);

      final JournalCheck scrap = checkJournal(utf8.encode('{"seq":1,"t'));
      expect(scrap.lines, 0);
      expect(scrap.torn, isTrue);
      expect(scrap.intact, isFalse);
    });

    test('SNO-F-REC-13: пустые строки строками не считаются', () {
      // После отказа диска следующая пачка начинается с перевода строки.
      final List<int> bytes = utf8.encode(
        '{"seq":1,"t":0,"type":"recording.start"}\n'
        '\n'
        '{"seq":2,"t":10,"type":"page.shown"}\n',
      );

      final JournalCheck check = checkJournal(bytes, expected: 2);

      expect(check.lines, 2);
      expect(check.intact, isTrue);
    });

    test('SNO-F-REC-13: битый UTF-8 проверку не роняет', () {
      final List<int> bytes = <int>[
        ...utf8.encode('{"seq":1,"t":0,"type":"recording.start"}\n'),
        0xD0,
        0x0A,
      ];

      final JournalCheck check = checkJournal(bytes, expected: 2);

      expect(check.lines, 2);
      expect(check.gaps, 1);
    });
  });

  group('SNO-F-REC-13: итог самопроверки хранится и говорится', () {
    test('SNO-F-REC-13: итог переживает запись в сведения и обратно', () {
      const JournalCheck check = JournalCheck(
        lines: 1479,
        gaps: 3,
        torn: true,
        late: true,
      );

      final JournalCheck? back = JournalCheck.fromJson(
        jsonDecode(jsonEncode(check.toJson())),
      );

      expect(back, isNotNull);
      expect(back!.lines, 1479);
      expect(back.gaps, 3);
      expect(back.torn, isTrue);
      expect(back.late, isTrue);
      // Цельной проверке в сведениях лишнего не пишут.
      expect(
        const JournalCheck(lines: 5, gaps: 0, torn: false).toJson(),
        <String, Object?>{'lines': 5, 'gaps': 0, 'torn': false},
      );
    });

    test('SNO-F-REC-13: запись, которая не читается, — не итог', () {
      expect(JournalCheck.fromJson(null), isNull);
      expect(JournalCheck.fromJson('цела'), isNull);
      expect(
        JournalCheck.fromJson(const <String, Object?>{'lines': 5}),
        isNull,
      );
    });

    test('SNO-F-REC-13: экран завершения говорит об итоге словами', () {
      expect(
        describeJournalCheck(
          const JournalCheck(lines: 1482, gaps: 0, torn: false),
        ),
        'Запись цела: 1482 строки, пропусков нет',
      );
      expect(
        describeJournalCheck(
          const JournalCheck(lines: 1479, gaps: 3, torn: true),
        ),
        'Запись неполная: 1479 строк, пропущено строк 3, последняя оборвана',
      );
      expect(
        describeJournalCheck(
          const JournalCheck(lines: 21, gaps: 0, torn: true),
        ),
        'Запись неполная: 21 строка, последняя оборвана',
      );
      expect(
        describeJournalCheck(null),
        'Запись не проверена: журнал не перечитался с диска.',
      );
    });

    test('SNO-F-REC-13: об оборванной записи «цела» не говорится', () {
      // Проверка видит только то, что успело лечь на диск: событий,
      // потерянных за последней строкой, она не найдёт.
      expect(
        describeJournalCheck(
          const JournalCheck(lines: 152, gaps: 0, torn: false, late: true),
        ),
        'Журнал цел до обрыва записи: 152 строки, пропусков нет',
      );
      expect(
        describeJournalCheck(
          const JournalCheck(lines: 152, gaps: 0, torn: true, late: true),
        ),
        'Запись неполная: 152 строки, последняя оборвана',
      );
    });

    test('SNO-F-REC-13: «строка» склоняется по числу', () {
      expect(describeLineCount(1), '1 строка');
      expect(describeLineCount(2), '2 строки');
      expect(describeLineCount(5), '5 строк');
      expect(describeLineCount(11), '11 строк');
      expect(describeLineCount(12), '12 строк');
      expect(describeLineCount(21), '21 строка');
      expect(describeLineCount(104), '104 строки');
      expect(describeLineCount(0), '0 строк');
    });
  });
}
