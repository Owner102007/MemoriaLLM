import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../application/app_services.dart';
import '../../application/reading/document_search.dart';
import '../../application/reading/reader_controller.dart';
import '../../domain/library/book.dart';
import '../../domain/reading/reader_document.dart';
import 'reader_scaffold.dart';

/// Как листается книга.
enum PageFlow {
  /// Непрерывная лента страниц сверху вниз.
  continuous,

  /// Страница за страницей вбок.
  paged,
}

/// Экран чтения.
///
/// Единственное место, где встречаются `pdfrx` и всё остальное:
/// просмотрщик рисует страницу, а состояние книги — где читатель, что в
/// оглавлении, что нашлось — живёт в [ReaderController] и [DocumentSearch]
/// и ничего про виджеты не знает.
class ReaderScreen extends StatefulWidget {
  /// Создаёт экран чтения.
  const ReaderScreen({required this.book, required this.services, super.key});

  /// Книга.
  final Book book;

  /// Службы приложения.
  final AppServices services;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final PdfViewerController _viewer = PdfViewerController();
  ReaderController? _controller;
  DocumentSearch? _search;
  DocumentOpenException? _failure;
  bool _loading = true;
  PageFlow _flow = PageFlow.continuous;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // Свернули приложение — записываем место немедленно: система вправе
    // убить процесс сразу после этого, и переспросить будет некого.
    _lifecycle = AppLifecycleListener(
      onInactive: () => unawaited(_controller?.flush()),
      onDetach: () => unawaited(_controller?.flush()),
    );
    unawaited(_open());
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _search?.dispose();
    final ReaderController? controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(controller.close().then((_) => controller.dispose()));
    }
    super.dispose();
  }

  Future<void> _open({String? password}) async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final ReaderController controller = await ReaderController.open(
        book: widget.book,
        opener: widget.services.opener,
        reading: widget.services.data.reading,
        password: password,
      );
      await widget.services.data.library.markOpened(
        widget.book.id,
        DateTime.now(),
      );
      if (!mounted) {
        await controller.close();
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _search = DocumentSearch(document: controller.document);
        _loading = false;
      });
    } on DocumentOpenException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _failure = error;
        _loading = false;
      });
    }
  }

  Future<void> _goToPage(int page) async {
    if (!_viewer.isReady) {
      return;
    }
    await _viewer.goToPage(pageNumber: page);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(key: Key('reader-loading')),
        ),
      );
    }
    final DocumentOpenException? failure = _failure;
    if (failure != null) {
      return _FailureScreen(
        failure: failure,
        onPassword: (String password) => unawaited(_open(password: password)),
      );
    }

    final ReaderController controller = _controller!;
    return ReaderScaffold(
      controller: controller,
      search: _search!,
      onGoToPage: _goToPage,
      extraActions: <Widget>[
        IconButton(
          key: const Key('reader-flow-button'),
          icon: Icon(
            _flow == PageFlow.continuous ? Icons.swap_vert : Icons.swap_horiz,
          ),
          tooltip: _flow == PageFlow.continuous
              ? 'Листать постранично'
              : 'Листать лентой',
          onPressed: () => setState(() {
            _flow = _flow == PageFlow.continuous
                ? PageFlow.paged
                : PageFlow.continuous;
          }),
        ),
      ],
      viewerBuilder: (BuildContext context, VoidCallback onTap) {
        return PdfViewer.file(
          widget.book.filePath,
          controller: _viewer,
          initialPageNumber: controller.initialPage,
          params: PdfViewerParams(
            // Фон под страницей — цвет темы, а не белый: белые поля
            // вокруг страницы ночью бьют в глаза сильнее самой страницы.
            backgroundColor: Theme.of(context).colorScheme.surface,
            margin: _flow == PageFlow.paged ? 0 : 6,
            layoutPages: _flow == PageFlow.paged ? _layoutSideBySide : null,
            pageDropShadow: null,
            enableKeyboardNavigation: true,
            onPageChanged: (int? page) {
              if (page != null) {
                controller.onPageChanged(page);
              }
            },
            onGeneralTap:
                (
                  BuildContext context,
                  PdfViewerController viewerController,
                  PdfViewerGeneralTapHandlerDetails details,
                ) {
                  // Панели переключает только простое нажатие. Двойное
                  // нажатие — это масштаб, долгое — выделение текста;
                  // отбирать их у просмотрщика нельзя.
                  if (details.type != PdfViewerGeneralTapType.tap ||
                      details.tapOn == PdfViewerPart.selectedText) {
                    return false;
                  }
                  onTap();
                  return true;
                },
          ),
        );
      },
    );
  }
}

