import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/sno/index/shelf_reading.dart';
import 'package:memoria/sno/index/shelf_reading_log.dart';
import 'package:memoria/sno/recording/event.dart';

import '../data/test_data.dart';
import '../support/recording_fakes.dart';
import '../support/shown_reading.dart';

/// Шаг 23, SNO-F-IDX-04: ход подготовки книг в журнале записи.
///
/// Подготовка здесь — та, состоянием которой распоряжается тест, а
/// журнал просто копит записанное: проверяется, о чём пишется строка
/// `index.progress` и о чём — нет.
void main() {
  late AppData data;
  late ShownReading reading;
  late ListActionLog log;
  late void Function() stop;

  setUp(() async {
    data = await openTestData();
    reading = ShownReading(data);
    log = ListActionLog();
    stop = logShelfReading(reading, log);
  });
  tearDown(() async {
    stop();
    reading.dispose();
    await data.close();
  });

  List<Map<String, Object?>> said() => log.dataOf(SnoEventType.indexProgress);

  test('SNO-F-IDX-04: смена дела и каждая прочитанная книга — строкой, '
      'страницы — нет', () {
    reading.show(
      const ShelfReadingProgress(
        phase: ShelfReadingPhase.reading,
        booksTotal: 3,
        title: 'Первая',
        page: 1,
        pages: 200,
      ),
    );
    // Страницы одной книги: счёт книг не меняется.
    for (int page = 2; page <= 50; page++) {
      reading.show(
        ShelfReadingProgress(
          phase: ShelfReadingPhase.reading,
          booksTotal: 3,
          title: 'Первая',
          page: page,
          pages: 200,
        ),
      );
    }
    reading.show(
      const ShelfReadingProgress(
        phase: ShelfReadingPhase.reading,
        booksDone: 1,
        booksTotal: 3,
        elapsedMs: 4200,
      ),
    );

    expect(said(), hasLength(2));
    expect(said()[0], <String, Object?>{
      'phase': 'reading',
      'books_done': 0,
      'books_total': 3,
      'elapsed_ms': 0,
    });
    expect(said()[1]['books_done'], 1);
    expect(said()[1]['elapsed_ms'], 4200);
    // Названия книги в журнале нет: книга названа счётом.
    expect(said()[0].containsKey('title'), isFalse);
  });

  test('SNO-F-IDX-04: расчёт карты и итог — с отпечатком карты', () {
    reading
      ..show(
        const ShelfReadingProgress(
          phase: ShelfReadingPhase.reading,
          booksDone: 2,
          booksTotal: 3,
        ),
      )
      ..show(
        const ShelfReadingProgress(
          phase: ShelfReadingPhase.mapping,
          booksDone: 3,
          booksTotal: 3,
          mapTotal: 3,
        ),
      )
      // Ход расчёта карты строками не идёт.
      ..show(
        const ShelfReadingProgress(
          phase: ShelfReadingPhase.mapping,
          booksDone: 3,
          booksTotal: 3,
          mapDone: 1,
          mapTotal: 3,
        ),
      )
      ..show(
        const ShelfReadingProgress(
          phase: ShelfReadingPhase.done,
          booksDone: 3,
          booksTotal: 3,
          elapsedMs: 9000,
        ),
        summary: const ShelfIndexSummary(
          complete: true,
          books: 3,
          pages: 640,
          scans: 1,
          map: MapSummary(
            state: MapSummary.built,
            books: 3,
            groups: 2,
            ms: 120,
            fingerprint: '6be411b9',
          ),
        ),
      );

    expect(
      said().map((Map<String, Object?> line) => line['phase']),
      <String>['reading', 'mapping', 'done'],
    );
    expect(said()[1]['map_total'], 3);
    final Map<String, Object?> done = said().last;
    expect(done['pages'], 640);
    expect(done['scans'], 1);
    expect(done['unread'], 0);
    expect(
      (done['map']! as Map<String, Object?>)['fingerprint'],
      '6be411b9',
    );
  });

  test('SNO-F-IDX-04: подготовке нечего было делать — журнал молчит', () {
    // Обычный запуск: всё прочитано заранее, проход только сверяет.
    for (int done = 0; done <= 3; done++) {
      reading.show(ShelfReadingProgress(booksDone: done, booksTotal: 3));
    }
    reading.show(
      const ShelfReadingProgress(
        phase: ShelfReadingPhase.done,
        booksDone: 3,
        booksTotal: 3,
      ),
    );

    expect(said(), isEmpty);
  });

  test('SNO-F-IDX-04: запись не идёт — строк нет; началась посреди '
      'подготовки — первая же строка говорит, где та стоит', () {
    log.recording = false;
    reading.show(
      const ShelfReadingProgress(
        phase: ShelfReadingPhase.reading,
        booksDone: 1,
        booksTotal: 3,
      ),
    );
    expect(log.asked, 0);

    log.recording = true;
    reading.show(
      const ShelfReadingProgress(
        phase: ShelfReadingPhase.reading,
        booksDone: 1,
        booksTotal: 3,
        page: 7,
        pages: 90,
      ),
    );

    expect(said().single['books_done'], 1);
  });

  test('SNO-F-IDX-04: перестали слушать — строк больше нет', () {
    stop();
    reading.show(
      const ShelfReadingProgress(
        phase: ShelfReadingPhase.reading,
        booksTotal: 3,
      ),
    );

    expect(said(), isEmpty);
  });
}
