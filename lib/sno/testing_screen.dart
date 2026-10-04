import 'dart:async';

import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../application/build_info.dart';
import '../application/library/book_importer.dart';
import '../domain/library/archive_scan.dart';
import '../domain/library/book.dart';
import '../domain/library/book_file_picker.dart';
import '../domain/library/device_scan.dart';
import '../domain/library/scan_mark.dart';
import '../domain/library/storage_access.dart';
import '../domain/reading/reader_document.dart';
import 'flags.dart';
import 'literature_archive.dart';

/// Сколько знаков идентификатора устройства показывается.
///
/// Шести хватает, чтобы различить устройства одной серии тестов, и их
/// можно прочесть вслух; тот же код встанет в манифест записи.
const int kDeviceCodeLength = 6;

/// Код устройства: первые знаки его идентификатора узла.
String deviceCodeOf(String nodeId) {
  return nodeId.length > kDeviceCodeLength
      ? nodeId.substring(0, kDeviceCodeLength)
      : nodeId;
}

/// Сколько неудач названо в сообщении поимённо.
const int kNamedFailures = 3;

/// Почему файл не встал на полку — словами для экспериментатора.
///
/// Слова свои, а не из `describeDocumentProblem`: тот текст написан для
/// экрана чтения и зовёт ввести пароль, а здесь вводить его негде. И
/// «не PDF» названо прямо: движок отличить чужой файл от битого PDF не
/// умеет, и сказать можно только про оба сразу.
String describeAddFailure(ImportFailure failure) {
  return switch (failure.problem) {
    DocumentProblem.passwordRequired ||
    DocumentProblem.wrongPassword => 'защищён паролем',
    DocumentProblem.damaged => 'не PDF или файл повреждён',
    DocumentProblem.empty => 'файл пустой',
    DocumentProblem.missing => 'до файла не добраться',
    DocumentProblem.unknown => 'не удалось открыть',
    null => failure.reason,
  };
}

/// Книга ли это, судя по имени файла.
bool isBookName(String name) => name.toLowerCase().endsWith('.pdf');

/// Что сказать, когда вместо архива выбрали книги (решение владельца П3
/// от 04.10.2026).
///
/// Свои PDF в сборках для тестирования не добавляются: у всех
/// тестировщиков одна и та же полка, и встаёт она только из архива с
/// литературой. Книга, выбранная вручную, названа — и на полку не
/// попадает.
String describeRefusedBooks(List<String> names) {
  final String listed = names
      .take(kNamedFailures)
      .map((String name) => '«$name»')
      .join(', ');
  final int rest = names.length - kNamedFailures;
  final String all = rest > 0 ? '$listed и ещё $rest' : listed;
  return 'Не добавлено: $all. В сборке для тестирования книги встают '
      'на полку только из архива с литературой.';
}

/// Что сказать экспериментатору после добавления архива (SNO-F-LIT-01).
///
/// Архив распаковывается минуты, и итог обязан отвечать на три вопроса:
/// сколько книг встало, чего на полке нет и почему, и надо ли добавлять
/// архив ещё раз.
String describeArchiveReport(ArchiveReport report) {
  final String? refusal = report.refusal;
  if (refusal != null) {
    return 'Архив не добавлен: $refusal.';
  }
  final List<String> lines = <String>[];
  final int added = report.added.length;
  final int categories = report.categories;
  if (added > 0) {
    lines.add(
      categories > 0
          ? 'Добавлено книг: $added, категорий: $categories.'
          : 'Добавлено книг: $added.',
    );
  }
  if (report.already > 0) {
    lines.add(
      added == 0 && report.already == report.total
          ? 'Все книги архива уже на полке: ${report.already}.'
          : 'Уже стояло на полке: ${report.already}.',
    );
  }
  final int scans = report.added
      .where((Book book) => isMarkedScan(book.hasTextLayer))
      .length;
  if (scans > 0) {
    lines.add(
      'Сканов без текста: $scans — в них не работают выделение, поиск '
      'и функции.',
    );
  }
  if (report.repeats > 0) {
    lines.add(
      'Одинаковых файлов в архиве: ${report.repeats} — такая книга '
      'стоит на полке один раз.',
    );
  }
  if (report.skipped > 0) {
    lines.add('Пропущено не-PDF: ${report.skipped}.');
  }
  if (report.failed.isNotEmpty) {
    lines.add('Не открылось: ${report.failed.length}');
    for (final ImportFailure failure in report.failed.take(kNamedFailures)) {
      lines.add('«${failure.name}» — ${describeAddFailure(failure)}');
    }
    final int rest = report.failed.length - kNamedFailures;
    if (rest > 0) {
      lines.add('И ещё не добавлено: $rest');
    }
  }
  final String? stopped = report.stopped;
  if (stopped != null) {
    lines.add(
      'Распаковка остановлена: $stopped. Распакованное осталось на '
      'полке; добавьте архив ещё раз — продолжит с того же места.',
    );
  }
  return lines.join('\n');
}

