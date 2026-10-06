import 'dart:async';

import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../application/theme/theme_controller.dart';
import '../domain/library/shelf.dart';
import '../domain/navigation/sections.dart';
import '../domain/settings/app_settings.dart';
import '../domain/theme/app_palette.dart';
import '../sno/flags.dart';
import '../sno/recording/event.dart';
import '../sno/recording/logged_settings.dart';
import '../sno/recording/recording_overlay.dart';
import '../sno/recording/session.dart';
import '../sno/testing_screen.dart';
import 'galaxy/galaxy_screen.dart';
import 'library/device_books_screen.dart';
import 'library/library_screen.dart';
import 'settings/settings_screen.dart';
import 'theme/palette_scope.dart';
import 'theme/theme_builder.dart';

/// Корневой виджет приложения.
class MemoriaApp extends StatefulWidget {
  /// Создаёт приложение с готовым контроллером тем и службами.
  const MemoriaApp({
    required this.themeController,
    required this.services,
    super.key,
  });

  /// Источник текущей темы.
  final ThemeController themeController;

  /// Службы приложения: данные, движок PDF, диалог выбора файла.
  final AppServices services;

  @override
  State<MemoriaApp> createState() => _MemoriaAppState();
}

class _MemoriaAppState extends State<MemoriaApp> {
  /// Навигатор приложения — слою записи: диалог остановки и экран
  /// завершения сессии открываются поверх любого экрана (SNO-F-REC-01).
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeId>(
      valueListenable: widget.themeController,
      builder: (BuildContext context, AppThemeId themeId, Widget? child) {
        final AppPalette palette = appPalettes[themeId]!;
        return MaterialApp(
          title: appNameFor(Sno.branch),
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigator,
          theme: buildTheme(palette),
          // Палитра нужна полке целыми числами, а не через `ColorScheme`:
          // по ним считается цвет категории и проверяется его контраст.
          builder: (BuildContext context, Widget? page) => AppPaletteScope(
            palette: palette,
            child: _underRecording(page ?? const SizedBox.shrink()),
          ),
          home: HomeShell(
            themeController: widget.themeController,
            services: widget.services,
          ),
        );
      },
    );
  }

  /// Кладёт поверх приложения слой записи, если запись в сборке есть.
  ///
  /// Слой стоит выше навигатора: точка записи видна на каждом экране и
  /// лежит поверх светофильтра — тот накрывает только картинку
  /// страницы (SNO-SCR-02).
  Widget _underRecording(Widget page) {
    final RecordingSession? session = widget.services.recording;
    if (session == null) {
      return page;
    }
    return RecordingOverlay(
      session: session,
      navigator: _navigator,
      records: widget.services.records,
      child: page,
    );
  }
}

/// Оболочка приложения: разделы и навигация между ними (F-APP-02).
///
/// Разделов три — «Полка», «Устройство», «Настройки». На телефоне и в
/// узком окне навигация стоит у нижнего края, в окне от
/// [kTopNavWidth] точек — полосой наверху; где ей стоять, решает
/// `domain/navigation/sections.dart`.
///
/// В сборке ветви СНО2026 разделы другие (SNO-F-CFG-02, SNO-F-CFG-03):
/// «Устройства» нет — книг на диске ветвь не ищет, — а на его месте
/// стоит «Тестирование»: там, и только там, она ищет архив с
/// литературой и просит для этого доступ к файлам (SNO-F-LIT-03).
/// Какие разделы есть, решают флаги сборки (`sno/flags.dart`): это
/// константы, и в основном приложении раздела «Тестирование» нет вовсе.
/// В сборке ветви II между «Полкой» и «Тестированием» стоит «Галактика»
/// (SNO-F-MAP-01) — книги полки картой.
///
/// Каждый раздел **остаётся там, где его оставили**: все они живут в
/// одном `IndexedStack`, и переключение раздела не сбрасывает ни место
/// прокрутки, ни набранный поиск. «Устройство» при этом строится не при
/// запуске, а при первом заходе: запуск приложения не начинает обход
/// диска и не спрашивает разрешений.
class HomeShell extends StatefulWidget {
  /// Создаёт оболочку.
  const HomeShell({
    required this.themeController,
    required this.services,
    super.key,
  });

  /// Контроллер тем, нужен экрану настроек.
  final ThemeController themeController;

  /// Службы приложения.
  final AppServices services;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Ключ на разделы: навигация переезжает сверху вниз вместе с шириной
  /// окна, и разделы при этом не должны строиться заново.
  final GlobalKey _sections = GlobalKey();

  /// Разделы этой сборки, в порядке навигации.
  final List<AppSection> _visible = sectionsFor(
    scanner: Sno.scanner,
    testing: Sno.recording,
    galaxy: Sno.galaxy,
  );

  AppSection _section = AppSection.shelf;

