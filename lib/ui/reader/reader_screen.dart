import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../application/app_services.dart';
import '../../application/reading/document_search.dart';
import '../../application/reading/reader_controller.dart';
import '../../domain/library/book.dart';
import '../../domain/reading/fragments.dart';
import '../../domain/reading/reader_document.dart';
import '../../domain/reading/reading.dart';
import 'crop_editor_screen.dart';
import 'reader_scaffold.dart';
import 'reader_settings_sheet.dart';
import 'reading_filter_layer.dart';

/// Как листается книга.
enum PageFlow {
  /// Непрерывная лента страниц сверху вниз.
  continuous,

  /// Страница за страницей вбок — с читательской рамкой.
  paged,
}

/// Экран чтения.
///
/// Единственное место, где встречаются `pdfrx` и всё остальное:
/// просмотрщик рисует страницу, а состояние книги — где читатель, какая
/// у страницы рамка, какой фильтр — живёт в [ReaderController] и ничего
/// про виджеты не знает.
///
/// **Рамка работает в постраничном листании.** Там читатель ходит по
/// фрагментам, и каждый фрагмент занимает весь экран. Непрерывная лента
/// оставлена как есть: это другой способ читать, и навязывать ему рамку
/// значит сломать оба.
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
  /// Доля ширины экрана по краям, отданная переходу по фрагментам.
  static const double _tapZone = 0.3;

  final PdfViewerController _viewer = PdfViewerController();
  ReaderController? _controller;
  DocumentSearch? _search;
  DocumentOpenException? _failure;
  bool _loading = true;
  PageFlow _flow = PageFlow.paged;
  AppLifecycleListener? _lifecycle;
  ScreenOrientation _orientation = ScreenOrientation.portrait;
  CropBox? _appliedBox;
  int _appliedPage = 0;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    // Чтение во весь экран: системные панели уходят и возвращаются по
    // жесту от края. Страница — это вся поверхность, а не окно в ней.
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
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
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    _lifecycle?.dispose();
    _search?.dispose();
    final ReaderController? controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onFrameChanged);
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
        orientation: _orientation,
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
      controller.addListener(_onFrameChanged);
      unawaited(controller.loadFrame());
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

  /// Рамка или страница изменились — надо привести экран в соответствие.
  ///
  /// Проверка на «изменилось ли» обязательна: контроллер уведомляет и о
  /// том, что дочиталось оглавление, а перескакивать при этом на начало
  /// фрагмента значило бы дёргать страницу под руками у читателя.
  void _onFrameChanged() {
    final ReaderController? controller = _controller;
    if (controller == null || _flow != PageFlow.paged) {
      return;
    }
    final CropBox box = controller.fragmentBox;
    if (box == _appliedBox && controller.page == _appliedPage) {
      return;
    }
    unawaited(_applyFrame());
  }

  Future<void> _applyFrame({
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    final ReaderController? controller = _controller;
    if (controller == null || _applying || !_viewer.isReady) {
      return;
    }
    if (_flow != PageFlow.paged) {
      return;
    }
    _applying = true;
    controller.beginViewerNavigation();
    try {
      final CropBox box = controller.fragmentBox;
      final int page = controller.page;
      _appliedBox = box;
      _appliedPage = page;
      if (controller.settings.displayMode == PageDisplayMode.spread) {
        await _goToSpread(page, box, duration);
      } else {
        await _viewer.goToRectInsidePage(
          pageNumber: page,
          rect: _pdfRect(page, box),
          anchor: PdfPageAnchor.all,
          duration: duration,
        );
      }
    } on Object {
      // Просмотрщик мог не успеть разложить страницы. Следующее движение
      // читателя повторит попытку — ронять чтение из-за этого нельзя.
      _appliedBox = null;
    } finally {
      controller.endViewerNavigation();
      _applying = false;
    }
  }

  /// Разворот: две соседние страницы целиком в поле зрения.
  ///
  /// В постраничной раскладке страницы уже стоят в ряд, поэтому разворот —
  /// это просто прямоугольник, накрывающий обе.
  Future<void> _goToSpread(int page, CropBox box, Duration duration) async {
    final List<int> pages = spreadPages(page, _viewer.pageCount);
    Rect area = _viewer.calcRectForRectInsidePage(
      pageNumber: pages.first,
      rect: _pdfRect(pages.first, box),
    );
    for (final int other in pages.skip(1)) {
      area = area.expandToInclude(
        _viewer.calcRectForRectInsidePage(
          pageNumber: other,
          rect: _pdfRect(other, box),
        ),
      );
    }
    await _viewer.goToArea(
      rect: area,
      anchor: PdfPageAnchor.all,
      duration: duration,
    );
  }

  /// Переводит рамку из долей отображаемой страницы в координаты PDF.
  PdfRect _pdfRect(int pageNumber, CropBox box) {
    final PdfPage page = _viewer.pages[pageNumber - 1];
    final Rect rect = Rect.fromLTRB(
      box.left * page.width,
      box.top * page.height,
      box.right * page.width,
      box.bottom * page.height,
    );
    return rect.toPdfRect(page: page);
  }

  Future<void> _goToPage(int page) async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    await controller.goToPage(page);
    if (_flow == PageFlow.paged) {
      await _applyFrame();
      return;
    }
    if (_viewer.isReady) {
      await _viewer.goToPage(pageNumber: page);
    }
  }

  void _onTap(Offset position, Size size, VoidCallback toggleChrome) {
    final ReaderController? controller = _controller;
    if (controller == null || _flow != PageFlow.paged || size.width <= 0) {
      toggleChrome();
      return;
    }
    final double share = position.dx / size.width;
    if (share < _tapZone) {
      unawaited(controller.previousFragment());
      return;
    }
    if (share > 1 - _tapZone) {
      unawaited(controller.nextFragment());
      return;
    }
    toggleChrome();
  }

  Future<void> _openSettings() async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return ReaderSettingsSheet(
          controller: controller,
          onEditCrop: () {
            Navigator.of(context).pop();
            unawaited(_editCrop());
          },
        );
      },
    );
  }

  Future<void> _editCrop() async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    final CropBox? box = await Navigator.of(context).push<CropBox>(
      MaterialPageRoute<CropBox>(
        builder: (BuildContext context) => CropEditorScreen(
          document: controller.document,
          pageNumber: controller.page,
          initial: controller.contentBox,
        ),
      ),
    );
    if (box != null) {
      await controller.setManualCrop(box);
    }
  }

  void _syncOrientation(BuildContext context) {
    final ScreenOrientation now =
        MediaQuery.orientationOf(context) == Orientation.landscape
        ? ScreenOrientation.landscape
        : ScreenOrientation.portrait;
    if (now == _orientation) {
      return;
    }
    _orientation = now;
    unawaited(_controller?.setOrientation(now));
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

    _syncOrientation(context);
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
              ? 'Листать постранично, с рамкой'
              : 'Листать лентой',
          onPressed: () {
            setState(() {
              _flow = _flow == PageFlow.continuous
                  ? PageFlow.paged
                  : PageFlow.continuous;
              _appliedBox = null;
            });
            if (_flow == PageFlow.paged) {
              unawaited(_applyFrame());
            }
          },
        ),
        IconButton(
          key: const Key('reader-settings-button'),
          icon: const Icon(Icons.tune),
          tooltip: 'Рамка и светофильтр',
          onPressed: () => unawaited(_openSettings()),
        ),
      ],
      viewerBuilder: (BuildContext context, VoidCallback onTap) {
        return AnimatedBuilder(
          animation: controller,
          builder: (BuildContext context, Widget? child) {
            return ReadingFilterLayer(filter: controller.filter, child: child!);
          },
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints limits) {
              final Size size = Size(limits.maxWidth, limits.maxHeight);
              return PdfViewer.file(
                widget.book.filePath,
                controller: _viewer,
                initialPageNumber: controller.initialPage,
                params: PdfViewerParams(
                  // Фон под страницей — цвет темы, а не белый: белые поля
                  // вокруг страницы ночью бьют в глаза сильнее самой
                  // страницы.
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  margin: _flow == PageFlow.paged ? 32 : 6,
                  layoutPages: _flow == PageFlow.paged
                      ? _layoutSideBySide
                      : null,
                  pageDropShadow: null,
                  enableKeyboardNavigation: true,
                  // Обрезанный фрагмент занимает весь экран, а значит,
                  // требует куда большего увеличения, чем страница
                  // целиком. Восьмикратного потолка по умолчанию на трети
                  // страницы уже не хватает.
                  sizeDelegateProvider:
                      const PdfViewerSizeDelegateProviderLegacy(maxScale: 24),
                  onViewerReady:
                      (
                        PdfDocument document,
                        PdfViewerController viewerController,
                      ) {
                        unawaited(_applyFrame(duration: Duration.zero));
                      },
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
                        // Панели переключает только простое нажатие.
                        // Двойное нажатие — это масштаб, долгое —
                        // выделение текста; отбирать их у просмотрщика
                        // нельзя.
                        if (details.type != PdfViewerGeneralTapType.tap ||
                            details.tapOn == PdfViewerPart.selectedText) {
                          return false;
                        }
                        _onTap(details.localPosition, size, onTap);
                        return true;
                      },
                ),
              );
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
/// Соседние страницы разделены полем: при показе фрагмента экран заполнен
/// не целиком, и в остаток должен попадать фон, а не край чужой страницы.
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
