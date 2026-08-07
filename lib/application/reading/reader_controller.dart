import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/library/book.dart';
import '../../domain/reading/navigation.dart';
import '../../domain/reading/reader_document.dart';
import '../../domain/reading/reading.dart';

/// Состояние открытой книги: где читатель сейчас и что об этом знает база.
///
/// Контроллер не знает ни про виджеты, ни про PDFium: документ приходит
/// готовым интерфейсом [ReaderDocument], позиция уходит в
/// [ReadingRepository]. Поэтому всё поведение — восстановление места,
/// частота записи, оглавление — проверяется обычными тестами, без экрана
/// и без настоящего PDF.
class ReaderController extends ChangeNotifier {
  /// Создаёт контроллер для уже открытого документа.
  ReaderController({
    required this.book,
    required ReaderDocument document,
    required ReadingRepository reading,
    ReadingPosition? position,
    Duration saveDelay = const Duration(seconds: 2),
  }) : _document = document,
       _reading = reading,
       _saveDelay = saveDelay,
       _page = restorePage(position, document.pageCount) {
    _initialPage = _page;
  }

  /// Открывает книгу и восстанавливает место, на котором её оставили.
  static Future<ReaderController> open({
    required Book book,
    required DocumentOpener opener,
    required ReadingRepository reading,
    String? password,
    Duration saveDelay = const Duration(seconds: 2),
  }) async {
    final ReaderDocument document = await opener.open(
      book.filePath,
      password: password,
    );
    try {
      final ReadingPosition? position = await reading.position(book.id);
      return ReaderController(
        book: book,
        document: document,
        reading: reading,
        position: position,
        saveDelay: saveDelay,
      );
    } on Object {
      // База сломалась на ровном месте — документ всё равно надо закрыть,
      // иначе утечёт память движка.
      await document.close();
      rethrow;
    }
  }

  /// Книга.
  final Book book;

  final ReaderDocument _document;
  final ReadingRepository _reading;
  final Duration _saveDelay;

  int _page;
  late final int _initialPage;
  Timer? _saveTimer;
  bool _dirty = false;
  bool _closed = false;
  List<OutlineEntry>? _outline;
  bool _outlineLoading = false;

  /// Документ. Нужен поиску и будущей автообрезке (S4).
  ReaderDocument get document => _document;

  /// Число страниц.
  int get pageCount => _document.pageCount;

  /// Текущая страница, начиная с единицы.
  int get page => _page;

  /// Страница, с которой книга открылась.
  ///
  /// Отличается от [page] тем, что не меняется: экран отдаёт её просмотрщику
  /// при первой отрисовке и больше к ней не возвращается.
  int get initialPage => _initialPage;

  /// Доля прочитанного, от 0 до 1.
  double get progress => progressForPage(_page, pageCount);

  /// Подпись для панели: `12 / 340`.
  String get label => pageLabel(_page, pageCount);

  /// Оглавление; `null` — ещё не читали.
  List<OutlineEntry>? get outline => _outline;

  /// Идёт ли чтение оглавления.
  bool get isOutlineLoading => _outlineLoading;

  /// Есть ли в книге оглавление. `null` — пока неизвестно.
  bool? get hasOutline => _outline?.isNotEmpty;

  /// Читает оглавление документа. Повторные вызовы бесплатны.
  Future<void> loadOutline() async {
    if (_outline != null || _outlineLoading || _closed) {
      return;
    }
    _outlineLoading = true;
    notifyListeners();
    try {
      _outline = await _document.outline();
    } on Object {
      // Испорченное оглавление — не повод не дать читать книгу.
      _outline = const <OutlineEntry>[];
    } finally {
      _outlineLoading = false;
      if (!_closed) {
        notifyListeners();
      }
    }
  }

  /// Просмотрщик сообщил, что показывается другая страница.
  void onPageChanged(int page) {
    final int safe = clampPage(page, pageCount);
    if (safe == _page) {
      return;
    }
    _page = safe;
    _dirty = true;
    notifyListeners();
    _scheduleSave();
  }

  /// Записывает позицию немедленно.
  ///
  /// Вызывается при уходе с экрана и при сворачивании приложения: система
  /// вправе убить процесс сразу после этого, а место в книге терять нельзя.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_dirty) {
      return;
    }
    _dirty = false;
    await _reading.savePosition(
      positionForPage(
        bookId: book.id,
        page: _page,
        pageCount: pageCount,
      ),
    );
  }

  /// Записывает позицию и закрывает документ.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await flush();
    await _document.close();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    super.dispose();
  }

  /// Планирует запись позиции.
  ///
  /// Таймер намеренно **не** перезапускается на каждой странице. При
  /// быстром листании перезапуск откладывал бы запись бесконечно, и
  /// закрытое по питанию приложение теряло бы место. Здесь же запись
  /// случается не реже одного раза в [_saveDelay], сколько бы страниц
  /// ни пролистали.
  void _scheduleSave() {
    _saveTimer ??= Timer(_saveDelay, () {
      _saveTimer = null;
      unawaited(flush());
    });
  }
}