/// Раскладка «страница за страницей»: страницы стоят в ряд.
///
/// Каждая страница получает столбец шириной с самую широкую страницу
/// книги, поэтому при листании узкие страницы не прыгают влево-вправо.
/// Прилипание к границам страниц появится в S4 вместе с режимами
/// отображения — там для него уже будет вся геометрия.
PdfPageLayout _layoutSideBySide(List<PdfPage> pages, PdfViewerParams params) {
  double widest = 0;
  double tallest = 0;
  for (final PdfPage page in pages) {
    widest = math.max(widest, page.width);
    tallest = math.max(tallest, page.height);
  }
  final double column = widest + params.margin;
  final List<Rect> layouts = <Rect>[];
  double x = params.margin;
  for (final PdfPage page in pages) {
    layouts.add(
      Rect.fromLTWH(
        x + (widest - page.width) / 2,
        params.margin + (tallest - page.height) / 2,
        page.width,
        page.height,
      ),
    );
    x += column;
  }
  return PdfPageLayout(
    pageLayouts: layouts,
    documentSize: Size(x, tallest + params.margin * 2),
  );
}

/// Экран «книга не открылась».
///
/// Причина названа своими словами, а не кодом ошибки: человеку надо
/// понять, что делать дальше, а не что сломалось внутри.
class _FailureScreen extends StatefulWidget {
  const _FailureScreen({required this.failure, required this.onPassword});

  final DocumentOpenException failure;
  final void Function(String password) onPassword;

  @override
  State<_FailureScreen> createState() => _FailureScreenState();
}

class _FailureScreenState extends State<_FailureScreen> {
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DocumentProblem problem = widget.failure.problem;
    final bool needsPassword =
        problem == DocumentProblem.passwordRequired ||
        problem == DocumentProblem.wrongPassword;

    return Scaffold(
      appBar: AppBar(title: const Text('Книга не открылась')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Icon(
              needsPassword ? Icons.lock_outline : Icons.report_gmailerrorred,
              size: 56,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(height: 16),
            Text(
              describeDocumentProblem(problem),
              key: const Key('reader-failure-message'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (needsPassword) ...<Widget>[
              const SizedBox(height: 24),
              TextField(
                key: const Key('reader-password-field'),
                controller: _password,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Пароль',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: widget.onPassword,
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('reader-password-submit'),
                onPressed: () => widget.onPassword(_password.text),
                child: const Text('Открыть'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Человеческое объяснение того, почему книга не открылась.
String describeDocumentProblem(DocumentProblem problem) {
  switch (problem) {
    case DocumentProblem.missing:
      return 'Файла больше нет по прежнему пути. Возможно, его перенесли '
          'или удалили — выберите книгу заново.';
    case DocumentProblem.empty:
      return 'Файл пустой: в нём ноль байт. Скорее всего, он не докачался.';
    case DocumentProblem.damaged:
      return 'Файл повреждён и не читается. Это не всегда видно по имени: '
          'бывает, что скачивание оборвалось на середине.';
    case DocumentProblem.passwordRequired:
      return 'Книга защищена паролем. Введите его, чтобы открыть.';
    case DocumentProblem.wrongPassword:
      return 'Пароль не подошёл. Попробуйте ещё раз.';
    case DocumentProblem.unknown:
      return 'Книгу не удалось открыть. Если файл открывается в других '
          'программах, расскажите об этом в issue — так ошибка починится.';
  }
}
