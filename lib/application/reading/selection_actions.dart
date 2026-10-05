import 'dart:async';

import '../../domain/annotations/annotations.dart';
import '../../domain/library/ids.dart';
import '../../domain/prompts/selection_prompt.dart';
import '../../domain/reading/context_paragraph.dart';
import '../../domain/reading/selection_text.dart';
import '../../sno/recording/action_log.dart';
import '../../sno/recording/event.dart';
import 'book_selection.dart';
import 'book_text.dart';
import 'reader_controller.dart';

/// Действия над выделенным текстом: что из него уходит из книги и
/// куда (ALG-TXT-14, BUG-51, SNO-F-REC-02).
///
/// Выделенное уходит четырьмя путями — в цитату, в заметку, в буфер
/// обмена и в запрос к модели, — и на каждом обязано уйти чистым: без
/// знака, которым движок отмечает перенос слова. Прежде текст брался у
/// выделения как есть в четырёх местах экрана чтения, и знак уезжал
/// вместе с ним. Теперь путь один: [textOf] и [contextOf]. Пятый выход
/// — «Копировать» в ленте, где выделение ведёт сам просмотрщик и места
/// в тексте страницы у него нет, — чистит текст здесь же ([leaving]).
///
/// Здесь же действия пишутся в журнал записи сборок ветвей СНО2026:
/// что выделено и что с этим сделано — с текстом целиком (решение В3).
///
/// Виджетов здесь нет: лист с выделением в тестах не строится, а эти
/// действия проверяются.
class SelectionActions {
  /// Создаёт действия над выделением книги [bookId].
  ///
  /// [texts] — кэш текста книги: он знает, какие слова написаны в ней
  /// с дефисом; без него знак переноса просто убирается. [log] —
  /// журнал записи; `null` — в этой сборке записи нет. [now] и [newId]
  /// подменяются в тестах.
  SelectionActions({
    required ReaderController controller,
    required AnnotationRepository annotations,
    required String bookId,
    BookTextCache? texts,
    ActionLog? log,
    DateTime Function()? now,
    String Function()? newId,
  }) : _controller = controller,
       _annotations = annotations,
       _bookId = bookId,
       _texts = texts,
       _log = log,
       _now = now ?? DateTime.now,
       _newId = newId ?? newLibraryId;

  final ReaderController _controller;
  final AnnotationRepository _annotations;
  final String _bookId;
  final BookTextCache? _texts;
  final ActionLog? _log;
  final DateTime Function() _now;
  final String Function() _newId;

  static final RegExp _spaces = RegExp(r'\s+');

  /// Очередь записей в журнал. Текст выделения с переносом считается
  /// по книге и не сразу: событие, которое его ждёт, не должно лечь в
  /// журнал после события, случившегося позже, — «выделение снято»
  /// раньше самого выделения.
  Future<void> _order = Future<void>.value();