/// Что известно о поиске архивов на устройстве (SNO-F-LIT-03).
enum ArchiveSearchPhase {
  /// Блок «Для экспериментатора» ещё не раскрывали: ничего не искали.
  idle,

  /// На телефоне нет доступа к файлам: искать нельзя, пока его не дали.
  needsAccess,

  /// Обход идёт; найденное уже стоит в списке.
  searching,

  /// Обход кончился — дошёл до конца или оборвался.
  finished,
}

/// Раздел «Тестирование» сборок ветвей СНО2026 (SNO-F-CFG-03).
///
/// Единственное место инструментов исследования: всё остальное
/// приложение остаётся читалкой. Пунктов-заглушек здесь нет — запись,
/// cognitive load test и записи на устройстве появляются вместе со
/// своими функциями. Сейчас в разделе: код устройства, блок «Для
/// экспериментатора» с архивами литературы (SNO-F-LIT-03, SNO-F-LIT-01)
/// и сведения о ветви (SNO-F-CFG-01).
///
/// **Архив с литературой приложение находит само** (SNO-F-LIT-03).
/// Когда блок «Для экспериментатора» раскрыт, устройство обходится
/// (`AppServices.archiveSearch`), и ZIP-архивы с книгами встают списком;
/// нажатие на архив раскладывает его по полке. Обход начинается только
/// отсюда: запуск приложения и полка ничего не ищут, и тестировщик,
/// который в блок не заходит, запроса на доступ к файлам не видит.
/// Системный диалог выбора остаётся запасным путём.
///
/// **Свои PDF не добавляются** (SNO-F-LIT-02 снята решением владельца
/// П3 от 04.10.2026): книга, выбранная вручную вместо архива, названа
/// отказом и на полку не встаёт.
class TestingScreen extends StatefulWidget {
  /// Создаёт раздел.
  ///
  /// [unpack] подменяет распаковку архива в widget-тестах: настоящая
  /// пишет на диск, а в них файлового ввода-вывода быть не должно.
  const TestingScreen({
    required this.services,
    required this.flags,
    this.unpack,
    super.key,
  });

  /// Службы приложения.
  final AppServices services;

  /// Флаги сборки — для строки «О ветви».
  final BranchFlags flags;

  /// Распаковка архива; `null` — настоящая.
  final ArchiveUnpack? unpack;

  @override
  State<TestingScreen> createState() => _TestingScreenState();
}