  /// Заходил ли читатель в «Устройство»: до первого захода раздела нет.
  bool _deviceOpened = false;

  /// Открыта ли книга: пока её читают, обход устройства стоит.
  bool _reading = false;

  /// Категория, чей «+» нажали на полке: туда лягут добавленные книги.
  String? _targetCategory;

  /// Сколько раз устройство сбрасывали к эталону за этот запуск
  /// (SNO-F-CFG-04). Полка держит порядок книг в памяти; новый номер —
  /// новая полка, которая читает настройки заново.
  int _resets = 0;

  /// Сессия записи; `null` — в этой сборке записи нет.
  RecordingSession? get _session => widget.services.recording;

  /// Настройки для экрана настроек: в сборке с записью каждая запись
  /// в них видна журналу (SNO-F-REC-02). Заводятся один раз — экран не
  /// должен получать новое хранилище на каждое перестроение.
  AppSettingsRepository? _settings;

  AppSettingsRepository get _screenSettings {
    final AppSettingsRepository? ready = _settings;
    if (ready != null) {
      return ready;
    }
    final AppSettingsRepository inner = widget.services.data.settings;
    final RecordingSession? session = _session;
    final AppSettingsRepository made = session == null
        ? inner
        : LoggedSettings(inner: inner, log: session);
    _settings = made;
    return made;
  }

  @override
  void initState() {
    super.initState();
    _session?.addListener(_sessionChanged);
    widget.themeController.addListener(_themeChanged);
    _tellScreen();
  }

