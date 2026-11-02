/// Автосценарии на настоящем приложении (F-REL-09).
///
/// Что это. Не widget-тест с заглушками, а запуск того же приложения, что
/// у читателя (`startApp` из `lib/main.dart`): настоящая база, PDFium,
/// экраны. Подменён только системный выбор файла — сценарий отдаёт
/// подложенный PDF из `test/fixtures/`.
///
/// Как запускать — `tool/agent/scenarios.ps1` (создаёт новую папку данных
/// и передаёт её в `--dart-define=MEMORIA_DATA_DIR`). Без папки данных
/// сценарии не стартуют: база владельца не трогается (F-REL-10).
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/infrastructure/database/connection.dart';
import 'package:memoria/infrastructure/files/app_directory.dart';
import 'package:memoria/main.dart' as app;
import 'package:path/path.dart' as p;

/// Выбор файла без диалога: каждый раз отдаёт [files].
class _FixturePicker implements BookFilePicker {
  _FixturePicker(this.files);

  final List<PickedFile> files;

  @override
  Future<PickedFile?> pickPdf() async => files.isEmpty ? null : files.first;

  @override
  Future<List<PickedFile>> pickPdfs() async => files;

  // Архивы выбирает только сборка ветви СНО2026 — сценарии основного
  // приложения до них не доходят.
  @override
  Future<List<PickedFile>> pickArchives() async => const <PickedFile>[];
}

/// Ждёт, пока на экране появится [finder], не дольше [timeout].
///
/// `pumpAndSettle` здесь не годится: у настоящего приложения есть
/// бесконечные анимации (индикаторы загрузки), и «успокоения» не будет.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final DateTime end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Не дождались на экране: $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'F-REL-09 F-REL-10 F-APP-02 F-DEV-09: запуск на своей папке, разделы, '
    'книга вручную',
    (WidgetTester tester) async {
      // F-REL-10: без своей папки данных сценарий не идёт — иначе он
      // открыл бы базу владельца.
      expect(
        kDataDirOverride,
        isNotEmpty,
        reason: 'нужен --dart-define=MEMORIA_DATA_DIR=<новая папка>',
      );
      final File database = File(p.join(kDataDirOverride, databaseFileName));
      expect(
        database.existsSync(),
        isFalse,
        reason: 'папка данных должна быть новой: сценарий начинает с нуля',
      );

      // Подложенная книга — копия образца рядом с папкой данных: так
      // путь у книги настоящий и переживает весь прогон.
      final Directory books = Directory('$kDataDirOverride-книги')
        ..createSync(recursive: true);
      final File book = File(p.join('test', 'fixtures', 'basic_text.pdf'))
          .copySync(p.join(books.path, 'Автопроверка.pdf'));

      final AppServices services = await app.startApp(
        picker: _FixturePicker(<PickedFile>[
          PickedFile(name: 'Автопроверка.pdf', path: book.path),
        ]),
      );
      await _pumpUntil(tester, find.byKey(const Key('nav-library')));

      // F-REL-10: база легла в свою папку.
      expect(database.existsSync(), isTrue);

      // F-APP-02: разделы открываются из навигации.
      // «Настройки» видны и в полосе навигации — ждём то, что есть только
      // на самом экране настроек.
      await tester.tap(find.byKey(const Key('nav-settings')));
      await _pumpUntil(tester, find.text('Оформление'));
      await tester.tap(find.byKey(const Key('nav-device')));
      await _pumpUntil(tester, find.byKey(const Key('device-pick-files')));

      // F-DEV-09: книга добавляется выбором файла.
      await tester.tap(find.byKey(const Key('device-pick-files')));
      await _pumpUntil(tester, find.text('Книга добавлена'));
      final List<Book> shelf = await services.data.library.books();
      expect(shelf, hasLength(1));

      await tester.tap(find.byKey(const Key('nav-library')));
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
