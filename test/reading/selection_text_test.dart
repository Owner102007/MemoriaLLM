import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/reading/book_selection.dart';
import 'package:memoria/application/reading/book_text.dart';
import 'package:memoria/application/reading/reader_controller.dart';
import 'package:memoria/application/reading/selection_actions.dart';
import 'package:memoria/domain/annotations/annotations.dart';
import 'package:memoria/domain/prompts/selection_prompt.dart';
import 'package:memoria/domain/reading/page_text.dart';
import 'package:memoria/domain/reading/selection_text.dart';
import 'package:memoria/domain/reading/text_search.dart';
import 'package:memoria/sno/recording/event.dart';

import '../support/fake_reading.dart';
import '../support/recording_fakes.dart';

/// Цитаты и заметки в памяти: действиям над выделением база не нужна.
class _MemoryAnnotations implements AnnotationRepository {
  final List<Quote> savedQuotes = <Quote>[];
  final List<Note> savedNotes = <Note>[];

  @override
  Future<void> saveQuote(Quote quote) async => savedQuotes.add(quote);

  @override
  Future<void> saveNote(Note note) async => savedNotes.add(note);

  @override
  Future<List<Quote>> quotes(String bookId) async => savedQuotes;

  @override
  Future<List<Note>> notes(String bookId) async => savedNotes;

  @override
  Stream<List<Quote>> watchQuotes(String bookId) {
    return Stream<List<Quote>>.value(savedQuotes);
  }

  @override
  Stream<List<Note>> watchNotes(String bookId) {
    return Stream<List<Note>>.value(savedNotes);
  }

  @override
  Future<void> deleteQuote(String id) async {}

  @override
  Future<void> deleteNote(String id) async {}

  @override
  Stream<List<Bookmark>> watchBookmarks(String bookId) {
    return Stream<List<Bookmark>>.value(const <Bookmark>[]);
  }

  @override
  Future<List<Bookmark>> bookmarks(String bookId) async => const <Bookmark>[];

  @override
  Future<void> saveBookmark(Bookmark bookmark) async {}

  @override
  Future<void> deleteBookmark(String id) async {}
}