  Future<void> _inOrder(FutureOr<void> Function() write) {
    final Future<void> next = _order.then((_) => write());
    _order = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// Текст [text] таким, каким он уходит из книги.
  ///
  /// Сбой кэша — не повод оставить знак: тогда он убирается без дефиса.
  Future<String> leaving(String text) async {
    if (!hasLineBreakMark(text)) {
      return text;
    }
    final BookTextCache? texts = _texts;
    if (texts == null) {
      return leavingText(text);
    }
    try {
      return await texts.leaving(text);
    } on Object {
      return leavingText(text);
    }
  }

  /// Выделенный текст — без знаков переноса.
  Future<String> textOf(BookSelection selection) => leaving(selection.text);

  /// Абзац вокруг выделения — без знаков переноса; `null` — абзаца не
  /// нашлось.
  Future<String?> contextOf(BookSelection selection) async {
    final ParagraphContext? paragraph = await _controller.contextAround(
      pageNumber: selection.pageNumber,
      start: selection.start,
      end: selection.end,
    );
    return paragraph == null ? null : leaving(paragraph.text);
  }

  /// Идёт ли запись: данные события собирают, только если да.
  bool get _recording => _log?.recording ?? false;

  Map<String, Object?> _placeOf(BookSelection selection) {
    return <String, Object?>{
      'page': selection.pageNumber,
      'start': selection.start,
      'end': selection.end,
    };
  }

  /// Выделение устоялось: в журнал — `select.end` с текстом.
  Future<void> settled(BookSelection selection) {
    if (!_recording) {
      return Future<void>.value();
    }
    return _inOrder(() async {
      final String text = await textOf(selection);
      final String flat = text.trim();
      _log?.log(
        SnoEventType.selectEnd,
        data: <String, Object?>{
          ..._placeOf(selection),
          ...journalText(text),
          'words': flat.isEmpty ? 0 : flat.split(_spaces).length,
        },
      );
    });
  }

  /// Выделение снято без действия над ним.
  Future<void> cancelled() {
    if (!_recording) {
      return Future<void>.value();
    }
    return _inOrder(() => _log?.log(SnoEventType.selectCancel));
  }

  /// Выделенное скопировано там, где места в тексте страницы у него
  /// нет, — в ленте; [text] — уже очищенный.
  Future<void> copiedLoose(String text) {
    if (!_recording) {
      return Future<void>.value();
    }
    return _inOrder(
      () => _log?.log(
        SnoEventType.selectionAction,
        data: <String, Object?>{
          'action': 'copy',
          'flow': 'ribbon',
          ...journalText(text),
        },
      ),
    );
  }

  /// Нажато действие [action] панели над выделением: `quote`, `note`,
  /// `copy`, `find`, `prompt`. [extra] — что добавить к событию.
  Future<void> acted(
    String action,
    BookSelection selection, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    if (!_recording) {
      return Future<void>.value();
    }
    return _inOrder(() async {
      final String text = await textOf(selection);
      _log?.log(
        SnoEventType.selectionAction,
        data: <String, Object?>{
          'action': action,
          ..._placeOf(selection),
          ...journalText(text),
          ...extra,
        },
      );
    });
  }

  /// Сохраняет выделенное цитатой.
  ///
  /// Контекст сохраняется всегда, а не только когда его просит промпт:
  /// по нему через месяц видно, откуда цитата и о чём там была речь.
  ///
  /// [text] — текст цитаты, если он уже посчитан и показан читателю:
  /// сохраняется ровно то, что он видел.
  Future<Quote> saveQuote(BookSelection selection, {String? text}) async {
    final String content = text ?? await textOf(selection);
    final String? context = await contextOf(selection);
    final Quote quote = Quote(
      id: _newId(),
      bookId: _bookId,
      page: selection.pageNumber,
      content: content,
      context: context,
      // Место цитаты в тексте страницы: по нему она подсвечивается,
      // когда читатель возвращается к ней из списка. У цитат,
      // сохранённых до схемы 8, его нет — такие открываются на своей
      // странице без подсветки.
      textStart: selection.start,
      textEnd: selection.end,
      createdAt: _now(),
    );
    await _annotations.saveQuote(quote);
    if (_recording) {
      await _inOrder(
        () => _log?.log(
          SnoEventType.quoteCreate,
          data: <String, Object?>{
            'id': quote.id,
            ..._placeOf(selection),
            ...journalText(content),
          },
        ),
      );
    }
    return quote;
  }

  /// Сохраняет заметку [body] к выделенному — вместе с самой цитатой.
  ///
  /// Заметка «здесь автор себе противоречит» без того, чему она
  /// противоречит, через месяц не значит ничего. [text] — текст цитаты,
  /// каким его показало окно заметки.
  Future<Note> saveNote(
    BookSelection selection,
    String body, {
    String? text,
  }) async {
    final Quote quote = await saveQuote(selection, text: text);
    final DateTime now = _now();
    final Note note = Note(
      id: _newId(),
      bookId: _bookId,
      quoteId: quote.id,
      page: quote.page,
      body: body,
      createdAt: now,
      updatedAt: now,
    );
    await _annotations.saveNote(note);
    if (_recording) {
      await _inOrder(
        () => _log?.log(
          SnoEventType.noteCreate,
          data: <String, Object?>{
            'id': note.id,
            'quote': quote.id,
            'page': note.page,
            ...journalText(body),
          },
        ),
      );
    }
    return note;
  }

  /// Готовый запрос к модели по промпту [prompt].
  ///
  /// Абзац-контекст извлекается, только если промпт его просит.
  Future<String> request(
    BookSelection selection,
    SelectionPrompt prompt, {
    String? bookLanguage,
    String? myLanguage,
  }) async {
    final String text = await textOf(selection);
    final String? context = prompt.check.needsContext
        ? await contextOf(selection)
        : null;
    return fillPrompt(
      prompt.body,
      selection: text,
      context: context,
      bookLanguage: bookLanguage,
      myLanguage: myLanguage,
    );
  }
}
