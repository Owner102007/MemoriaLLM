import 'dart:async';

import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../application/build_info.dart';
import '../application/library/book_importer.dart';
import '../domain/library/book_file_picker.dart';
import '../domain/reading/reader_document.dart';
import 'flags.dart';

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

/// Что сказать экспериментатору после «Добавить PDF…» (SNO-F-LIT-02).
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

/// Раздел «Тестирование» сборок ветвей СНО2026 (SNO-F-CFG-03).
///
/// Единственное место инструментов исследования: всё остальное
/// приложение остаётся читалкой. Пунктов-заглушек здесь нет — запись,
/// cognitive load test и записи на устройстве появляются вместе со
/// своими функциями. Сейчас в разделе: код устройства, блок «Для
/// экспериментатора» с добавлением книг (SNO-F-LIT-02) и сведения о
/// ветви (SNO-F-CFG-01).
class TestingScreen extends StatefulWidget {
  /// Создаёт раздел.
  const TestingScreen({required this.services, required this.flags, super.key});

  /// Службы приложения.
  final AppServices services;

  /// Флаги сборки — для строки «О ветви».
  final BranchFlags flags;

  @override
  State<TestingScreen> createState() => _TestingScreenState();
}

class _TestingScreenState extends State<TestingScreen> {
  /// Идёт ли добавление книг.
  bool _busy = false;

  /// Сколько файлов уже разобрано и сколько выбрано.
  int _done = 0;
  int _total = 0;

  /// Добавляет выбранные PDF на полку (SNO-F-LIT-02).
  ///
  /// Файлы выбираются системным диалогом — разрешений на доступ к
  /// файлам он не требует. Книга копируется в папку приложения: так
  /// решает хранилище сборки ветви (`AppServices.production`), а не
  /// этот экран. Встаёт она в «Без категории».
  Future<void> _addPdf() async {
    if (_busy) {
      return;
    }
    final List<PickedFile> files = await widget.services.picker.pickPdfs();
    if (files.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _done = 0;
      _total = files.length;
    });
    final BookImporter importer = BookImporter(
      library: widget.services.data.library,
      storage: widget.services.storage,
      opener: widget.services.opener,
    );
    final ImportReport report;
    try {
      report = await importer.registerAll(
        files,
        onProgress: (int done, int total) {
          if (mounted) {
            setState(() => _done = done);
          }
        },
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(describeAddedPdfs(report)),
        // Сообщение с причинами и со словом о скане длиннее обычного —
        // его надо успеть прочесть.
        duration: report.isClean && report.scans.isEmpty
            ? const Duration(seconds: 4)
            : const Duration(seconds: 10),
      ),
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
                    title: const Text('Добавить PDF…'),
                    subtitle: Text(
                      _busy
                          ? 'Добавляю: $_done из $_total'
                          : 'Книга копируется в приложение и встаёт '
                                'в «Без категории»',
                    ),
                    trailing: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    enabled: !_busy,
                    onTap: () => unawaited(_addPdf()),
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
