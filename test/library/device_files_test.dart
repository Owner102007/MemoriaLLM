import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/device_files.dart';
import 'package:memoria/domain/library/device_scan.dart';

/// Сверка обхода с тем, что уже знает база, и склейка дубликатов.
///
/// Два обещания сессии живут именно здесь: «повторный обход открывает
/// только изменившееся» и «перемещённый файл не заводит новой книги».
void main() {
  final DateTime early = DateTime.utc(2026, 9, 1, 10);
  final DateTime later = DateTime.utc(2026, 9, 5, 10);

  ScannedFile file(
    String path, {
    int size = 1000,
    DateTime? modified,
  }) {
    return ScannedFile(
      path: path,
      size: size,
      modifiedAt: modified ?? early,
    );
  }

  DeviceFileRecord known(
    String path, {
    int size = 1000,
    DateTime? modified,
    String? hash = 'hash-1',
    IndexStage stage = IndexStage.text,
    bool missing = false,
  }) {
    return DeviceFileRecord(
      path: path,
      size: size,
      modifiedAt: modified ?? early,
      seenAt: early,
      fingerprint: hash,
      stage: stage,
      missing: missing,
    );
  }

  group('повторный обход', () {
    test('прежний файл не разбирается заново', () {
      final List<ScanDecision> decisions = reconcileScan(
        known: <DeviceFileRecord>[known('/a/книга.pdf')],
        found: <ScannedFile>[file('/a/книга.pdf')],
        seenAt: later,
      );

      expect(decisions.single.verdict, ScanVerdict.unchanged);
      // Разобранное осталось при файле: ни отпечаток, ни ступень не
      // сброшены — иначе каждый заход на экран стоил бы полного разбора
      // всей библиотеки.
      expect(decisions.single.record.fingerprint, 'hash-1');
      expect(decisions.single.record.stage, IndexStage.text);
      expect(decisions.single.record.seenAt, later);
    });

    test('другой размер сбрасывает разборку', () {
      final List<ScanDecision> decisions = reconcileScan(
        known: <DeviceFileRecord>[known('/a/книга.pdf')],
        found: <ScannedFile>[file('/a/книга.pdf', size: 2000)],
        seenAt: later,
      );

      expect(decisions.single.verdict, ScanVerdict.changed);
      expect(decisions.single.record.fingerprint, isNull);
      expect(decisions.single.record.stage, IndexStage.name);
      expect(decisions.single.record.size, 2000);
    });

    test('другое время правки тоже сбрасывает разборку', () {
      final List<ScanDecision> decisions = reconcileScan(
        known: <DeviceFileRecord>[known('/a/книга.pdf')],
        found: <ScannedFile>[file('/a/книга.pdf', modified: later)],
        seenAt: later,
      );

      expect(decisions.single.verdict, ScanVerdict.changed);
      expect(decisions.single.record.stage, IndexStage.name);
    });

    test('новый файл заводится с нуля', () {
      final List<ScanDecision> decisions = reconcileScan(
        known: const <DeviceFileRecord>[],
        found: <ScannedFile>[file('/a/новая.pdf')],
        seenAt: later,
      );

      expect(decisions.single.verdict, ScanVerdict.added);
      expect(decisions.single.record.stage, IndexStage.name);
      expect(decisions.single.record.fingerprint, isNull);
    });

    test('пропавший файл помечается, но не забывается', () {
      // Карту памяти вынули и вставили обратно. Вместе с записью пропали
      // бы отпечаток и разобранные метаданные — минуты работы ради
      // файла, который никуда не девался.
      final List<ScanDecision> decisions = reconcileScan(
        known: <DeviceFileRecord>[known('/sd/книга.pdf')],
        found: const <ScannedFile>[],
        seenAt: later,
      );

      expect(decisions.single.verdict, ScanVerdict.gone);
      expect(decisions.single.record.missing, isTrue);
      expect(decisions.single.record.fingerprint, 'hash-1');
    });

    test('уже помеченный пропавшим второй раз не отмечается', () {
      final List<ScanDecision> decisions = reconcileScan(
        known: <DeviceFileRecord>[known('/sd/книга.pdf', missing: true)],
        found: const <ScannedFile>[],
        seenAt: later,
      );

      expect(decisions, isEmpty);
    });

    test('вернувшийся файл перестаёт быть пропавшим', () {
      final List<ScanDecision> decisions = reconcileScan(
        known: <DeviceFileRecord>[known('/sd/книга.pdf', missing: true)],
        found: <ScannedFile>[file('/sd/книга.pdf')],
        seenAt: later,
      );

      expect(decisions.single.verdict, ScanVerdict.unchanged);
      expect(decisions.single.record.missing, isFalse);
      expect(decisions.single.record.fingerprint, 'hash-1');
    });
  });

  group('дубликаты', () {
    test('один отпечаток — одна карточка', () {
      final List<DeviceBookEntry> entries = groupDeviceFiles(
        <DeviceFileRecord>[
          known('/storage/Downloads/telegram_photo/книга.pdf'),
          known('/storage/Книги/книга.pdf'),
          known('/storage/tmp/книга (1).pdf'),
        ],
      );

      expect(entries.length, 1);
      expect(entries.single.copies, 3);
      // Главным становится самый короткий путь: он почти всегда и есть
      // тот, куда книгу положил человек.
      expect(entries.single.primary.path, '/storage/Книги/книга.pdf');
      expect(entries.single.duplicatesLabel, 'ещё в 2 местах');
    });

    test('одна копия — без приписки', () {
      final List<DeviceBookEntry> entries = groupDeviceFiles(
        <DeviceFileRecord>[known('/a/книга.pdf')],
      );
      expect(entries.single.duplicatesLabel, '');
    });

    test('файлы без отпечатка стоят каждый сам по себе', () {
      // Показать файл сразу важнее, чем дождаться, пока станет ясно, что
      // это дубликат.
      final List<DeviceBookEntry> entries = groupDeviceFiles(
        <DeviceFileRecord>[
          known('/a/книга.pdf', hash: null),
          known('/b/книга.pdf', hash: null),
        ],
      );
      expect(entries.length, 2);
    });

    test('пропавшие файлы в список не попадают', () {
      final List<DeviceBookEntry> entries = groupDeviceFiles(
        <DeviceFileRecord>[known('/sd/книга.pdf', missing: true)],
      );
      expect(entries, isEmpty);
    });
  });

  group('название карточки', () {
    test('заголовок из метаданных главнее имени файла', () {
      final DeviceBookEntry entry = DeviceBookEntry(
        primary: known('/a/scan0043.pdf').copyWith(title: 'Пиковая дама'),
      );
      expect(entry.title, 'Пиковая дама');
    });

    test('служебный мусор из генератора отбрасывается', () {
      // «Microsoft Word - Document1» в заголовке — это не название книги,
      // а след программы, в которой её сохранили.
      final DeviceBookEntry entry = DeviceBookEntry(
        primary: known(
          '/a/Онегин.pdf',
        ).copyWith(title: 'Microsoft Word - Document1.doc'),
      );
      expect(entry.title, 'Онегин.pdf');
    });

    test('без метаданных берётся имя файла', () {
      expect(
        DeviceBookEntry(primary: known('/a/Онегин.pdf')).title,
        'Онегин.pdf',
      );
    });
  });

  group('ступени разборки', () {
    test('ступень знает, докуда дошли', () {
      expect(IndexStage.name.reached(IndexStage.meta), isFalse);
      expect(IndexStage.meta.reached(IndexStage.meta), isTrue);
      expect(IndexStage.text.reached(IndexStage.meta), isTrue);
    });

    test('выше текста ступеней нет', () {
      expect(IndexStage.name.next, IndexStage.meta);
      expect(IndexStage.meta.next, IndexStage.text);
      expect(IndexStage.text.next, IndexStage.text);
    });
  });
}
