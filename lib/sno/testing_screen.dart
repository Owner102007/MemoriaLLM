import 'dart:async';

import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../application/build_info.dart';
import '../application/library/book_importer.dart';
import '../domain/library/book.dart';
import '../domain/library/book_file_picker.dart';
import '../domain/library/scan_mark.dart';
import '../domain/library/shelf_archive.dart';
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

/// Что сказать экспериментатору после добавления файлов PDF
/// (SNO-F-LIT-02).
///
/// Отличие от сообщения основного приложения одно: файл, который не
/// встал на полку, назван вместе с причиной. Экспериментатор готовит
/// устройство к тесту и должен знать, какой именно книги на полке нет
/// и почему — не PDF, повреждён, защищён паролем.
String describeAddedPdfs(ImportReport report) {
  final StringBuffer text = StringBuffer(describeImportReport(report));
  for (final ImportFailure failure in report.failed.take(kNamedFailures)) {
    text.write('\n«${failure.name}» — ${describeAddFailure(failure)}');
  }
  final int rest = report.failed.length - kNamedFailures;
  if (rest > 0) {
    text.write('\nИ ещё не добавлено: $rest');
  }
  return text.toString();
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

/// Раздел «Тестирование» сборок ветвей СНО2026 (SNO-F-CFG-03).
///
/// Единственное место инструментов исследования: всё остальное
/// приложение остаётся читалкой. Пунктов-заглушек здесь нет — запись,
/// cognitive load test и записи на устройстве появляются вместе со
/// своими функциями. Сейчас в разделе: код устройства, блок «Для
/// экспериментатора» с добавлением книг и архива с литературой
/// (SNO-F-LIT-02, SNO-F-LIT-01) и сведения о ветви (SNO-F-CFG-01).
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

class _TestingScreenState extends State<TestingScreen> {
  /// Идёт ли добавление книг.
  bool _busy = false;

  /// Сколько файлов уже разобрано и сколько выбрано.
  int _done = 0;
  int _total = 0;

  /// Какая книга архива распаковывается; `null` — архив не идёт.
  ArchiveProgress? _unpacking;

  /// Добавляет выбранные книги и архивы на полку (SNO-F-LIT-02,
  /// SNO-F-LIT-01).
  ///
  /// Файлы выбираются системным диалогом — разрешений на доступ к
  /// файлам он не требует. PDF копируется в папку приложения и встаёт в
  /// «Без категории»: так решает хранилище сборки ветви
  /// (`AppServices.production`), а не этот экран. Архив распаковывается
  /// туда же, и его книги встают по своим папкам (`LiteratureArchive`).
  Future<void> _addBooks() async {
    if (_busy) {
      return;
    }
    final List<PickedFile> files = await widget.services.picker
        .pickBooksOrArchives();
    if (files.isEmpty || !mounted) {
      return;
    }
    final List<PickedFile> archives = <PickedFile>[
      for (final PickedFile file in files)
        if (isArchiveName(file.name)) file,
    ];
    final List<PickedFile> pdfs = <PickedFile>[
      for (final PickedFile file in files)
        if (!isArchiveName(file.name)) file,
    ];
    setState(() {
      _busy = true;
      _done = 0;
      _total = pdfs.length;
      _unpacking = null;
    });
    ImportReport? report;
    final List<ArchiveReport> unpacked = <ArchiveReport>[];
    try {
      if (pdfs.isNotEmpty) {
        final BookImporter importer = BookImporter(
          library: widget.services.data.library,
          storage: widget.services.storage,
          opener: widget.services.opener,
        );
        report = await importer.registerAll(
          pdfs,
          onProgress: (int done, int total) {
            if (mounted) {
              setState(() => _done = done);
            }
          },
        );
      }
      if (archives.isNotEmpty) {
        final ArchiveUnpack unpack = widget.unpack ?? _archive().add;
        for (final PickedFile archive in archives) {
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
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _unpacking = null;
        });
      }
    }
    if (!mounted) {
      return;
    }
    if (unpacked.isEmpty) {
      final ImportReport added = report!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(describeAddedPdfs(added)),
          // Сообщение с причинами и со словом о скане длиннее обычного —
          // его надо успеть прочесть.
          duration: added.isClean && added.scans.isEmpty
              ? const Duration(seconds: 4)
              : const Duration(seconds: 10),
        ),
      );
      return;
    }
    // Итог архива — окном, которое само не исчезает: распаковка идёт
    // минуты, и экспериментатор мог отвернуться.
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          key: const Key('sno-archive-report'),
          title: Text(
            unpacked.length == 1
                ? 'Архив «${unpacked.single.archive}»'
                : 'Архивы: ${unpacked.length}',
          ),
          content: SingleChildScrollView(
            child: Text(_describeAll(report, unpacked)),
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

  /// Итог всего выбранного одним текстом.
  String _describeAll(ImportReport? pdfs, List<ArchiveReport> archives) {
    return <String>[
      if (pdfs != null) describeAddedPdfs(pdfs),
      for (final ArchiveReport archive in archives)
        archives.length == 1
            ? describeArchiveReport(archive)
            : '«${archive.archive}»\n${describeArchiveReport(archive)}',
    ].join('\n\n');
  }

  /// Что написано под кнопкой, пока идёт добавление.
  Widget _progress() {
    final ArchiveProgress? unpacking = _unpacking;
    if (unpacking == null) {
      return Text('Добавляю: $_done из $_total');
    }
    final String? category = unpacking.category;
    return Column(
      key: const Key('sno-archive-progress'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Распаковываю архив: ${unpacking.number} из ${unpacking.total}',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: LinearProgressIndicator(
            value: (unpacking.number - 1) / unpacking.total,
          ),
        ),
        Text(
          category == null
              ? unpacking.title
              : '$category · ${unpacking.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
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
                children: <Widget>[
                  ListTile(
                    key: const Key('sno-add-pdf'),
                    leading: const Icon(Icons.note_add_outlined),
                    title: const Text('Добавить книги или архив…'),
                    subtitle: _busy
                        ? _progress()
                        : const Text(
                            'PDF встают в «Без категории»; архив — по '
                            'своим папкам',
                          ),
                    trailing: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    enabled: !_busy,
                    onTap: () => unawaited(_addBooks()),
                  ),
                ],
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
