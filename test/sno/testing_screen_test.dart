import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/library/book_importer.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/sno/flags.dart';
import 'package:memoria/sno/testing_screen.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/test_services.dart';

/// SNO-F-CFG-03, SNO-F-LIT-02: раздел «Тестирование» сам по себе.
///
/// Раздел получает флаги параметром, поэтому проверяется одним
/// прогоном для обеих ветвей. Как он встаёт в навигацию собранного
/// приложения — в `branch_app_test.dart`, прогонами ветвей.
void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  Future<void> pumpTesting(
    WidgetTester tester,
    AppServices services, {
    String branch = 'I',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TestingScreen(
          services: services,
          flags: BranchFlags.of(branch),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Снимает дерево и даёт drift и сообщению внизу экрана прибраться:
  /// время в widget-тестах подменено, и оставшийся таймер валит тест.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> openExperimenter(WidgetTester tester) async {
    await tester.tap(find.text('Для экспериментатора'));
    await tester.pumpAndSettle();
  }

  group('SNO-F-CFG-03: раздел «Тестирование»', () {
    testWidgets('SNO-F-CFG-03: в разделе код устройства', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester, testServices(data: data));

      final String code = deviceCodeOf(data.clock.nodeId);
      expect(code, hasLength(kDeviceCodeLength));
      expect(find.byKey(const Key('sno-device')), findsOneWidget);
      expect(find.text(code), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-03: блок «Для экспериментатора» свёрнут', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester, testServices(data: data));

      expect(find.text('Для экспериментатора'), findsOneWidget);
      expect(find.byKey(const Key('sno-add-pdf')), findsNothing);

      await openExperimenter(tester);
      expect(find.byKey(const Key('sno-add-pdf')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-01: «О ветви» называет ветвь и её флаги', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester, testServices(data: data));
      expect(find.textContaining('ветвь I · '), findsOneWidget);
      expect(
        find.textContaining('флаги: запись, литература'),
        findsOneWidget,
      );

      await pumpTesting(tester, testServices(data: data), branch: 'II');
      expect(find.textContaining('ветвь II · '), findsOneWidget);
      expect(find.textContaining('галактика, палимпсест'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-03: пунктов-заглушек в разделе нет', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester, testServices(data: data));
      await openExperimenter(tester);

      // Запись, тест и записи появятся вместе со своими функциями:
      // кнопка, которая ничего не делает, — ложь о сборке.
      expect(find.textContaining('Старт записи'), findsNothing);
      expect(find.textContaining('Cognitive load test'), findsNothing);
      expect(find.textContaining('Сбросить'), findsNothing);

      await unmount(tester);
    });
  });

  group('SNO-F-LIT-02: добавление PDF экспериментатором', () {
    testWidgets('SNO-F-LIT-02: выбранные PDF встают в «Без категории»', (
      WidgetTester tester,
    ) async {
      await pumpTesting(
        tester,
        testServices(
          data: data,
          batch: const <PickedFile>[
            PickedFile(name: 'Анатомия.pdf', path: '/picked/Анатомия.pdf'),
            PickedFile(name: 'Гистология.pdf', path: '/picked/Гистология.pdf'),
          ],
          // У каждой книги своё содержимое: иначе отпечатки совпали бы,
          // и вторая книга была бы принята за первую.
          storage: const PathBytesStorage(),
        ),
      );
      await openExperimenter(tester);

      await tester.tap(find.byKey(const Key('sno-add-pdf')));
      await tester.pumpAndSettle();

      final List<Book> books = await data.library.books();
      expect(books, hasLength(2));
      expect(
        books.map((Book book) => book.title).toSet(),
        <String>{'Анатомия', 'Гистология'},
      );
      expect(
        books.every((Book book) => book.categoryId == null),
        isTrue,
        reason: 'книги экспериментатора встают в «Без категории»',
      );
      expect(find.text('Добавлено книг: 2'), findsOneWidget);
      // Добавление закончилось — кнопка снова готова.
      expect(find.textContaining('Добавляю'), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-02: диалог закрыли — ничего не случилось', (
      WidgetTester tester,
    ) async {
      await pumpTesting(
        tester,
        testServices(data: data, batch: const <PickedFile>[]),
      );
      await openExperimenter(tester);

      await tester.tap(find.byKey(const Key('sno-add-pdf')));
      await tester.pumpAndSettle();

      expect(await data.library.books(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-02: файл, который не открылся, назван с причиной', (
      WidgetTester tester,
    ) async {
      await pumpTesting(
        tester,
        testServices(
          data: data,
          picked: const PickedFile(
            name: 'Секрет.pdf',
            path: '/picked/Секрет.pdf',
          ),
          opener: FakeDocumentOpener(
            FakeReaderDocument(pages: <String>['текст']),
            failure: const DocumentOpenException(
              DocumentProblem.passwordRequired,
              FilePathSource('/picked/Секрет.pdf'),
            ),
          ),
        ),
      );
      await openExperimenter(tester);

      await tester.tap(find.byKey(const Key('sno-add-pdf')));
      await tester.pumpAndSettle();

      expect(await data.library.books(), isEmpty);
      expect(find.textContaining('«Секрет.pdf»'), findsOneWidget);
      expect(find.textContaining('защищена паролем'), findsOneWidget);

      await unmount(tester);
    });
  });

  group('SNO-F-LIT-02: что сказать после добавления', () {
    Book book(String id) => testBook(id: id, hash: 'hash-$id');

    test('SNO-F-LIT-02: без отказов — то же, что в основном приложении', () {
      final ImportReport report = ImportReport(
        added: <Book>[book('a'), book('b')],
        failed: const <ImportFailure>[],
      );
      expect(describeAddedPdfs(report), describeImportReport(report));
      expect(describeAddedPdfs(report), 'Добавлено книг: 2');
    });

    test('SNO-F-LIT-02: отказ назван именем файла и причиной', () {
      final ImportReport report = ImportReport(
        added: <Book>[book('a')],
        failed: const <ImportFailure>[
          ImportFailure(name: 'Битый.pdf', reason: 'файл повреждён'),
        ],
      );
      final String text = describeAddedPdfs(report);
      expect(text, startsWith(describeImportReport(report)));
      expect(text, contains('«Битый.pdf» — файл повреждён'));
    });

    test('SNO-F-LIT-02: поимённо названы три отказа, остальные числом', () {
      final ImportReport report = ImportReport(
        added: const <Book>[],
        failed: <ImportFailure>[
          for (int i = 1; i <= 5; i++)
            ImportFailure(name: 'Файл $i.pdf', reason: 'не открылся'),
        ],
      );
      final String text = describeAddedPdfs(report);
      for (int i = 1; i <= kNamedFailures; i++) {
        expect(text, contains('«Файл $i.pdf»'));
      }
      expect(text, isNot(contains('«Файл 4.pdf»')));
      expect(text, contains('И ещё не добавлено: 2'));
    });
  });

  group('SNO-F-CFG-03: код устройства', () {
    test('SNO-F-CFG-03: первые шесть знаков идентификатора узла', () {
      expect(deviceCodeOf('a91f3c0b7d2e4f60a91f3c0b7d2e4f60'), 'a91f3c');
      expect(deviceCodeOf('a91f'), 'a91f');
      expect(deviceCodeOf(''), '');
    });
  });
}
