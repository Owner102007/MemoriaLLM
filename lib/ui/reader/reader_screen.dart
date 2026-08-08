import 'dart:async';

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
import '../../domain/settings/app_settings.dart';
import 'crop_editor_screen.dart';
import 'reader_scaffold.dart';
import 'reader_settings_sheet.dart';
import 'reader_sheet.dart';
import 'reading_filter_layer.dart';

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
  ScreenOrientation _rotation = ScreenOrientation.portrait;

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
    unawaited(_restoreDeviceSettings());
    unawaited(_open());
  }

  /// Положение экрана и способ листания — настройки устройства, а не
  /// книги: держать телефон боком читатель привыкает один раз.
  Future<void> _restoreDeviceSettings() async {
    final AppSettingsRepository settings = widget.services.data.settings;
    final String? rotation = await settings.read(SettingsKeys.readingRotation);
    final String? flow = await settings.read(SettingsKeys.pageFlow);
    if (!mounted) {
      return;
    }
    setState(() {
      _rotation = rotation == ScreenOrientation.landscape.name
          ? ScreenOrientation.landscape
          : ScreenOrientation.portrait;
      _flow = flow == PageFlow.continuous.name
          ? PageFlow.continuous
          : PageFlow.paged;
    });
    await _applyRotation();
  }

  /// Поворачивает экран сам, не спрашивая систему.
  ///
  /// Автоповорот у многих выключен насовсем, а без поворота деление
  /// страницы на полосы не даёт ровным счётом ничего: полоса той же
  /// ширины вписывается в вертикальный экран тем же масштабом, что и
  /// целая страница. Принудительная ориентация сильнее пользовательской
  /// блокировки — именно так поступают видеоплееры.
  Future<void> _applyRotation() async {
    await SystemChrome.setPreferredOrientations(
      _rotation == ScreenOrientation.landscape
          ? const <DeviceOrientation>[
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const <DeviceOrientation>[
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
            ],
    );
  }

  Future<void> _setRotation(ScreenOrientation rotation) async {
    if (rotation == _rotation) {
      return;
    }
    setState(() => _rotation = rotation);
    await widget.services.data.settings.write(
      SettingsKeys.readingRotation,
      rotation.name,
    );
    await _applyRotation();
  }

  Future<void> _setFlow(PageFlow flow) async {
    if (flow == _flow) {
      return;
    }
    setState(() => _flow = flow);
    await widget.services.data.settings.write(SettingsKeys.pageFlow, flow.name);
  }

  /// Смена режима отображения заодно поворачивает чтение.
  ///
  /// Без поворота режимы бессмысленны, и объяснять это читателю текстом
  /// вместо действия — плохой размен.
  Future<void> _setDisplayMode(PageDisplayMode mode) async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    await controller.setDisplayMode(mode);
    await _setRotation(controller.preferredOrientation);
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    _lifecycle?.dispose();
    _search?.dispose();
    final ReaderController? controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onControllerChanged);
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
      controller.addListener(_onControllerChanged);
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

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _goToPage(int page) async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    await controller.goToPage(page);
    if (_flow == PageFlow.continuous && _viewer.isReady) {
      await _viewer.goToPage(pageNumber: page);
    }
  }

  /// Нажатие по странице: переход к соседнему фрагменту или панели.
  ///
  /// Зоны следуют направлению деления: полосы идут сверху вниз — значит
  /// и нажимать надо сверху и снизу, там, где лежит следующий кусок
  /// текста. Колонки, целые страницы и развороты листаются привычно,
  /// слева и справа.
  void _onTap(Offset position, Size size, VoidCallback toggleChrome) {
    final ReaderController? controller = _controller;
    if (controller == null || _flow != PageFlow.paged) {
      toggleChrome();
      return;
    }
    final bool vertical = controller.fragmentFlow == FragmentFlow.vertical;
    final double extent = vertical ? size.height : size.width;
    if (extent <= 0) {
      toggleChrome();
      return;
    }
    final double share = (vertical ? position.dy : position.dx) / extent;
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
          flow: _flow,
          onFlow: (PageFlow value) => unawaited(_setFlow(value)),
          onDisplayMode: (PageDisplayMode mode) =>
              unawaited(_setDisplayMode(mode)),
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
          key: const Key('reader-rotation-button'),
          icon: Icon(
            _rotation == ScreenOrientation.landscape
                ? Icons.stay_current_landscape
                : Icons.stay_current_portrait,
          ),
          tooltip: _rotation == ScreenOrientation.landscape
              ? 'Читать вертикально'
              : 'Читать горизонтально',
          onPressed: () => unawaited(
            _setRotation(
              _rotation == ScreenOrientation.landscape
                  ? ScreenOrientation.portrait
                  : ScreenOrientation.landscape,
            ),
          ),
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
            return ReadingFilterLayer(
              filter: controller.filter,
              // Лента строится один раз и передаётся мимо перестроений:
              // пересоздавать просмотрщик на каждое уведомление значило бы
              // терять место прокрутки под руками у читателя.
              child: child ?? _buildSheet(context, controller, onTap),
            );
          },
          child: _flow == PageFlow.continuous
              ? _buildRibbon(context, controller, onTap)
              : null,
        );
      },
    );
  }

  /// Чтение по страницам: жёсткая раскладка, никакого зума.
  ///
  /// Лист вписывается в экран целиком, масштаб один и тот же на каждой
  /// странице. Читатель не может ни увести страницу пальцем, ни поймать
  /// случайный масштаб — а именно этого от читалки и ждут.
  Widget _buildSheet(
    BuildContext context,
    ReaderController controller,
    VoidCallback onTap,
  ) {
    final Color background = Theme.of(context).colorScheme.surface;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints limits) {
        final Size size = Size(limits.maxWidth, limits.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (TapUpDetails details) =>
              _onTap(details.localPosition, size, onTap),
          child: PdfDocumentViewBuilder.file(
            widget.book.filePath,
            builder: (BuildContext context, PdfDocument? document) {
              if (document == null) {
                return ColoredBox(
                  color: background,
                  child: const SizedBox.expand(),
                );
              }
              return ReaderSheet(
                document: document,
                pages: isSpreadMode(controller.settings.displayMode)
                    ? spreadPages(controller.page, document.pages.length)
                    : <int>[controller.page],
                fragment: controller.fragmentBox,
                background: background,
              );
            },
          ),
        );
      },
    );
  }

  /// Непрерывная лента: свободное чтение с зумом и прокруткой.
  ///
  /// Здесь читатель сам решает, что и как разглядывать, поэтому режимы
  /// отображения в ленте не действуют — это другой способ читать.
  Widget _buildRibbon(
    BuildContext context,
    ReaderController controller,
    VoidCallback onTap,
  ) {
    return PdfViewer.file(
      widget.book.filePath,
      controller: _viewer,
      initialPageNumber: controller.initialPage,
      params: PdfViewerParams(
        // Фон под страницей — цвет темы, а не белый: белые поля вокруг
        // страницы ночью бьют в глаза сильнее самой страницы.
        backgroundColor: Theme.of(context).colorScheme.surface,
        margin: 6,
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
              // Панели переключает только простое нажатие. Двойное — это
              // масштаб, долгое — выделение текста; отбирать их у
              // просмотрщика нельзя.
              if (details.type != PdfViewerGeneralTapType.tap ||
                  details.tapOn == PdfViewerPart.selectedText) {
                return false;
              }
              onTap();
              return true;
            },
      ),
    );
  }
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
