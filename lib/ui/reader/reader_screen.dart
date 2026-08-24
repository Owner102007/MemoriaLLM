import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../application/app_services.dart';
import '../../application/library/book_importer.dart';
import '../../application/reading/document_search.dart';
import '../../application/reading/reader_controller.dart';
import '../../domain/library/book.dart';
import '../../domain/library/book_file_picker.dart';
import '../../domain/reading/fragments.dart';
import '../../domain/reading/reader_document.dart';
import '../../domain/reading/reading.dart';
import '../../domain/settings/app_settings.dart';
import 'crop_editor_screen.dart';
import 'display_mode_buttons.dart';
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

  /// Книга может смениться прямо на этом экране: если файл переехал,
  /// читатель выбирает его заново, и у книги становится новый источник.
  /// Идентификатор при этом прежний — место чтения и цитаты не теряются.
  late Book _book = widget.book;
  ReaderController? _controller;
  DocumentSearch? _search;
  DocumentOpenException? _failure;
  bool _loading = true;
  PageFlow _flow = PageFlow.paged;
  AppLifecycleListener? _lifecycle;
  ScreenOrientation _rotation = ScreenOrientation.portrait;
  bool _zoomLocked = true;
  DisplayArea _area = DisplayArea.unknown;

  /// Можно ли попросить систему повернуть экран.
  ///
  /// На ПК — нельзя: `setPreferredOrientations` там не делает ничего, а
  /// форму окна выбирает человек. Поэтому и кнопки поворота на ПК нет:
  /// кнопка, которая заведомо ничего не сделает, хуже её отсутствия.
  static final bool _canTurn =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

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

  /// Форма области показа приходит из системы и меняется сама: поворот
  /// телефона, изменение размера окна на ПК. Геометрия деления страницы
  /// работает с этими числами, а не с признаком «портрет или альбом», —
  /// иначе на ПК, где ориентации нет вовсе, ей нечего было бы сказать.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Size size = MediaQuery.sizeOf(context);
    _area = DisplayArea(width: size.width, height: size.height);
    _controller?.setDisplayArea(_area, canTurn: _canTurn);
  }

  /// Положение экрана и способ листания — настройки устройства, а не
  /// книги: держать телефон боком читатель привыкает один раз.
  Future<void> _restoreDeviceSettings() async {
    final AppSettingsRepository settings = widget.services.data.settings;
    final String? rotation = await settings.read(SettingsKeys.readingRotation);
    final String? flow = await settings.read(SettingsKeys.pageFlow);
    final String? locked = await settings.read(SettingsKeys.zoomLock);
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
      // Заперто по умолчанию: обычное чтение — это листание, и страница,
      // уехавшая от случайного движения двумя пальцами, читателю ничего
      // не даёт, а вернуть её он не догадается.
      _zoomLocked = locked != 'false';
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
    if (!_canTurn) {
      return;
    }
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

  /// Запирает и отпирает масштаб.
  ///
  /// Настройка устройства, а не книги: привычка держать страницу
  /// запертой не меняется от книги к книге.
  Future<void> _setZoomLocked(bool value) async {
    if (value == _zoomLocked) {
      return;
    }
    setState(() => _zoomLocked = value);
    await widget.services.data.settings.write(
      SettingsKeys.zoomLock,
      value.toString(),
    );
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
  /// Положение экрана выбирает геометрия: на двухколоночной книге
  /// половина — это колонка, и её экран **вертикальный**, а поворот в
  /// альбом сделал бы текст мельче целой страницы. Режим, у которого
  /// выигрыша нет вовсе, не включается — но и не молчит: читателю
  /// говорится, почему страница осталась целой.
  Future<void> _setDisplayMode(PageDisplayMode mode) async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    final DisplayModeOutcome outcome = await controller.setDisplayMode(mode);
    if (outcome == DisplayModeOutcome.noGain) {
      _explainNoGain(mode);
      return;
    }
    // Пока область показа не измерена, поворачивать экран не по чему:
    // поворот вслепую — это ровно та ошибка, от которой уходим.
    final FragmentLayout layout = controller.layout;
    if (layout.isKnown) {
      await _setRotation(layout.orientation);
    }
  }

  /// Говорит, почему деление не включилось.
  void _explainNoGain(PageDisplayMode mode) {
    if (!mounted) {
      return;
    }
    final String fraction = mode == PageDisplayMode.third ? '⅓' : '½';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('reader-mode-no-gain'),
        duration: const Duration(seconds: 3),
        content: Text(
          'На этой странице $fraction не увеличит текст — страница '
          'осталась целой.',
        ),
      ),
    );
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
        book: _book,
        opener: widget.services.opener,
        reading: widget.services.data.reading,
        password: password,
      );
      await widget.services.data.library.markOpened(_book.id, DateTime.now());
      if (!mounted) {
        await controller.close();
        controller.dispose();
        return;
      }
      controller.addListener(_onControllerChanged);
      controller.setDisplayArea(_area, canTurn: _canTurn);
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

  /// Привязывает книгу к заново выбранному файлу.
  ///
  /// Файл переименовали, унесли карту памяти, отозвали разрешение на
  /// ссылку — книга при этом никуда не делась: место чтения, цитаты и
  /// заметки принадлежат ей, а не файлу. Поэтому «файл недоступен» — это
  /// не тупик с кнопкой «назад», а предложение показать файл заново.
  Future<void> _relink() async {
    final PickedFile? file = await widget.services.picker.pickPdf();
    if (file == null || !mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _failure = null;
    });
    final BookImporter importer = BookImporter(
      library: widget.services.data.library,
      storage: widget.services.storage,
      opener: widget.services.opener,
    );
    try {
      _book = await importer.relink(_book, file);
    } on DocumentOpenException catch (error) {
      if (mounted) {
        setState(() {
          _failure = error;
          _loading = false;
        });
      }
      return;
    }
    if (mounted) {
      await _open();
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
  /// Зоны всегда слева и справа, в любом режиме и в любом положении
  /// экрана. Пробовали привязать их к направлению деления — читатель
  /// каждый раз вспоминал, куда нажимать в этом режиме. Привычка «вправо
  /// значит дальше» сильнее любой логики раскладки.
  void _onTap(Offset position, Size size, VoidCallback toggleChrome) {
    final ReaderController? controller = _controller;
    if (controller == null || _flow != PageFlow.paged) {
      toggleChrome();
      return;
    }
    final double extent = size.width;
    if (extent <= 0) {
      toggleChrome();
      return;
    }
    final double share = position.dx / extent;
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
        onRelink: () => unawaited(_relink()),
      );
    }

    final ReaderController controller = _controller!;
    return ReaderScaffold(
      controller: controller,
      search: _search!,
      onGoToPage: _goToPage,
      extraActions: <Widget>[
        // Деление страницы стоит там, где им пользуются, — на странице, а
        // не в панели настроек: это способ читать, а не настройка.
        DisplayModeButtons(
          mode: controller.settings.displayMode,
          onMode: (PageDisplayMode mode) => unawaited(_setDisplayMode(mode)),
          // Дробь, которая на этой книге не увеличит текст, показана
          // погасшей: обещать увеличение и не дать его — хуже, чем
          // честно сказать заранее.
          gainless: <PageDisplayMode>{
            for (final PageDisplayMode mode in <PageDisplayMode>[
              PageDisplayMode.half,
              PageDisplayMode.third,
            ])
              if (!controller.layoutFor(mode).isWorthwhile) mode,
          },
        ),
        IconButton(
          key: const Key('reader-zoom-lock-button'),
          icon: Icon(_zoomLocked ? Icons.lock_outline : Icons.lock_open),
          tooltip: _zoomLocked
              ? 'Разрешить двигать и масштабировать страницу'
              : 'Запереть масштаб',
          visualDensity: VisualDensity.compact,
          onPressed: () => unawaited(_setZoomLocked(!_zoomLocked)),
        ),
        // Поворот есть только там, где он что-то делает. На ПК форму окна
        // выбирает человек, а `setPreferredOrientations` не делает ничего:
        // кнопка-обманка хуже её отсутствия.
        if (_canTurn)
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
            visualDensity: VisualDensity.compact,
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
          visualDensity: VisualDensity.compact,
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

  /// Чтение по страницам: жёсткая раскладка, страница целиком.
  ///
  /// Лист кладётся так, что читаемая часть занимает экран, а остальная
  /// страница гаснет вокруг неё. Масштаб один и тот же на каждой странице
  /// книги — пока замок заперт. Отперев его, читатель двигает и
  /// масштабирует страницу как в обычном просмотрщике, и она остаётся в
  /// том виде, в каком он её оставил.
  Widget _buildSheet(
    BuildContext context,
    ReaderController controller,
    VoidCallback onTap,
  ) {
    final Color background = Theme.of(context).colorScheme.surface;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints limits) {
        final Size size = Size(limits.maxWidth, limits.maxHeight);
        // Рисуем тем же документом, который уже открыл контроллер:
        // второе открытие той же книги стоило вдвое больше памяти, а на
        // большой книге отдавало страницы не сразу — и вместо содержимого
        // читатель видел пустой экран.
        final Object? engine = controller.document.engineDocument;
        final PdfDocument? document = engine is PdfDocument ? engine : null;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (TapUpDetails details) =>
              _onTap(details.localPosition, size, onTap),
          child: document == null
              ? ColoredBox(color: background, child: const SizedBox.expand())
              : ReaderSheet(
                  document: document,
                  pages: isSpreadMode(controller.settings.displayMode)
                      ? spreadPages(controller.page, controller.pageCount)
                      : <int>[controller.page],
                  fragment: controller.fragmentBox,
                  background: background,
                  page: controller.page,
                  pageCount: controller.pageCount,
                  locked: _zoomLocked,
                  stripFit: controller.settings.stripFit,
                  dim: controller.settings.dimOutside,
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
    // Тем же документом, который уже открыл контроллер. Прежде лента
    // открывала книгу по пути во второй раз — но у документа Android
    // пути нет вовсе, а второе открытие большой книги и без того стоило
    // вдвое больше памяти. `autoDispose: false` потому, что закрывает
    // документ контроллер: он его и открыл.
    final Object? engine = controller.document.engineDocument;
    final PdfDocument? document = engine is PdfDocument ? engine : null;
    if (document == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: const SizedBox.expand(),
      );
    }
    return PdfViewer(
      PdfDocumentRefDirect(document, autoDispose: false),
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
  const _FailureScreen({
    required this.failure,
    required this.onPassword,
    required this.onRelink,
  });

  final DocumentOpenException failure;
  final void Function(String password) onPassword;
  final VoidCallback onRelink;

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
    // Файл потерялся — значит, его можно показать заново. Всё остальное
    // (повреждён, пустой) перевыбором того же файла не лечится.
    final bool canRelink = problem == DocumentProblem.missing;

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
            if (canRelink) ...<Widget>[
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('reader-relink'),
                onPressed: widget.onRelink,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Выбрать файл заново'),
              ),
              const SizedBox(height: 12),
              Text(
                'Место чтения, цитаты и заметки останутся на месте: они '
                'принадлежат книге, а не файлу.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