  @override
  void didUpdateWidget(HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.themeController, widget.themeController)) {
      oldWidget.themeController.removeListener(_themeChanged);
      widget.themeController.addListener(_themeChanged);
    }
    if (!identical(oldWidget.services, widget.services)) {
      _settings = null;
    }
    if (!identical(oldWidget.services.recording, widget.services.recording)) {
      oldWidget.services.recording?.removeListener(_sessionChanged);
      _session?.addListener(_sessionChanged);
      _tellScreen();
    }
  }

  @override
  void dispose() {
    widget.themeController.removeListener(_themeChanged);
    _session?.removeListener(_sessionChanged);
    super.dispose();
  }

  /// Тему сменили: она пишется мимо хранилища экрана настроек, и
  /// журнал узнаёт о ней здесь (SNO-F-REC-02).
  void _themeChanged() {
    _session?.log(
      SnoEventType.settingsChange,
      data: <String, Object?>{
        'key': SettingsKeys.theme,
        'value': widget.themeController.value.name,
      },
    );
  }

  /// Запись началась, остановилась или сессия завершена: замок полки
  /// и «назад» зависят от этого (SNO-F-LIB-02, SNO-F-REC-01).
  void _sessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Говорит записи, на каком экране участник (SNO-F-REC-02): это
  /// подставляется в каждое событие журнала, а смена экрана пишется
  /// событием `nav.screen`.
  void _tellScreen() {
    _session?.screen(_reading ? 'reader' : _section.name);
  }

  void _open(AppSection section) {
    if (section == _section) {
      return;
    }
    setState(() {
      _section = section;
      if (section == AppSection.device) {
        _deviceOpened = true;
      }
    });
    _tellScreen();
  }

  /// Запись началась (SNO-F-REC-01): участник возвращается на полку.
  ///
  /// Сообщение «убрана с полки» с кнопкой «Вернуть» при этом уходит:
  /// под замком расположение книг не меняется ничем (SNO-F-LIB-02).
  void _recordingStarted() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..removeCurrentSnackBar();
    _open(AppSection.shelf);
  }

  /// Полка просит книги устройства: раздел и категория для них.
  void _addBooks(String? categoryId) {
    if (!_visible.contains(AppSection.device)) {
      // В сборке ветви раздела нет (SNO-F-CFG-02), и полка сюда не
      // зовёт; переключиться на раздел, которого нет, нельзя.
      return;
    }
    setState(() {
      _targetCategory = categoryId;
      _section = AppSection.device;
      _deviceOpened = true;
    });
  }

  /// Книгу открыли или закрыли.
  ///
  /// Закрытие может прийти и после того, как оболочку сняли с экрана:
  /// полка сообщает о нём, когда вернулся её экран чтения.
  void _readingChanged(bool reading) {
    // SNO-F-IDX-04: пока книгу читают, проход по полке стоит — движок
    // PDF отдан странице. Сказать ему об этом надо и тогда, когда
    // оболочку уже сняли с экрана: иначе он простоял бы до перезапуска.
    widget.services.shelfReading?.held = reading;
    if (mounted && reading != _reading) {
      setState(() => _reading = reading);
      _tellScreen();
    }
  }

  /// Устройство сбросили к эталонному состоянию (SNO-F-CFG-04).
  ///
  /// Настройки стёрты мимо всего, что держит их в памяти: тема
  /// перечитывается, полка строится заново. Перезапуск не нужен.
  Future<void> _stateReset() async {
    if (!mounted) {
      return;
    }
    // Сообщение «убрана с полки» с кнопкой «Вернуть» относится к полке,
    // которой больше нет: оставшись, оно вернуло бы книгу прежнего
    // тестировщика.
    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..removeCurrentSnackBar();
    await widget.themeController.reload();
    // SNO-F-MAP-01: время в книгах — след читателя, сброс его стёр;
    // счёт в памяти перечитывается, и звёзды на карте снова одинаковы.
    await widget.services.bookTimes?.restore();
    if (mounted) {
      setState(() => _resets++);
    }
  }

  /// Книги встали на полку: читатель хочет увидеть результат.
  void _booksAdded() {
    setState(() {
      _targetCategory = null;
      _section = AppSection.shelf;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool top =
            navPlacementFor(constraints.maxWidth) == NavPlacement.top;
        // Экранная клавиатура поднимает нижнюю панель вместе с собой, и
        // та отнимает место у списка, в котором ищут. Пока набирают —
        // панели нет.
        final bool typing = MediaQuery.viewInsetsOf(context).bottom > 0;
        final AppSection? behind = sectionBehind(_section);
        // SNO-F-REC-01: пока запись идёт, «назад» на полке приложение
        // не закрывает — закрытое приложение оборвало бы запись.
        final bool recording = _session?.recording ?? false;
        return PopScope<Object?>(
          // «Назад» из «Устройства» и «Настроек» ведёт на «Полку», а не
          // закрывает приложение.
          canPop: behind == null && !recording,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop && behind != null) {
              // SNO-F-REC-02: «назад» увело из раздела на полку.
              _session?.log(
                SnoEventType.navBack,
                data: const <String, Object?>{'closes': 'section'},
              );
              _open(behind);
            }
          },
          child: Scaffold(
            body: Column(
              children: <Widget>[
                if (top)
                  _TopNav(
                    key: const Key('nav-top'),
                    sections: _visible,
                    current: _section,
                    onOpen: _open,
                  ),
                // Контекст — из-под `Scaffold`: отступ под клавиатуру он
                // уже учёл, и взять его из контекста оболочки значило бы
                // вернуть разделам отступ, который отдан дважды.
                Expanded(
                  child: Builder(
                    builder: (BuildContext inner) {
                      return _buildSections(inner, top: top);
                    },
                  ),
                ),
              ],
            ),
            bottomNavigationBar: top || typing
                ? null
                : _BottomNav(
                    key: const Key('nav-bottom'),
                    sections: _visible,
                    current: _section,
                    onOpen: _open,
                  ),
          ),
        );
      },
    );
  }

  Widget _buildSections(BuildContext inner, {required bool top}) {
    final Widget sections = IndexedStack(
      key: _sections,
      index: _visible.indexOf(_section),
      children: <Widget>[
        for (final AppSection section in _visible) _buildSection(section),
      ],
    );
    if (!top) {
      return sections;
    }
    // Верхний отступ системы уже занят полосой навигации: шапкам
    // разделов отступать ещё раз незачем.
    return MediaQuery.removePadding(
      context: inner,
      removeTop: true,
      child: sections,
    );
  }

  Widget _buildSection(AppSection section) {
    switch (section) {
      case AppSection.shelf:
        return LibraryScreen(
          key: ValueKey<int>(_resets),
          services: widget.services,
          onAddBooks: _addBooks,
          onReading: _readingChanged,
          // SNO-F-CFG-02: в ветви полка на «Устройство» не ведёт.
          canAddBooks: Sno.scanner,
          // SNO-F-CFG-04: в ветви книги стоят, как их положил архив.
          defaultSort: Sno.literature ? ShelfSort.manual : ShelfSort.recent,
          // SNO-F-LIB-01: поиск по названию — в сборках ветвей.
          titleSearch: Sno.enabled,
          // SNO-F-READ-01: без модели над выделением нет промптов.
          models: Sno.models,
          // SNO-F-LIB-02: пока сессия записи не завершена, полка стоит
          // на месте.
          locked: _session?.locked ?? false,
          // SNO-F-REC-02: журнал записи пишет, когда полка показана.
          visible: _section == AppSection.shelf && !_reading,
        );
      case AppSection.device:
        if (!_deviceOpened) {
          return const SizedBox.shrink();
        }
        return DeviceBooksScreen(
          services: widget.services,
          section: true,
          visible: _section == AppSection.device,
          paused: _reading,
          categoryId: _targetCategory,
          onClearCategory: () => setState(() => _targetCategory = null),
          onAdded: _booksAdded,
        );
      case AppSection.galaxy:
        // SNO-F-MAP-01. Условие — константа сборки: в основное
        // приложение и в ветвь I раздел не попадает.
        if (Sno.galaxy) {
          return GalaxyScreen(
            // Новый номер сброса — новый раздел: карта читается заново,
            // а выбранная книга и приближение прежнего участника уходят.
            key: ValueKey<String>('galaxy-$_resets'),
            services: widget.services,
            visible: _section == AppSection.galaxy && !_reading,
            onReading: _readingChanged,
            // BUG-46: в ветви файл книги заново не выбирают.
            canRelink: Sno.scanner,
            // SNO-F-READ-01: без модели над выделением нет промптов.
            models: Sno.models,
          );
        }
        return const SizedBox.shrink();
      case AppSection.testing:
        // SNO-F-CFG-03. Условие — константа сборки: в основном
        // приложении ветка недостижима, и раздел в него не попадает.
        if (Sno.recording) {
          return TestingScreen(
            services: widget.services,
            flags: Sno.flags,
            visible: _section == AppSection.testing,
            onStateReset: () => unawaited(_stateReset()),
            onRecordingStarted: _recordingStarted,
          );
        }
        return const SizedBox.shrink();
      case AppSection.settings:
        return SettingsScreen(
          themeController: widget.themeController,
          settings: _screenSettings,
        );
    }
  }
}

