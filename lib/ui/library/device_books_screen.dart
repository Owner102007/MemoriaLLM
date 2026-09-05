import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_services.dart';
import '../../application/library/book_importer.dart';
import '../../application/library/device_library.dart';
import '../../domain/library/book.dart';
import '../../domain/library/book_file_picker.dart';
import '../../domain/library/device_files.dart';
import '../../domain/library/device_scan.dart';
import '../../domain/library/shelf.dart';
import '../../domain/library/storage_access.dart';
import 'device_book_card.dart';
import 'storage_permission_view.dart';

/// Экран «Книги на устройстве».
///
/// То, ради чего в S5.1 был пройден «последний рубеж»: кнопка «+» на полке
/// больше не открывает системный диалог, где книгу надо найти самому.
/// Вместо этого приложение показывает **все** PDF устройства — с
/// обложками, поиском и отметками у тех, что уже стоят на полке.
///
/// Разрешения может не быть, и это не тупик: экран честно объясняет, зачем
/// оно, и рядом оставляет прежний путь — выбрать файлы по одному
/// системным диалогом.
class DeviceBooksScreen extends StatefulWidget {
  /// Создаёт экран.
  const DeviceBooksScreen({required this.services, this.categoryId, super.key});

  /// Службы приложения.
  final AppServices services;

  /// Категория, в которую попадут выбранные книги.
  final String? categoryId;

  @override
  State<DeviceBooksScreen> createState() => _DeviceBooksScreenState();
}