class _TestingScreenState extends State<TestingScreen>
    with WidgetsBindingObserver {
  /// Идёт ли добавление архива.
  bool _busy = false;

  /// Открыт ли диалог выбора: второе нажатие, пока он открыт, не должно
  /// начать второе добавление.
  bool _picking = false;

  /// Имя архива, который добавляется сейчас; `null` — архив не идёт.
  String? _archiveName;

  /// Какая книга архива распаковывается; `null` — архив ещё открывается
  /// или не идёт вовсе.
  ArchiveProgress? _unpacking;

  /// Раскрыт ли блок «Для экспериментатора».
  bool _expanded = false;

  /// Что известно о поиске архивов.
  ArchiveSearchPhase _phase = ArchiveSearchPhase.idle;

  /// Найденные архивы, в порядке списка.
  List<FoundArchive> _found = const <FoundArchive>[];

  /// Корни обхода — от них считается, где лежит архив.
  List<String> _roots = const <String>[];

  /// Почему обход оборвался; `null` — идёт или дошёл до конца.
  String? _searchFailure;

  /// Идущий обход.
  StreamSubscription<FoundArchive>? _searching;

  /// Номер поиска: ответ прежнего поиска, пришедший после начала
  /// нового, не принимается.
  int _searchRun = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchRun++;
    unawaited(_searching?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Доступ к файлам выдают на системном экране, и ответа Android не
    // даёт: узнать о нём можно, только спросив заново, когда приложение
    // вернулось на передний план.
    if (state == AppLifecycleState.resumed &&
        _expanded &&
        _phase == ArchiveSearchPhase.needsAccess) {
      unawaited(_search());
    }
  }

  void _expansionChanged(bool expanded) {
    _expanded = expanded;
    // Обход, который уже идёт, заново не начинается: блок свернули и
    // раскрыли, а архивы всё те же.
    if (expanded && _phase != ArchiveSearchPhase.searching) {
      unawaited(_search());
    }
  }

  /// Ищет архивы с книгами на устройстве (SNO-F-LIT-03).
  ///
  /// На телефоне без доступа ко всем файлам искать нечем: раздел
  /// говорит об этом и предлагает дать доступ — или выбрать архив
  /// вручную. На ПК доступ не нужен.
  Future<void> _search() async {
    final int run = ++_searchRun;
    final StreamSubscription<FoundArchive>? previous = _searching;
    _searching = null;
    await previous?.cancel();
    final StorageAccessState access = await widget.services.access.state();
    if (!mounted || run != _searchRun) {
      return;
    }
    if (!access.allowsScan) {
      setState(() {
        _phase = ArchiveSearchPhase.needsAccess;
        _found = const <FoundArchive>[];
        _searchFailure = null;
      });
      return;
    }
    final List<String> roots = await widget.services.access.roots();
    if (!mounted || run != _searchRun) {
      return;
    }
    setState(() {
      _phase = ArchiveSearchPhase.searching;
      _found = const <FoundArchive>[];
      _roots = roots;
      _searchFailure = null;
    });
    final Stream<FoundArchive> stream = widget.services.archiveSearch(roots);
    _searching = stream.listen(
      (FoundArchive archive) {
        if (!mounted || run != _searchRun) {
          return;
        }
        // Список растёт, пока идёт обход, и остаётся в своём порядке:
        // новые сверху.
        final List<FoundArchive> found = <FoundArchive>[..._found, archive];
        found.sort(compareFoundArchives);
        setState(() => _found = found);
      },
      onError: (Object error) {
        if (!mounted || run != _searchRun) {
          return;
        }
        final String reason = error is ScanFailure
            ? error.reason
            : 'обход устройства не удался';
        setState(() => _searchFailure = reason);
      },
      onDone: () {
        if (!mounted || run != _searchRun) {
          return;
        }
        setState(() => _phase = ArchiveSearchPhase.finished);
      },
    );
  }

  /// Открывает системный экран выдачи доступа к файлам.
  ///
  /// Ответ приходит не сюда: состояние перепроверяется, когда
  /// приложение снова на переднем плане
  /// ([didChangeAppLifecycleState]). Сразу оно спрашивается на случай,
  /// когда доступ дан без ухода из приложения.
  Future<void> _allowAndSearch() async {
    await widget.services.access.request();
    if (!mounted) {
      return;
    }
    await _search();
  }

  /// Выбор архива системным диалогом — запасной путь.
  Future<void> _pickArchives() async {
    if (_busy || _picking) {
      return;
    }
    final List<PickedFile> files;
    _picking = true;
    try {
      files = await widget.services.picker.pickArchives();
    } finally {
      _picking = false;
    }
    if (files.isEmpty || !mounted) {
      return;
    }
    await _addArchives(files);
  }

  /// Раскладывает архивы [files] по полке (SNO-F-LIT-01).
  ///
  /// Сюда приходит и архив из найденных, и выбранное диалогом. Книга
  /// (PDF) вместо архива не добавляется и названа в итоге (решение П3);
  /// всё остальное уходит в распаковку, и не-архив получает свой отказ
  /// от неё — «это не ZIP-архив».
  Future<void> _addArchives(List<PickedFile> files) async {
    if (_busy) {
      return;
    }
    final List<PickedFile> archives = <PickedFile>[
      for (final PickedFile file in files)
        if (!isBookName(file.name)) file,
    ];
    final List<String> books = <String>[
      for (final PickedFile file in files)
        if (isBookName(file.name)) file.name,
    ];
    final List<ArchiveReport> unpacked = <ArchiveReport>[];
    if (archives.isNotEmpty) {
      setState(() {
        _busy = true;
        _archiveName = null;
        _unpacking = null;
      });
      try {
        final ArchiveUnpack unpack = widget.unpack ?? _archive().add;
        for (final PickedFile archive in archives) {
          if (mounted) {
            setState(() {
              _archiveName = archive.name;
              _unpacking = null;
            });
          }
          try {
            unpacked.add(
              await unpack(
                archive,
                onProgress: (ArchiveProgress progress) {
                  if (mounted) {
                    setState(() => _unpacking = progress);
                  }
                },
              ),
            );
          } on Object {
            // Распаковка обещает не бросать; если всё же бросила, итог
            // остальных файлов не должен пропасть вместе с ней.
            unpacked.add(
              ArchiveReport(
                archive: archive.name,
                stopped: 'распаковка прервалась из-за ошибки приложения',
              ),
            );
          }
        }
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _archiveName = null;
            _unpacking = null;
          });
        }
      }
    }
    if (!mounted) {
      return;
    }
    // Итог — окном, которое само не исчезает: распаковка идёт минуты, и
    // экспериментатор мог отвернуться.
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          key: const Key('sno-archive-report'),
          title: Text(_reportTitle(unpacked)),
          content: SingleChildScrollView(
            child: Text(_describeAll(books, unpacked)),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Понятно'),
            ),
          ],
        );
      },
    );
  }

  /// Настоящая распаковка архива — на службах приложения.
  LiteratureArchive _archive() {
    return LiteratureArchive(
      library: widget.services.data.library,
      categories: widget.services.data.categories,
      storage: widget.services.storage,
      opener: widget.services.opener,
    );
  }

  String _reportTitle(List<ArchiveReport> archives) {
    if (archives.isEmpty) {
      return 'Книги добавляются архивом';
    }
    return archives.length == 1
        ? 'Архив «${archives.single.archive}»'
        : 'Архивы: ${archives.length}';
  }

  /// Итог всего выбранного одним текстом.
  String _describeAll(List<String> books, List<ArchiveReport> archives) {
    return <String>[
      if (books.isNotEmpty) describeRefusedBooks(books),
      for (final ArchiveReport archive in archives)
        archives.length == 1
            ? describeArchiveReport(archive)
            : '«${archive.archive}»\n${describeArchiveReport(archive)}',
    ].join('\n\n');
  }

  /// Что написано в строке хода, пока идёт распаковка.
  Widget _progress() {
    final ArchiveProgress? unpacking = _unpacking;
    if (unpacking == null) {
      // Оглавление архива читается до первой книги, а на телефоне архив
      // из облака сначала переносится в приложение — это не миг.
      final String? archive = _archiveName;
      return Text(
        archive == null ? 'Открываю архив…' : 'Открываю архив «$archive»…',
      );
    }
    final String? category = unpacking.category;
    return Column(
      key: const Key('sno-archive-progress'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Распаковываю архив: ${unpacking.number} из ${unpacking.total}'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: LinearProgressIndicator(
            value: (unpacking.number - 1) / unpacking.total,
          ),
        ),
        Text(
          category == null ? unpacking.title : '$category · ${unpacking.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// Блок «Для экспериментатора»: архивы с книгами (SNO-F-LIT-03).
  List<Widget> _experimenter(ThemeData theme) {
    final bool needsAccess = _phase == ArchiveSearchPhase.needsAccess;
    final String? failure = _searchFailure;
    return <Widget>[
      if (_busy)
        ListTile(
          key: const Key('sno-archive-busy'),
          leading: const Icon(Icons.unarchive_outlined),
          title: const Text('Добавляю архив'),
          subtitle: _progress(),
          trailing: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Архивы с книгами на устройстве',
            style: theme.textTheme.titleSmall,
          ),
        ),
      ),
      if (needsAccess)
        Padding(
          key: const Key('sno-archives-access'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Чтобы найти архив с книгами, нужен доступ к файлам. '
                'Приложение ищет только ZIP-архивы с книгами.',
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('sno-archives-allow'),
                onPressed: _busy ? null : () => unawaited(_allowAndSearch()),
                child: const Text('Разрешить и найти'),
              ),
            ],
          ),
        ),
      for (final (int index, FoundArchive archive) in _found.indexed)
        ListTile(
          key: Key('sno-archive-$index'),
          leading: const Icon(Icons.folder_zip_outlined),
          title: Text(
            archive.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(describeFoundArchive(archive, _roots)),
          trailing: const Icon(Icons.chevron_right),
          enabled: !_busy,
          // Архив назван самим собой, а не местом в списке: пока идёт
          // обход, список растёт и места сдвигаются.
          onTap: () => unawaited(_addFound(archive)),
        ),
      if (_phase == ArchiveSearchPhase.searching)
        const Padding(
          key: Key('sno-archives-searching'),
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Ищу архивы…'),
            ],
          ),
        ),
      if (failure != null)
        Padding(
          key: const Key('sno-archives-failure'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Поиск прервался: $failure.'),
          ),
        ),
      if (_phase == ArchiveSearchPhase.finished &&
          _found.isEmpty &&
          failure == null)
        const Padding(
          key: Key('sno-archives-empty'),
          padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Архивов с книгами не найдено. Архив из мессенджера '
              'сначала сохраните в «Загрузки».',
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Wrap(
          children: <Widget>[
            if (!needsAccess)
              TextButton.icon(
                key: const Key('sno-archives-refresh'),
                onPressed: _busy ? null : () => unawaited(_search()),
                icon: const Icon(Icons.refresh),
                label: const Text('Искать заново'),
              ),
            TextButton(
              key: const Key('sno-add-archive'),
              onPressed: _busy ? null : () => unawaited(_pickArchives()),
              child: const Text('Выбрать вручную…'),
            ),
          ],
        ),
      ),
    ];
  }

  /// Раскладывает по полке архив из найденных.
  ///
  /// Архив читается там, где лежит, по пути: на телефоне доступ к нему
  /// даёт то же разрешение, с которым он найден.
  Future<void> _addFound(FoundArchive archive) {
    return _addArchives(<PickedFile>[
      PickedFile(name: archive.name, path: archive.path),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String device = deviceCodeOf(widget.services.data.clock.nodeId);
    return Scaffold(
      appBar: AppBar(title: const Text('Тестирование')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // На широком окне ПК строки во всю ширину читать неудобно.
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            children: <Widget>[
              ListTile(
                key: const Key('sno-device'),
                title: const Text('Устройство'),
                subtitle: Text(device),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(
                  'Запись, тест и записи появятся здесь следующими '
                  'сборками.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const Divider(),
              ExpansionTile(
                key: const Key('sno-experimenter'),
                title: const Text('Для экспериментатора'),
                onExpansionChanged: _expansionChanged,
                children: _experimenter(theme),
              ),
              const Divider(),
              ListTile(
                key: const Key('sno-about'),
                title: const Text('О ветви'),
                subtitle: Text(
                  buildLabelFor(
                    version: appVersion,
                    commit: appCommit,
                    flags: widget.flags,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
