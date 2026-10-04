import 'dart:async';

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
import 'package:memoria/sno/literature_archive.dart';
import 'package:memoria/sno/testing_screen.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/test_services.dart';

/// SNO-F-CFG-03, SNO-F-LIT-02, SNO-F-LIT-01: раздел «Тестирование» сам по
/// себе.
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
    ArchiveUnpack? unpack,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TestingScreen(
          services: services,
          flags: BranchFlags.of(branch),
          unpack: unpack,
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
      expect(find.textContaining('флаги: запись, литература'), findsOneWidget);

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
      expect(books.map((Book book) => book.title).toSet(), <String>{
        'Анатомия',
        'Гистология',
      });
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
      // Причина сказана словами раздела: вводить пароль здесь негде, и
      // звать к этому нельзя.
      expect(
        find.textContaining('«Секрет.pdf» — защищён паролем'),
        findsOneWidget,
      );
      expect(find.textContaining('Введите'), findsNothing);

      await unmount(tester);
    });
  });

  group('SNO-F-LIT-01: архив с книгами', () {
    const PickedFile archive = PickedFile(
      name: 'Литература.zip',
      path: '/picked/Литература.zip',
    );

    Book shelved(String id, {String? categoryId}) {
      final Book book = testBook(id: id, hash: 'hash-$id');
      return categoryId == null ? book : book.copyWith(categoryId: categoryId);
    }

    testWidgets('SNO-F-LIT-02: кнопка называет и книги, и архив', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester, testServices(data: data));
      await openExperimenter(tester);

      expect(find.text('Добавить книги или архив…'), findsOneWidget);
      expect(find.textContaining('архив — по своим папкам'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-01: архив распаковывается, итог — окном', (
      WidgetTester tester,
    ) async {
      final List<String> unpacked = <String>[];
      await pumpTesting(
        tester,
        testServices(data: data, picked: archive),
        unpack:
            (
              PickedFile file, {
              void Function(ArchiveProgress progress)? onProgress,
            }) async {
              unpacked.add(file.name);
              return ArchiveReport(
                archive: file.name,
                total: 3,
                added: <Book>[
                  shelved('a', categoryId: 'c1'),
                  shelved('b', categoryId: 'c2'),
                  shelved('c'),
                ],
                skipped: 2,
              );
            },
      );
      await openExperimenter(tester);

      await tester.tap(find.byKey(const Key('sno-add-pdf')));
      await tester.pumpAndSettle();

      expect(unpacked, <String>['Литература.zip']);
      // Архив не пошёл в импорт PDF: книг от него на полке нет.
      expect(await data.library.books(), isEmpty);
      expect(find.byKey(const Key('sno-archive-report')), findsOneWidget);
      expect(find.text('Архив «Литература.zip»'), findsOneWidget);
      expect(
        find.textContaining('Добавлено книг: 3, категорий: 2.'),
        findsOneWidget,
      );
      expect(find.textContaining('Пропущено не-PDF: 2.'), findsOneWidget);
      // Итог не исчезает сам: это окно, а не сообщение внизу экрана.
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-archive-report')), findsNothing);
      // Распаковка закончилась — кнопка снова готова.
      expect(find.textContaining('Распаковываю'), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-01: ход распаковки виден под кнопкой', (
      WidgetTester tester,
    ) async {
      final Completer<void> gate = Completer<void>();
      await pumpTesting(
        tester,
        testServices(data: data, picked: archive),
        unpack:
            (
              PickedFile file, {
              void Function(ArchiveProgress progress)? onProgress,
            }) async {
              onProgress?.call(
                const ArchiveProgress(
                  number: 12,
                  total: 34,
                  title: 'Анатомия человека',
                  category: 'Анатомия',
                ),
              );
              await gate.future;
              return ArchiveReport(archive: file.name, total: 34);
            },
      );
      await openExperimenter(tester);

      await tester.tap(find.byKey(const Key('sno-add-pdf')));
      // Не `pumpAndSettle`: пока идёт распаковка, крутится индикатор.
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('sno-archive-progress')), findsOneWidget);
      expect(find.text('Распаковываю архив: 12 из 34'), findsOneWidget);
      expect(find.text('Анатомия · Анатомия человека'), findsOneWidget);
      final LinearProgressIndicator bar = tester.widget(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(11 / 34, 1e-9));
      // Второй раз кнопка не нажимается, пока идёт первая распаковка.
      final ListTile tile = tester.widget(find.byKey(const Key('sno-add-pdf')));
      expect(tile.enabled, isFalse);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-archive-progress')), findsNothing);
      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-02: PDF и архив выбраны вместе', (
      WidgetTester tester,
    ) async {
      await pumpTesting(
        tester,
        testServices(
          data: data,
          batch: const <PickedFile>[
            PickedFile(name: 'Гистология.pdf', path: '/picked/Гистология.pdf'),
            archive,
          ],
          storage: const PathBytesStorage(),
        ),
        unpack:
            (
              PickedFile file, {
              void Function(ArchiveProgress progress)? onProgress,
            }) async {
              return ArchiveReport(
                archive: file.name,
                refusal: 'это не ZIP-архив',
              );
            },
      );
      await openExperimenter(tester);

      await tester.tap(find.byKey(const Key('sno-add-pdf')));
      await tester.pumpAndSettle();

      // PDF встал на полку своим путём, архив ушёл в распаковку.
      final List<Book> books = await data.library.books();
      expect(books.single.title, 'Гистология');
      expect(find.textContaining('Книга добавлена'), findsOneWidget);
      expect(
        find.textContaining('Архив не добавлен: это не ZIP-архив.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
      await unmount(tester);
    });
  });

  group('SNO-F-LIT-01: что сказать после архива', () {
    Book shelved(String id, {String? categoryId, bool? text}) {
      final Book book = testBook(id: id, hash: 'hash-$id');
      return book.copyWith(categoryId: categoryId, hasTextLayer: text);
    }

    test('SNO-F-LIT-01: книги и категории сосчитаны', () {
      final ArchiveReport report = ArchiveReport(
        archive: 'Литература.zip',
        total: 3,
        added: <Book>[
          shelved('a', categoryId: 'c1'),
          shelved('b', categoryId: 'c1'),
          shelved('c'),
        ],
      );
      expect(report.categories, 1);
      expect(describeArchiveReport(report), 'Добавлено книг: 3, категорий: 1.');
    });

    test('SNO-F-LIT-01: без папок категорий нет и в словах', () {
      final ArchiveReport report = ArchiveReport(
        archive: 'Литература.zip',
        total: 1,
        added: <Book>[shelved('a')],
      );
      expect(describeArchiveReport(report), 'Добавлено книг: 1.');
    });

    test('SNO-F-LIT-01: тот же архив ещё раз', () {
      const ArchiveReport report = ArchiveReport(
        archive: 'Литература.zip',
        total: 34,
        already: 34,
      );
      expect(
        describeArchiveReport(report),
        'Все книги архива уже на полке: 34.',
      );
    });

    test('SNO-F-LIT-01: часть была, часть встала, часть не открылась', () {
      final ArchiveReport report = ArchiveReport(
        archive: 'Литература.zip',
        total: 6,
        added: <Book>[
          shelved('a', categoryId: 'c1'),
          shelved('s', categoryId: 'c1', text: false),
        ],
        already: 2,
        skipped: 1,
        failed: const <ImportFailure>[
          ImportFailure(
            name: 'Атлас.pdf',
            reason: 'нужен пароль',
            problem: DocumentProblem.passwordRequired,
          ),
          ImportFailure(
            name: 'Гистология.pdf',
            reason: 'контрольная сумма не сошлась',
          ),
        ],
      );
      expect(describeArchiveReport(report).split('\n'), <String>[
        'Добавлено книг: 2, категорий: 1.',
        'Уже стояло на полке: 2.',
        'Сканов без текста: 1 — в них не работают выделение, поиск и функции.',
        'Пропущено не-PDF: 1.',
        'Не открылось: 2',
        '«Атлас.pdf» — защищён паролем',
        '«Гистология.pdf» — контрольная сумма не сошлась',
      ]);
    });

    test('SNO-F-LIT-01: отказ архива и остановка названы', () {
      expect(
        describeArchiveReport(
          const ArchiveReport(
            archive: 'x.zip',
            refusal: 'архив защищён паролем — пересоберите его без пароля',
          ),
        ),
        'Архив не добавлен: архив защищён паролем — пересоберите его без '
        'пароля.',
      );
      final String stopped = describeArchiveReport(
        ArchiveReport(
          archive: 'x.zip',
          total: 5,
          added: <Book>[shelved('a')],
          stopped: 'на устройстве кончилось место',
        ),
      );
      expect(stopped, contains('Добавлено книг: 1.'));
      expect(
        stopped,
        contains('Распаковка остановлена: на устройстве кончилось место.'),
      );
      expect(stopped, contains('добавьте архив ещё раз'));
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

    test('SNO-F-LIT-02: причина движка сказана своими словами', () {
      String reasonOf(DocumentProblem problem) {
        return describeAddFailure(
          ImportFailure(
            name: 'x.pdf',
            reason: describeDocumentProblem(problem),
            problem: problem,
          ),
        );
      }

      expect(reasonOf(DocumentProblem.passwordRequired), 'защищён паролем');
      expect(reasonOf(DocumentProblem.wrongPassword), 'защищён паролем');
      // Чужой файл и битый PDF движок не различает — названы оба.
      expect(reasonOf(DocumentProblem.damaged), 'не PDF или файл повреждён');
      expect(reasonOf(DocumentProblem.empty), 'файл пустой');
      for (final DocumentProblem problem in DocumentProblem.values) {
        expect(reasonOf(problem), isNotEmpty, reason: '$problem');
        expect(reasonOf(problem), isNot(contains('Введите')));
      }
      // Отказ не от движка — причина как есть.
      expect(
        describeAddFailure(
          const ImportFailure(name: 'x.pdf', reason: 'не удалось прочесть'),
        ),
        'не удалось прочесть',
      );
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