/// ALG-TXT-14, BUG-51: текст уходит из книги без знака переноса.
///
/// Правило — решение владельца Ф4 (вариант «в»): на месте знака ничего,
/// а дефис — если слово с дефисом написано в этой же книге целиком.
void main() {
  final String mark = String.fromCharCode(kLineBreakHyphen);

  group('BUG-51: правило знака переноса', () {
    test('BUG-51: без знака текст остаётся как есть', () {
      const String text = 'сердечно-сосудистая система';
      expect(leavingText(text), text);
      expect(hasLineBreakMark(text), isFalse);
      expect(hyphenSpellings(text), isEmpty);
    });

    test('BUG-51: слово с переноса склеивается', () {
      expect(leavingText('остео$markлогия'), 'остеология');
      expect(
        leavingText('наука остео$markлогия изучает кос$markти'),
        'наука остеология изучает кости',
      );
    });

    test('BUG-51: дефис встаёт, только если книга знает слово с ним', () {
      final String text = 'Сердечно$markсосудистая и остео$markлогия';
      expect(hyphenSpellings(text), <String>{
        'сердечно-сосудистая',
        'остео-логия',
      });
      expect(
        leavingText(text, hyphenated: <String>{'сердечно-сосудистая'}),
        'Сердечно-сосудистая и остеология',
      );
      // Книга не знает ни одного — дефисов нет вовсе.
      expect(leavingText(text), 'Сердечнососудистая и остеология');
    });

    test('BUG-51: знак на краю слова ничего не разрезает', () {
      expect(leavingText('$markлогия'), 'логия');
      expect(leavingText('остео$mark'), 'остео');
      expect(leavingText('остео$mark логия'), 'остео логия');
      expect(hyphenSpellings('остео$mark логия'), isEmpty);
      expect(leavingText(mark), '');
    });

    test('BUG-51: два переноса в одном слове — каждый решается сам', () {
      final String text = 'северо$markзападно$markевропейский';
      expect(hyphenSpellings(text), <String>{
        'северо-западно',
        'западно-европейский',
      });
      expect(
        leavingText(text, hyphenated: <String>{'северо-западно'}),
        'северо-западноевропейский',
      );
    });

    test('BUG-51: слово ищется целым, а не куском другого', () {
      expect(containsWholeWord('он self-made человек', 'self-made'), isTrue);
      expect(containsWholeWord('self-made', 'self-made'), isTrue);
      expect(containsWholeWord('herself-made', 'self-made'), isFalse);
      expect(containsWholeWord('self-mademoiselle', 'self-made'), isFalse);
      // Место на переносе само себе не свидетель.
      expect(containsWholeWord('self${mark}made', 'self-made'), isFalse);
      expect(containsWholeWord('что угодно', ''), isFalse);
    });

    test('BUG-51: написания сравниваются без регистра и без разницы между '
        'ё и е', () {
      final String text = 'Трёх$markмерный';
      expect(hyphenSpellings(text), <String>{'трех-мерный'});
      // Буквы самого текста при этом остаются как были.
      expect(
        leavingText(text, hyphenated: hyphenSpellings(text)),
        'Трёх-мерный',
      );
      expect(
        containsWholeWord(spellingKey('ТРЁХ-мерный куб'), 'трех-мерный'),
        isTrue,
      );
    });

    test('BUG-51: буква с приставленным знаком — одно слово', () {
      // «й», записанная буквой «и» и отдельной краткой (U+0306).
      const String breve = '\u0306';
      // Слово продолжается после краткой: целым «бело-серыи» здесь нет.
      expect(containsWholeWord('бело-серыи$breveшии', 'бело-серыи'), isFalse);
      // Половина слова с такой буквой у переноса не теряется.
      expect(hyphenSpellings('краи$breve$markне'), <String>{'краи$breve-не'});
    });

    test('BUG-51: один знак переноса — не выделение', () {
      final BookSelection only = BookSelection(
        pageNumber: 1,
        start: 4,
        end: 5,
        text: mark,
      );
      expect(only.isEmpty, isTrue);
      final BookSelection word = BookSelection(
        pageNumber: 1,
        start: 0,
        end: 9,
        text: 'пере$markнос',
      );
      expect(word.isEmpty, isFalse);
    });
  });

  group('BUG-51: что знает книга', () {
    const String bookId = 'book-1';
    const String hash = 'hash-1';

    BookTextCache cacheOf(
      FakeReaderDocument document,
      MemoryPageTextStore store,
    ) {
      return BookTextCache(
        document: document,
        store: store,
        bookId: bookId,
        fingerprint: hash,
        version: kPageTextVersion,
      );
    }

    FakeReaderDocument book() {
      return FakeReaderDocument(
        pages: <String>[
          'He bought a micro${mark}scope and felt self${mark}made.',
          'A microscope is useful.',
          'A Self-Made man from Saint${mark}Petersburg.',
        ],
      );
    }

    test('BUG-51: дефис — по тексту прочитанной книги', () async {
      final FakeReaderDocument document = book();
      final BookTextCache cache = cacheOf(document, MemoryPageTextStore());
      cache.startPass(from: 1);
      await cache.passDone();

      expect(
        await cache.leaving('a micro${mark}scope and felt self${mark}made'),
        'a microscope and felt self-made',
      );
      // Слова с дефисом в книге больше нигде нет — склеено без него.
      expect(await cache.leaving('Saint${mark}Petersburg'), 'SaintPetersburg');
      cache.close();
    });

    test(
      'BUG-51: книга ещё не прочитана — дефиса нет, движок не тронут',
      () async {
        final FakeReaderDocument document = book();
        final BookTextCache cache = cacheOf(document, MemoryPageTextStore());

        expect(await cache.leaving('self${mark}made'), 'selfmade');
        expect(document.textReads, isEmpty);
        cache.close();
      },
    );

    test('BUG-51: база не читается — знак всё равно убран', () async {
      final FakeReaderDocument document = book();
      final MemoryPageTextStore store = MemoryPageTextStore();
      final BookTextCache cache = cacheOf(document, store);
      cache.startPass(from: 1);
      await cache.passDone();
      store.failReads = true;

      expect(await cache.leaving('self${mark}made'), 'selfmade');
      cache.close();
    });

    test('BUG-51: о том же слове книгу второй раз не читают', () async {
      final MemoryPageTextStore store = MemoryPageTextStore();
      final BookTextCache cache = cacheOf(book(), store);
      cache.startPass(from: 1);
      await cache.passDone();

      // Слово, которого с дефисом в книге нет: просмотрена вся книга.
      expect(await cache.leaving('micro${mark}scope'), 'microscope');
      final int once = store.textQueries;
      expect(once, greaterThan(0));
      // Второй вопрос о нём же в базу не ходит; о найденном — тоже.
      expect(await cache.leaving('micro${mark}scope'), 'microscope');
      expect(await cache.leaving('self${mark}made'), 'self-made');
      final int twice = store.textQueries;
      expect(await cache.leaving('self${mark}made'), 'self-made');
      expect(await cache.leaving('a micro${mark}scope'), 'a microscope');
      expect(store.textQueries, twice);
      cache.close();
    });

    test('BUG-51: страница дочиталась позже — слово находится', () async {
      final MemoryPageTextStore store = MemoryPageTextStore();
      final FakeReaderDocument document = book();
      final BookTextCache cache = cacheOf(document, store);
      // Запомнена только первая страница: слова с дефисом на ней нет.
      await cache.textsOf(1, 1);
      expect(await cache.leaving('self${mark}made'), 'selfmade');

      // Проход дочитал книгу: третья страница знает слово с дефисом.
      cache.startPass(from: 1);
      await cache.passDone();
      expect(await cache.leaving('self${mark}made'), 'self-made');
      cache.close();
    });

    test('BUG-51: одно выделение спрашивают сразу трое — книга читается '
        'один раз', () async {
      final MemoryPageTextStore store = MemoryPageTextStore();
      final BookTextCache cache = cacheOf(book(), store);
      cache.startPass(from: 1);
      await cache.passDone();
      final int before = store.textQueries;

      final List<String> answers = await Future.wait(<Future<String>>[
        cache.leaving('micro${mark}scope'),
        cache.leaving('micro${mark}scope'),
        cache.leaving('micro${mark}scope'),
      ]);

      expect(answers, <String>['microscope', 'microscope', 'microscope']);
      expect(store.textQueries, before + 1);
      cache.close();
    });

    test('BUG-51: текст всей книги с сотней переносов книгу о каждом не '
        'спрашивает', () async {
      final MemoryPageTextStore store = MemoryPageTextStore();
      final BookTextCache cache = cacheOf(book(), store);
      cache.startPass(from: 1);
      await cache.passDone();
      final int before = store.textQueries;
      // «Выделить всё» в ленте: разрезанных слов — как в целой книге.
      final String whole = <String>[
        for (int i = 0; i < 100; i++) 'word$i${mark}tail',
        'self${mark}made',
      ].join(' ');

      final String clean = await cache.leaving(whole);

      expect(clean, isNot(contains(mark)));
      expect(clean, startsWith('word0tail word1tail'));
      // Дефисов в таком тексте нет вовсе — и знакомому слову тоже.
      expect(clean, endsWith('selfmade'));
      expect(store.textQueries, before);
      cache.close();
    });

    test('BUG-51: текст без знака в базу не ходит', () async {
      final MemoryPageTextStore store = MemoryPageTextStore();
      final BookTextCache cache = cacheOf(book(), store);
      cache.startPass(from: 1);
      await cache.passDone();
      final int before = store.textQueries;

      expect(await cache.leaving('обычный текст'), 'обычный текст');
      expect(store.textQueries, before);
      cache.close();
    });
  });

  group('BUG-51: выделенное уходит из книги чистым', () {
    late FakeReaderDocument document;
    late ReaderController controller;
    late BookTextCache texts;
    late _MemoryAnnotations annotations;
    late ListActionLog log;
    late SelectionActions actions;

    final String first =
        'He bought a micro${mark}scope and felt self${mark}made.';

    setUp(() async {
      document = FakeReaderDocument(
        pages: <String>[first, 'A microscope helps a self-made man.'],
      );
      controller = await ReaderController.open(
        book: fakeBook(),
        opener: FakeDocumentOpener(document),
        reading: FakeReadingRepository(),
      );
      texts = BookTextCache(
        document: document,
        store: MemoryPageTextStore(),
        bookId: 'book-read',
        fingerprint: 'hash-read',
      );
      texts.startPass(from: 1);
      await texts.passDone();
      annotations = _MemoryAnnotations();
      log = ListActionLog();
      int ids = 0;
      actions = SelectionActions(
        controller: controller,
        annotations: annotations,
        bookId: 'book-read',
        texts: texts,
        log: log,
        now: () => DateTime.utc(2026, 10, 5, 12),
        newId: () => 'id-${++ids}',
      );
    });

    tearDown(() async {
      texts.close();
      await controller.close();
      controller.dispose();
    });

    BookSelection whole() {
      return BookSelection(
        pageNumber: 1,
        start: 0,
        end: first.length,
        text: first,
      );
    }

    test('BUG-51: в цитате и в её абзаце знака переноса нет', () async {
      final Quote quote = await actions.saveQuote(whole());

      expect(quote.content, 'He bought a microscope and felt self-made.');
      expect(quote.content, isNot(contains(mark)));
      expect(quote.context, isNotNull);
      expect(quote.context, isNot(contains(mark)));
      expect(quote.textStart, 0);
      expect(quote.textEnd, first.length);
      expect(annotations.savedQuotes.single.id, 'id-1');
    });

    test('BUG-51: в скопированном знака переноса нет', () async {
      expect(
        await actions.textOf(whole()),
        'He bought a microscope and felt self-made.',
      );
    });

    test('BUG-51: в готовом запросе знака переноса нет', () async {
      final DateTime now = DateTime.utc(2026, 10, 5);
      final SelectionPrompt prompt = SelectionPrompt(
        id: 'p-1',
        name: 'Объясни',
        body: 'Объясни «{{выделение}}».\nОтрывок: {{контекст}}',
        position: 0,
        createdAt: now,
        updatedAt: now,
      );
      final String request = await actions.request(whole(), prompt);

      expect(request, isNot(contains(mark)));
      expect(request, contains('microscope and felt self-made'));
    });

    test('BUG-51: заметка сохраняет цитату без знака переноса', () async {
      final Note note = await actions.saveNote(whole(), 'проверить');

      expect(note.body, 'проверить');
      expect(annotations.savedQuotes.single.content, isNot(contains(mark)));
      expect(note.quoteId, annotations.savedQuotes.single.id);
    });

    test('SNO-F-REC-02: выделение и действия над ним — в журнале, с текстом '
        'без знака переноса', () async {
      await actions.settled(whole());
      await actions.acted('quote', whole());
      await actions.saveQuote(whole());
      await actions.acted('note', whole());
      await actions.saveNote(whole(), 'проверить');
      await actions.cancelled();

      expect(log.types, <String>[
        'select.end',
        'selection.action',
        'quote.create',
        'selection.action',
        'quote.create',
        'note.create',
        'select.cancel',
      ]);
      final Map<String, Object?> selected = log
          .dataOf(SnoEventType.selectEnd)
          .single;
      expect(selected['page'], 1);
      expect(selected['start'], 0);
      expect(selected['end'], first.length);
      expect(selected['text'], 'He bought a microscope and felt self-made.');
      expect(selected['words'], 7);
      expect(
        log
            .dataOf(SnoEventType.selectionAction)
            .map((Map<String, Object?> data) => data['action']),
        <String>['quote', 'note'],
      );
      expect(log.dataOf(SnoEventType.noteCreate).single['text'], 'проверить');
      for (final ({SnoEventType type, Map<String, Object?> data}) event
          in log.events) {
        expect('${event.data['text'] ?? ''}', isNot(contains(mark)));
      }
    });

    test(
      'SNO-F-REC-02: запись не идёт — действия работают, журнал пуст',
      () async {
        log.recording = false;
        await actions.settled(whole());
        await actions.acted('copy', whole());
        await actions.saveQuote(whole());
        await actions.cancelled();
        await actions.copiedLoose('текст');

        expect(log.events, isEmpty);
        // Вне записи событие даже не собирают.
        expect(log.asked, 0);
        expect(annotations.savedQuotes, hasLength(1));
      },
    );

    test('SNO-F-REC-02: выделение сняли, пока его текст считался, — в '
        'журнале оно всё равно раньше своего снятия', () async {
      // Текст выделения с переносом считается по книге и не сразу.
      final Future<void> selected = actions.settled(whole());
      final Future<void> dropped = actions.cancelled();
      await Future.wait(<Future<void>>[selected, dropped]);

      expect(log.types, <String>['select.end', 'select.cancel']);
    });

    test('BUG-51: заметка сохраняет цитату, какой её показало окно', () async {
      final Note note = await actions.saveNote(
        whole(),
        'проверить',
        text: 'показанное в окне',
      );

      expect(annotations.savedQuotes.single.content, 'показанное в окне');
      expect(note.quoteId, annotations.savedQuotes.single.id);
    });

    test('SNO-F-REC-02: скопированное в ленте — действием с текстом и '
        'пометкой ленты', () async {
      final String clean = await actions.leaving('micro${mark}scope');
      await actions.copiedLoose(clean);

      expect(clean, 'microscope');
      final Map<String, Object?> copied = log
          .dataOf(SnoEventType.selectionAction)
          .single;
      expect(copied, <String, Object?>{
        'action': 'copy',
        'flow': 'ribbon',
        'text': 'microscope',
      });
    });
  });
}