class _DeviceBooksScreenState extends State<DeviceBooksScreen>
    with WidgetsBindingObserver {
  /// Сколько разборка отдыхает между порциями.
  ///
  /// Не подряд: разборка обязана уступать читателю и диск, и движок.
  /// Восемь файлов, треть секунды тишины — это несколько сотен книг в
  /// минуту и незаметная нагрузка.
  ///
  /// Пауза — не таймер по кругу, а задержка внутри цикла, который **сам
  /// кончается**, когда разбирать больше нечего. Вечный `Timer.periodic`
  /// стоил бы того, что экран никогда не успокаивается: ни на устройстве,
  /// ни в widget-тесте, где `pumpAndSettle` ждёт именно этого.
  static const Duration _indexPause = Duration(milliseconds: 300);

  StorageAccessState _access = StorageAccessState.denied;
  bool _asked = false;
  bool _ready = false;
  ScanProgress? _progress;
  String _query = '';
  final Set<String> _picked = <String>{};
  final TextEditingController _search = TextEditingController();
  bool _indexing = false;
  StreamSubscription<ScanProgress>? _scan;
  List<DeviceFileRecord> _records = const <DeviceFileRecord>[];
  StreamSubscription<List<DeviceFileRecord>>? _watch;
  List<DeviceBookEntry>? _found;
  Set<String> _shelfHashes = const <String>{};

  DeviceLibrary get _device => widget.services.deviceLibrary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_scan?.cancel());
    unawaited(_watch?.cancel());
    unawaited(_device.stopScan());
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Разрешение могли выдать — или отозвать — в настройках Android, пока
    // приложение висело в фоне. Узнать об этом иначе нельзя: система о
    // таком не сообщает.
    if (state == AppLifecycleState.resumed) {
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    final StorageAccessState access = await _device.accessState();
    if (!mounted) {
      return;
    }
    final bool changed = access != _access;
    setState(() => _access = access);
    if (!access.allowsScan) {
      // Разрешения нет. Список файлов, собранный когда-то раньше,
      // забывается: держать перечень чужих файлов после того, как доступ
      // к ним отобрали, — ровно то, чего мы обещали не делать.
      await _device.forgetDevice();
      if (mounted) {
        setState(() {
          _records = const <DeviceFileRecord>[];
          _found = null;
          _ready = true;
        });
      }
      return;
    }
    if (_ready && !changed) {
      return;
    }
    _ready = true;
    await _loadShelf();
    _watch ??= _device.watchFiles().listen((List<DeviceFileRecord> records) {
      if (!mounted) {
        return;
      }
      setState(() => _records = records);
      unawaited(_indexLoop());
      if (_query.isNotEmpty) {
        unawaited(_runSearch(_query));
      }
    });
    unawaited(_indexLoop());
    await _rescan();
  }

  Future<void> _loadShelf() async {
    final List<Book> books = await widget.services.data.library.books();
    if (!mounted) {
      return;
    }
    setState(() {
      _shelfHashes = <String>{
        for (final Book book in books)
          if (book.fileHash.isNotEmpty) book.fileHash,
      };
    });
  }

  Future<void> _rescan() async {
    await _scan?.cancel();
    _scan = _device.scan().listen((ScanProgress progress) {
      if (!mounted) {
        return;
      }
      setState(() => _progress = progress);
    });
  }

  /// Разборка идёт слоями: сначала метаданные по всем файлам, потом текст.
  ///
  /// Ни одна ступень не ждёт следующую — но и не мешает ей: пока не
  /// разобраны метаданные всей библиотеки, за текст никто не берётся.
  /// Иначе одна тяжёлая книга задержала бы заголовки у сотни лёгких.
  ///
  /// Цикл кончается сам, когда разбирать нечего, и заводится заново, как
  /// только обход принесёт новые файлы.
  Future<void> _indexLoop() async {
    if (_indexing) {
      return;
    }
    _indexing = true;
    try {
      while (mounted) {
        final int meta = await _device.indexBatch(upTo: IndexStage.meta);
        if (meta == 0) {
          final int text = await _device.indexBatch(
            upTo: IndexStage.text,
            limit: 4,
          );
          if (text == 0) {
            return;
          }
        }
        await Future<void>.delayed(_indexPause);
      }
    } finally {
      _indexing = false;
    }
  }

  Future<void> _runSearch(String query) async {
    final List<DeviceBookEntry> found = await _device.find(query);
    if (!mounted || _query != query) {
      return;
    }
    setState(() => _found = found);
  }

  void _onQuery(String query) {
    setState(() => _query = query);
    if (query.trim().isEmpty) {
      setState(() => _found = null);
      return;
    }
    unawaited(_runSearch(query));
  }

  Future<void> _requestAccess() async {
    setState(() => _asked = true);
    await _device.requestAccess();
  }

  /// Прежний путь: выбрать книги по одной системным диалогом.
  ///
  /// Он остаётся на экране всегда, а не только при отказе: способ, к
  /// которому читатель привык за пять сессий, не должен исчезать оттого,
  /// что появился новый.
  Future<void> _pickManually() async {
    final List<PickedFile> files = await widget.services.picker.pickPdfs();
    if (files.isEmpty || !mounted) {
      return;
    }
    await _import(files);
  }

  Future<void> _addPicked(List<DeviceBookEntry> shown) async {
    final List<PickedFile> files = <PickedFile>[
      for (final DeviceBookEntry entry in shown)
        if (_picked.contains(entry.primary.path))
          PickedFile(name: entry.primary.name, path: entry.primary.path),
    ];
    if (files.isEmpty) {
      return;
    }
    await _import(files);
  }

  Future<void> _import(List<PickedFile> files) async {
    final BookImporter importer = BookImporter(
      library: widget.services.data.library,
      storage: widget.services.storage,
      opener: widget.services.opener,
    );
    final ImportReport report = await importer.registerAll(
      files,
      categoryId: widget.categoryId,
    );
    if (!mounted) {
      return;
    }
    setState(_picked.clear);
    await _loadShelf();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_describe(report))));
    // Книги встали на полку — читателю здесь больше делать нечего, и он
    // хочет увидеть результат. Но если экран открыт первым (так бывает
    // только в тесте), возвращаться некуда, и закрывать последний экран
    // нельзя: приложение осталось бы без единого.
    if (report.added.isNotEmpty && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  String _describe(ImportReport report) {
    if (report.added.isEmpty) {
      return 'Не удалось добавить ни одной книги из ${report.total}';
    }
    if (report.isClean) {
      return report.added.length == 1
          ? 'Книга добавлена'
          : 'Добавлено книг: ${report.added.length}';
    }
    return 'Добавлено ${report.added.length} из ${report.total}; '
        'не открылось: ${report.failed.length}';
  }

  @override
  Widget build(BuildContext context) {
    final List<DeviceBookEntry> shown = _entries();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Книги на устройстве'),
        actions: <Widget>[
          IconButton(
            key: const Key('device-pick-files'),
            icon: const Icon(Icons.library_add_outlined),
            tooltip: 'Выбрать файлы вручную',
            onPressed: () => unawaited(_pickManually()),
          ),
        ],
      ),
      body: _body(shown),
      bottomNavigationBar: _picked.isEmpty
          ? null
          : _AddBar(
              count: _picked.length,
              onAdd: () => unawaited(_addPicked(shown)),
            ),
    );
  }

  Widget _body(List<DeviceBookEntry> shown) {
    if (!_access.allowsScan) {
      return StoragePermissionView(
        denied: _asked,
        onRequest: () => unawaited(_requestAccess()),
        onPickManually: () => unawaited(_pickManually()),
      );
    }
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            key: const Key('device-search'),
            controller: _search,
            onChanged: _onQuery,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Название, автор, папка',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        _ProgressLine(progress: _progress, found: shown.length),
        Expanded(child: _grid(shown)),
      ],
    );
  }

  Widget _grid(List<DeviceBookEntry> shown) {
    if (shown.isEmpty) {
      return _EmptyDevice(
        searching: _query.trim().isNotEmpty,
        scanning: !(_progress?.done ?? false),
        onPickManually: () => unawaited(_pickManually()),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = shelfColumnsFor(constraints.maxWidth - 24);
        return GridView.builder(
          key: const Key('device-grid'),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 0.56,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
          ),
          itemCount: shown.length,
          itemBuilder: (BuildContext context, int index) {
            final DeviceBookEntry entry = shown[index];
            return DeviceBookCard(
              entry: entry,
              covers: widget.services.covers,
              selected: _picked.contains(entry.primary.path),
              onShelf: _shelfHashes.contains(entry.fingerprint),
              onTap: () => setState(() {
                if (!_picked.remove(entry.primary.path)) {
                  _picked.add(entry.primary.path);
                }
              }),
            );
          },
        );
      },
    );
  }

  List<DeviceBookEntry> _entries() {
    final List<DeviceBookEntry>? found = _found;
    if (found != null) {
      return found;
    }
    final List<DeviceBookEntry> entries = groupDeviceFiles(_records);
    entries.sort(
      (DeviceBookEntry a, DeviceBookEntry b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return entries;
  }
}

/// Строка о том, как идёт обход.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.progress, required this.found});

  final ScanProgress? progress;
  final int found;

  @override
  Widget build(BuildContext context) {
    final ScanProgress? state = progress;
    if (state == null || state.done) {
      return const SizedBox(height: 4);
    }
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Row(
        children: <Widget>[
          // Намеренно не крутящийся индикатор: бесконечная анимация не
          // даёт кадру успокоиться никогда — ни на устройстве, ни в
          // widget-тесте. Числа, которые растут, говорят о ходе дела
          // больше, чем колесо.
          Icon(
            Icons.travel_explore,
            size: 14,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Смотрим устройство: найдено ${state.found}, '
              'просмотрено папок ${state.visitedDirectories}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Нижняя полоса: сколько отмечено и кнопка добавления.
class _AddBar extends StatelessWidget {
  const _AddBar({required this.count, required this.onAdd});

  final int count;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: <Widget>[
            Expanded(child: Text('Отмечено: $count')),
            FilledButton(
              key: const Key('device-add'),
              onPressed: onAdd,
              child: Text(count == 1 ? 'Добавить книгу' : 'Добавить на полку'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Пустой экран: ничего не нашлось или ещё ищем.
class _EmptyDevice extends StatelessWidget {
  const _EmptyDevice({
    required this.searching,
    required this.scanning,
    required this.onPickManually,
  });

  final bool searching;
  final bool scanning;
  final VoidCallback onPickManually;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String message;
    if (searching) {
      message =
          'По этому запросу ничего не нашлось. Попробуйте другое слово '
          'или часть названия — поиск понимает и опечатки.';
    } else if (scanning) {
      message =
          'Смотрим устройство. Книги появятся по мере того, '
          'как находятся.';
    } else {
      message =
          'PDF на устройстве не нашлось. Книгу всегда можно выбрать '
          'вручную.';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextButton(
              key: const Key('device-pick-empty'),
              onPressed: onPickManually,
              child: const Text('Выбрать файлы'),
            ),
          ],
        ),
      ),
    );
  }
}