IconData _iconOf(AppSection section, {required bool selected}) {
  return switch (section) {
    AppSection.shelf => selected ? Icons.menu_book : Icons.menu_book_outlined,
    AppSection.device =>
      selected ? Icons.folder_copy : Icons.folder_copy_outlined,
    AppSection.galaxy =>
      selected ? Icons.auto_awesome : Icons.auto_awesome_outlined,
    AppSection.testing => selected ? Icons.science : Icons.science_outlined,
    AppSection.settings => selected ? Icons.tune : Icons.tune_outlined,
  };
}

/// Ключ кнопки раздела — один и тот же внизу и наверху: тесты и
/// подсказки находят раздел, не зная, где сейчас стоит навигация.
Key _keyOf(AppSection section) {
  return switch (section) {
    AppSection.shelf => const Key('nav-library'),
    AppSection.device => const Key('nav-device'),
    AppSection.galaxy => const Key('nav-galaxy'),
    AppSection.testing => const Key('nav-testing'),
    AppSection.settings => const Key('nav-settings'),
  };
}

/// Навигация у нижнего края: телефон и узкое окно.
class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.sections,
    required this.current,
    required this.onOpen,
    super.key,
  });

  /// Разделы этой сборки, в порядке навигации.
  final List<AppSection> sections;
  final AppSection current;
  final ValueChanged<AppSection> onOpen;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: sections.indexOf(current),
      onDestinationSelected: (int value) => onOpen(sections[value]),
      destinations: <Widget>[
        for (final AppSection section in sections)
          NavigationDestination(
            key: _keyOf(section),
            icon: Icon(_iconOf(section, selected: false)),
            selectedIcon: Icon(_iconOf(section, selected: true)),
            label: sectionTitle(section),
          ),
      ],
    );
  }
}

/// Навигация полосой наверху: широкое окно.
///
/// Разделы стоят слева, настройки — справа, а середина пуста намеренно:
/// это место вкладок с открытыми книгами (F-DESK-01), и навигация не
/// должна его занимать.
class _TopNav extends StatelessWidget {
  const _TopNav({
    required this.sections,
    required this.current,
    required this.onOpen,
    super.key,
  });

  /// Разделы этой сборки, в порядке навигации.
  final List<AppSection> sections;
  final AppSection current;
  final ValueChanged<AppSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 44,
          child: Row(
            children: <Widget>[
              const SizedBox(width: 8),
              for (final AppSection section in sections)
                if (section != AppSection.settings)
                  _TopNavButton(
                    section: section,
                    selected: section == current,
                    onOpen: onOpen,
                  ),
              const Spacer(),
              _TopNavButton(
                section: AppSection.settings,
                selected: current == AppSection.settings,
                onOpen: onOpen,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopNavButton extends StatelessWidget {
  const _TopNavButton({
    required this.section,
    required this.selected,
    required this.onOpen,
  });

  final AppSection section;
  final bool selected;
  final ValueChanged<AppSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppPalette palette = AppPaletteScope.of(context);
    // Выбранный раздел написан основным цветом текста и подчёркнут
    // акцентом; остальные — вторичным. Одним цветом раздел не отмечен:
    // под ночной красной темой оттенки сходятся в один, а черта остаётся.
    final Color colour = Color(selected ? palette.text : palette.textSecondary);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: _keyOf(section),
        onTap: () => onOpen(section),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                _iconOf(section, selected: selected),
                size: 18,
                color: colour,
              ),
              const SizedBox(width: 8),
              Text(
                sectionTitle(section),
                style: theme.textTheme.labelLarge?.copyWith(color: colour),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
