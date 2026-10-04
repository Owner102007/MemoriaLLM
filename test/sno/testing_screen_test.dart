import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/library/book_importer.dart';
import 'package:memoria/domain/library/archive_scan.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/device_scan.dart';
import 'package:memoria/domain/library/storage_access.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/sno/flags.dart';
import 'package:memoria/sno/hold_button.dart';
import 'package:memoria/sno/literature_archive.dart';
import 'package:memoria/sno/reference_state.dart';
import 'package:memoria/sno/testing_screen.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/test_services.dart';

/// SNO-F-CFG-03, SNO-F-LIT-03, SNO-F-LIT-01: раздел «Тестирование» сам по
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

  /// Приложение свернули и вернули на передний план — так выглядит
  /// возвращение с системного экрана выдачи доступа.
  Future<void> backToApp(WidgetTester tester) async {
    for (final String state in <String>['paused', 'resumed']) {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/lifecycle',
        const StringCodec().encodeMessage('AppLifecycleState.$state'),
        (_) {},
      );
    }
    await tester.pumpAndSettle();
  }

  /// Распаковка, которая записывает, что ей дали, и отвечает [report].
  ArchiveUnpack recording(
    List<PickedFile> seen, {
    ArchiveReport Function(PickedFile file)? report,
  }) {
    return (
      PickedFile file, {
      void Function(ArchiveProgress progress)? onProgress,
    }) async {
      seen.add(file);
      return report?.call(file) ?? ArchiveReport(archive: file.name);
    };
  }

  /// Строка найденного архива: она названа самим архивом, а не местом
  /// в списке.
  Finder listed(FoundArchive archive) {
    return find.byKey(ValueKey<String>('sno-archive:${archive.path}'));
  }

  const PickedFile archive = PickedFile(
    name: 'Литература.zip',
    path: '/picked/Литература.zip',
  );

  final FoundArchive found = FoundArchive(
    path: '/device/Download/Литература.zip',
    // 2,1 ГБ.
    size: 2254857830,
    modifiedAt: DateTime.utc(2026, 10, 4, 12),
    books: 34,
  );

  final FoundArchive older = FoundArchive(
    path: '/device/Download/Telegram/Старая литература.zip',
    size: 5 * 1024 * 1024,
    modifiedAt: DateTime.utc(2026, 9, 1, 12),
    books: 2,
  );

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
      expect(find.byKey(const Key('sno-add-archive')), findsNothing);

      await openExperimenter(tester);
      expect(find.byKey(const Key('sno-add-archive')), findsOneWidget);

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
      // Сброс появился со своей функцией (SNO-F-CFG-04), но пока
      // эталона нет, сбрасывать не к чему — и кнопки нет.
      expect(find.byKey(const Key('sno-reset-hold')), findsNothing);

      await unmount(tester);
    });
  });

  group('SNO-F-LIT-03: архивы находятся на устройстве сами', () {
    testWidgets('SNO-F-LIT-03: пока блок свёрнут, устройство не обходится', (
      WidgetTester tester,
    ) async {
      final List<List<String>> searches = <List<String>>[];
      final FakeStorageAccess access = FakeStorageAccess();
      await pumpTesting(
        tester,
        testServices(
          data: data,
          access: access,
          archiveSearch: (List<String> roots) {
            searches.add(roots);
            return const Stream<FoundArchive>.empty();
          },
        ),
      );

      // Раздел построен вместе с приложением — и ничего не ищет.
      expect(searches, isEmpty);

      await openExperimenter(tester);
      // Ищет там же, где сканер основного приложения: в его корнях.
      expect(searches, <List<String>>[
        <String>['/device'],
      ]);
      // Доступ уже есть — спрашивать нечего.
      expect(access.requests, 0);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-03: найденные архивы стоят списком, новые сверху', (
      WidgetTester tester,
    ) async {
      await pumpTesting(
        tester,
        // Обход отдал их в другом порядке — как лежат на диске.
        testServices(data: data, archives: <FoundArchive>[older, found]),
      );
      await openExperimenter(tester);

      expect(find.text('Архивы с книгами на устройстве'), findsOneWidget);
      expect(find.text('Литература.zip'), findsOneWidget);
      expect(find.text('34 книги · 2,1 ГБ · Download'), findsOneWidget);
      expect(find.text('Старая литература.zip'), findsOneWidget);
      expect(find.text('2 книги · 5,0 МБ · Download/Telegram'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Литература.zip')).dy,
        lessThan(tester.getTopLeft(find.text('Старая литература.zip')).dy),
      );
      // Обход кончился: ни «ищу», ни «не найдено».
      expect(find.byKey(const Key('sno-archives-searching')), findsNothing);
      expect(find.byKey(const Key('sno-archives-empty')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-03: архив из списка уходит в ту же распаковку', (
      WidgetTester tester,
    ) async {
      final List<PickedFile> unpacked = <PickedFile>[];
      final AppServices services = testServices(
        data: data,
        archives: <FoundArchive>[found],
      );
      await pumpTesting(
        tester,
        services,
        unpack: recording(
          unpacked,
          report: (PickedFile file) => ArchiveReport(
            archive: file.name,
            total: 34,
            added: <Book>[testBook(id: 'a', hash: 'hash-a')],
          ),
        ),
      );
      await openExperimenter(tester);

      await tester.tap(listed(found));
      await tester.pumpAndSettle();

      // Архив читается там, где лежит, — по пути; диалога выбора не было.
      expect(unpacked.single.name, 'Литература.zip');
      expect(unpacked.single.path, '/device/Download/Литература.zip');
      expect(unpacked.single.uri, isNull);
      expect(find.byKey(const Key('sno-archive-report')), findsOneWidget);
      expect(find.text('Архив «Литература.zip»'), findsOneWidget);
      expect(find.textContaining('Добавлено книг: 1.'), findsOneWidget);

      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-03: архивов нет — сказано словами', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester, testServices(data: data));
      await openExperimenter(tester);

      expect(find.byKey(const Key('sno-archives-empty')), findsOneWidget);
      expect(
        find.textContaining('Архивов с книгами не найдено.'),
        findsOneWidget,
      );
      // Запасной путь и повтор остаются.
      expect(find.byKey(const Key('sno-add-archive')), findsOneWidget);
      expect(find.byKey(const Key('sno-archives-refresh')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-03: пока идёт обход, найденное уже в списке', (
      WidgetTester tester,
    ) async {
      final StreamController<FoundArchive> scan =
          StreamController<FoundArchive>();
      await pumpTesting(
        tester,
        testServices(
          data: data,
          archiveSearch: (List<String> roots) => scan.stream,
        ),
      );
      // Не `pumpAndSettle`: пока идёт обход, крутится индикатор.
      await tester.tap(find.text('Для экспериментатора'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('sno-archives-searching')), findsOneWidget);
      expect(find.byKey(const Key('sno-archives-empty')), findsNothing);

      scan.add(older);
      await tester.pump();
      await tester.pump();
      expect(listed(older), findsOneWidget);
      expect(find.byKey(const Key('sno-archives-searching')), findsOneWidget);

      // Архив новее найден позже — и встаёт в конец: строка, уже
      // стоящая на экране, из-под пальца не уезжает.
      final double before = tester.getTopLeft(listed(older)).dy;
      scan.add(found);
      await tester.pump();
      await tester.pump();
      expect(tester.getTopLeft(listed(older)).dy, before);
      expect(
        tester.getTopLeft(listed(found)).dy,
        greaterThan(tester.getTopLeft(listed(older)).dy),
      );

      // Обход кончился — список встаёт в свой порядок: новые сверху.
      await scan.close();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-archives-searching')), findsNothing);
      expect(
        tester.getTopLeft(listed(found)).dy,
        lessThan(tester.getTopLeft(listed(older)).dy),
      );

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-03: нажатие достаётся архиву, а не месту в списке', (
      WidgetTester tester,
    ) async {
      final List<PickedFile> unpacked = <PickedFile>[];
      final StreamController<FoundArchive> scan =
          StreamController<FoundArchive>();
      await pumpTesting(
        tester,
        testServices(
          data: data,
          archiveSearch: (List<String> roots) => scan.stream,
        ),
        unpack: recording(unpacked),
      );
      await tester.tap(find.text('Для экспериментатора'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      scan.add(older);
      await tester.pump();
      await tester.pump();

      // Палец лёг на архив, и, пока он не поднят, обход нашёл ещё один
      // и кончился: список встал в свой порядок, и на этом месте
      // теперь другой архив.
      final TestGesture finger = await tester.startGesture(
        tester.getCenter(listed(older)),
      );
      await tester.pump();
      scan.add(found);
      await scan.close();
      await tester.pump();
      await tester.pump();
      await finger.up();
      await tester.pumpAndSettle();

      expect(unpacked.map((PickedFile file) => file.name).toList(), <String>[
        'Старая литература.zip',
      ], reason: 'нажатие не должно достаться архиву, вставшему на это место');

      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-03: начатый раньше поиск новому не мешает', (
      WidgetTester tester,
    ) async {
      // Доступ спрашивается не мгновенно; пока первый поиск ждёт
      // ответа, экспериментатор начал второй.
      final _GatedAccess access = _GatedAccess();
      int searches = 0;
      await pumpTesting(
        tester,
        testServices(
          data: data,
          access: access,
          archiveSearch: (List<String> roots) {
            searches++;
            return Stream<FoundArchive>.fromIterable(<FoundArchive>[found]);
          },
        ),
      );
      await openExperimenter(tester);
      await tester.tap(find.byKey(const Key('sno-archives-refresh')));
      await tester.pump();
      expect(access.asked, hasLength(2));
      expect(searches, 0);

      // Ответы пришли оба — и первый поиск, уже отменённый вторым,
      // обхода не начинает: архив в списке один раз.
      access.asked[0].complete(StorageAccessState.granted);
      access.asked[1].complete(StorageAccessState.granted);
      await tester.pumpAndSettle();

      expect(searches, 1);
      expect(listed(found), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-03: «Искать заново» останавливает прежний обход', (
      WidgetTester tester,
    ) async {
      final StreamController<FoundArchive> first =
          StreamController<FoundArchive>();
      int searches = 0;
      await pumpTesting(
        tester,
        testServices(
          data: data,
          archiveSearch: (List<String> roots) {
            searches++;
            return searches == 1
                ? first.stream
                : Stream<FoundArchive>.fromIterable(<FoundArchive>[found]);
          },
        ),
      );
      await tester.tap(find.text('Для экспериментатора'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('sno-archives-searching')), findsOneWidget);

      // Первый обход ещё идёт, а экспериментатор начал новый.
      await tester.tap(find.byKey(const Key('sno-archives-refresh')));
      await tester.pumpAndSettle();
      expect(searches, 2);
      expect(first.hasListener, isFalse, reason: 'прежний обход остановлен');
      expect(listed(found), findsOneWidget);
      expect(find.byKey(const Key('sno-archives-searching')), findsNothing);

      // Не `await`: у отписанного потока «закрыто» приходит мимо
      // подменённого времени widget-теста.
      unawaited(first.close());
      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-03: раздел закрыли — обход остановлен', (
      WidgetTester tester,
    ) async {
      final StreamController<FoundArchive> scan =
          StreamController<FoundArchive>();
      await pumpTesting(
        tester,
        testServices(
          data: data,
          archiveSearch: (List<String> roots) => scan.stream,
        ),
      );
      await tester.tap(find.text('Для экспериментатора'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(scan.hasListener, isTrue);

      await unmount(tester);

      expect(scan.hasListener, isFalse);
      unawaited(scan.close());
    });

    testWidgets('SNO-F-LIT-03: «Искать заново» обходит устройство ещё раз', (
      WidgetTester tester,
    ) async {
      int searches = 0;
      await pumpTesting(
        tester,
        testServices(
          data: data,
          archiveSearch: (List<String> roots) {
            searches++;
            // Архив появился между обходами: его только что скачали.
            return Stream<FoundArchive>.fromIterable(<FoundArchive>[
              if (searches > 1) found,
            ]);
          },
        ),
      );
      await openExperimenter(tester);
      expect(searches, 1);
      expect(find.byKey(const Key('sno-archives-empty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sno-archives-refresh')));
      await tester.pumpAndSettle();

      expect(searches, 2);
      expect(find.text('Литература.zip'), findsOneWidget);
      expect(find.byKey(const Key('sno-archives-empty')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-03: оборванный обход назван, найденное остаётся', (
      WidgetTester tester,
    ) async {
      Stream<FoundArchive> broken(List<String> roots) async* {
        yield found;
        throw const ScanFailure('диск отвалился');
      }

      await pumpTesting(
        tester,
        testServices(data: data, archiveSearch: broken),
      );
      await openExperimenter(tester);

      expect(find.text('Литература.zip'), findsOneWidget);
      expect(find.byKey(const Key('sno-archives-failure')), findsOneWidget);
      expect(find.text('Поиск прервался: диск отвалился.'), findsOneWidget);
      // «Не найдено» здесь было бы неправдой: обход до конца не дошёл.
      expect(find.byKey(const Key('sno-archives-empty')), findsNothing);
      expect(find.byKey(const Key('sno-archives-searching')), findsNothing);
      expect(find.byKey(const Key('sno-archives-refresh')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-03: на ПК доступ не нужен и не просится', (
      WidgetTester tester,
    ) async {
      final FakeStorageAccess access = FakeStorageAccess(
        current: StorageAccessState.notRequired,
        paths: const <String>[r'C:\Users\Paul'],
      );
      await pumpTesting(
        tester,
        testServices(
          data: data,
          access: access,
          archives: <FoundArchive>[
            FoundArchive(
              path: r'C:\Users\Paul\Downloads\Литература.zip',
              size: 340 * 1024 * 1024,
              modifiedAt: DateTime.utc(2026, 10, 4, 12),
              books: 5,
            ),
          ],
        ),
      );
      await openExperimenter(tester);

      expect(access.requests, 0);
      expect(find.byKey(const Key('sno-archives-access')), findsNothing);
      expect(find.text('5 книг · 340 МБ · Downloads'), findsOneWidget);

      await unmount(tester);
    });
  });

  group('SNO-F-LIT-03: доступ к файлам на телефоне', () {
    testWidgets('SNO-F-LIT-03: без доступа обхода нет, запрос — по кнопке', (
      WidgetTester tester,
    ) async {
      int searches = 0;
      final FakeStorageAccess access = FakeStorageAccess(
        current: StorageAccessState.denied,
      );
      await pumpTesting(
        tester,
        testServices(
          data: data,
          access: access,
          archiveSearch: (List<String> roots) {
            searches++;
            return Stream<FoundArchive>.fromIterable(<FoundArchive>[found]);
          },
        ),
      );
      await openExperimenter(tester);

      // Раздел объясняет, зачем доступ, и сам ничего не спрашивает.
      expect(find.byKey(const Key('sno-archives-access')), findsOneWidget);
      expect(
        find.textContaining('Приложение ищет только ZIP-архивы с книгами.'),
        findsOneWidget,
      );
      expect(access.requests, 0);
      expect(searches, 0);
      // Искать заново нечем, а выбрать вручную можно.
      expect(find.byKey(const Key('sno-archives-refresh')), findsNothing);
      expect(find.byKey(const Key('sno-add-archive')), findsOneWidget);
      expect(find.byKey(const Key('sno-archives-empty')), findsNothing);

      await tester.tap(find.byKey(const Key('sno-archives-allow')));
      await tester.pumpAndSettle();
      expect(access.requests, 1);
      // Системный экран открыт, ответа ещё нет.
      expect(searches, 0);
      expect(find.byKey(const Key('sno-archives-access')), findsOneWidget);

      // Доступ дали и вернулись в приложение — обход пошёл сам.
      access.current = StorageAccessState.granted;
      await backToApp(tester);

      expect(searches, 1);
      expect(access.requests, 1);
      expect(find.byKey(const Key('sno-archives-access')), findsNothing);
      expect(find.text('Литература.zip'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-03: отказали — запрос сам не повторяется', (
      WidgetTester tester,
    ) async {
      final List<PickedFile> unpacked = <PickedFile>[];
      final FakeStorageAccess access = FakeStorageAccess(
        current: StorageAccessState.denied,
      );
      await pumpTesting(
        tester,
        testServices(data: data, access: access, picked: archive),
        unpack: recording(unpacked),
      );
      await openExperimenter(tester);

      await tester.tap(find.byKey(const Key('sno-archives-allow')));
      await tester.pumpAndSettle();
      // Вернулись, ничего не разрешив.
      await backToApp(tester);
      await backToApp(tester);

      expect(access.requests, 1, reason: 'приложение не настаивает');
      expect(find.byKey(const Key('sno-archives-access')), findsOneWidget);

      // Ручной выбор работает и без доступа.
      await tester.tap(find.byKey(const Key('sno-add-archive')));
      await tester.pumpAndSettle();
      expect(unpacked.single.name, 'Литература.zip');
      expect(find.byKey(const Key('sno-archive-report')), findsOneWidget);

      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-03: вернулись в приложение — обход не повторён', (
      WidgetTester tester,
    ) async {
      int searches = 0;
      await pumpTesting(
        tester,
        testServices(
          data: data,
          archiveSearch: (List<String> roots) {
            searches++;
            return const Stream<FoundArchive>.empty();
          },
        ),
      );
      await openExperimenter(tester);
      expect(searches, 1);

      // Доступ есть: возвращение из другого приложения ничего не меняет.
      await backToApp(tester);
      expect(searches, 1);

      await unmount(tester);
    });
  });

  group('SNO-F-LIT-02: свои PDF не добавляются', () {
    testWidgets('SNO-F-LIT-02: PDF вместо архива на полку не встаёт', (
      WidgetTester tester,
    ) async {
      final List<PickedFile> unpacked = <PickedFile>[];
      await pumpTesting(
        tester,
        testServices(
          data: data,
          picked: const PickedFile(
            name: 'Анатомия.PDF',
            path: '/picked/Анатомия.PDF',
          ),
          storage: const PathBytesStorage(),
        ),
        unpack: recording(unpacked),
      );
      await openExperimenter(tester);

      await tester.tap(find.byKey(const Key('sno-add-archive')));
      await tester.pumpAndSettle();

      expect(await data.library.books(), isEmpty);
      expect(unpacked, isEmpty, reason: 'книгу не пробуют и распаковать');
      expect(find.byKey(const Key('sno-archive-report')), findsOneWidget);
      expect(find.text('Книги добавляются архивом'), findsOneWidget);
      expect(
        find.textContaining('Не добавлено: «Анатомия.PDF».'),
        findsOneWidget,
      );
      expect(
        find.textContaining('только из архива с литературой'),
        findsOneWidget,
      );

      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-02: PDF и архив вместе — встаёт только архив', (
      WidgetTester tester,
    ) async {
      final List<PickedFile> unpacked = <PickedFile>[];
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
        unpack: recording(unpacked),
      );
      await openExperimenter(tester);

      await tester.tap(find.byKey(const Key('sno-add-archive')));
      await tester.pumpAndSettle();

      expect(await data.library.books(), isEmpty);
      expect(unpacked.single.name, 'Литература.zip');
      expect(find.text('Архив «Литература.zip»'), findsOneWidget);
      expect(
        find.textContaining('Не добавлено: «Гистология.pdf».'),
        findsOneWidget,
      );

      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-02: кнопка и подписи книг не обещают', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester, testServices(data: data));
      await openExperimenter(tester);

      expect(find.text('Выбрать вручную…'), findsOneWidget);
      expect(find.textContaining('Добавить книги'), findsNothing);
      expect(find.textContaining('PDF встают'), findsNothing);

      await unmount(tester);
    });

    test('SNO-F-LIT-02: книга узнаётся по имени файла', () {
      expect(isBookName('Анатомия.pdf'), isTrue);
      expect(isBookName('АНАТОМИЯ.PDF'), isTrue);
      expect(isBookName('Литература.zip'), isFalse);
      expect(isBookName('pdf'), isFalse);
      expect(isBookName('Литература.pdf.zip'), isFalse);
    });

    test('SNO-F-LIT-02: отказ называет книги и говорит, как надо', () {
      expect(
        describeRefusedBooks(<String>['Анатомия.pdf']),
        'Не добавлено: «Анатомия.pdf». В сборке для тестирования книги '
        'встают на полку только из архива с литературой.',
      );
      expect(
        describeRefusedBooks(<String>['А.pdf', 'Б.pdf']),
        startsWith('Не добавлено: «А.pdf», «Б.pdf». '),
      );
    });

    test('SNO-F-LIT-02: поимённо названы три книги, остальные числом', () {
      final String text = describeRefusedBooks(<String>[
        for (int i = 1; i <= 5; i++) 'Файл $i.pdf',
      ]);
      for (int i = 1; i <= kNamedFailures; i++) {
        expect(text, contains('«Файл $i.pdf»'));
      }
      expect(text, isNot(contains('«Файл 4.pdf»')));
      expect(text, contains(' и ещё 2. '));
    });
  });

  group('SNO-F-LIT-01: архив с книгами', () {
    Book shelved(String id, {String? categoryId}) {
      final Book book = testBook(id: id, hash: 'hash-$id');
      return categoryId == null ? book : book.copyWith(categoryId: categoryId);
    }

    testWidgets('SNO-F-LIT-01: архив распаковывается, итог — окном', (
      WidgetTester tester,
    ) async {
      final List<PickedFile> unpacked = <PickedFile>[];
      await pumpTesting(
        tester,
        testServices(data: data, picked: archive),
        unpack: recording(
          unpacked,
          report: (PickedFile file) => ArchiveReport(
            archive: file.name,
            total: 3,
            added: <Book>[
              shelved('a', categoryId: 'c1'),
              shelved('b', categoryId: 'c2'),
              shelved('c'),
            ],
            skipped: 2,
          ),
        ),
      );
      await openExperimenter(tester);

      await tester.tap(find.byKey(const Key('sno-add-archive')));
      await tester.pumpAndSettle();

      expect(unpacked.single.name, 'Литература.zip');
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
      // Распаковка закончилась — строки хода больше нет.
      expect(find.byKey(const Key('sno-archive-busy')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-01: диалог закрыли — ничего не случилось', (
      WidgetTester tester,
    ) async {
      final List<PickedFile> unpacked = <PickedFile>[];
      await pumpTesting(
        tester,
        testServices(data: data, batch: const <PickedFile>[]),
        unpack: recording(unpacked),
      );
      await openExperimenter(tester);

      await tester.tap(find.byKey(const Key('sno-add-archive')));
      await tester.pumpAndSettle();

      expect(unpacked, isEmpty);
      expect(find.byKey(const Key('sno-archive-report')), findsNothing);
      expect(find.byKey(const Key('sno-archive-busy')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-01: ход распаковки виден над списком', (
      WidgetTester tester,
    ) async {
      final Completer<void> gate = Completer<void>();
      await pumpTesting(
        tester,
        testServices(
          data: data,
          picked: archive,
          archives: <FoundArchive>[found],
        ),
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

      await tester.tap(find.byKey(const Key('sno-add-archive')));
      // Не `pumpAndSettle`: пока идёт распаковка, крутится индикатор.
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('sno-archive-busy')), findsOneWidget);
      expect(find.byKey(const Key('sno-archive-progress')), findsOneWidget);
      expect(find.text('Распаковываю архив: 12 из 34'), findsOneWidget);
      expect(find.text('Анатомия · Анатомия человека'), findsOneWidget);
      final LinearProgressIndicator bar = tester.widget(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(11 / 34, 1e-9));
      // Пока идёт первая распаковка, вторую начать нечем: ни ручным
      // выбором, ни из списка, ни новым обходом.
      final TextButton pick = tester.widget(
        find.byKey(const Key('sno-add-archive')),
      );
      expect(pick.onPressed, isNull);
      final TextButton refresh = tester.widget(
        find.byKey(const Key('sno-archives-refresh')),
      );
      expect(refresh.onPressed, isNull);
      final ListTile row = tester.widget(listed(found));
      expect(row.enabled, isFalse);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-archive-progress')), findsNothing);
      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-01: пока архив открывается, это и сказано', (
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
              await gate.future;
              return ArchiveReport(archive: file.name);
            },
      );
      await openExperimenter(tester);

      await tester.tap(find.byKey(const Key('sno-add-archive')));
      await tester.pump();
      await tester.pump();

      // До первой книги — не «0 из 0».
      expect(find.text('Открываю архив «Литература.zip»…'), findsOneWidget);
      expect(find.textContaining('Распаковываю'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-01: второе нажатие второй диалог не открывает', (
      WidgetTester tester,
    ) async {
      final AppServices base = testServices(data: data);
      final _HeldPicker picker = _HeldPicker();
      await pumpTesting(
        tester,
        AppServices(
          data: base.data,
          opener: base.opener,
          picker: picker,
          storage: base.storage,
          coverStore: base.coverStore,
          access: base.access,
          archiveSearch: base.archiveSearch,
          covers: base.covers,
          deviceLibrary: base.deviceLibrary,
        ),
      );
      await openExperimenter(tester);

      // Диалог ещё открыт, а кнопку нажали снова.
      await tester.tap(find.byKey(const Key('sno-add-archive')));
      await tester.tap(find.byKey(const Key('sno-add-archive')));
      await tester.pump();
      expect(picker.dialogs, hasLength(1));

      // Диалог закрыли — кнопка снова отвечает.
      picker.dialogs.single.complete(const <PickedFile>[]);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sno-add-archive')));
      await tester.pump();
      expect(picker.dialogs, hasLength(2));
      picker.dialogs.last.complete(const <PickedFile>[]);
      await tester.pumpAndSettle();

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-01: сбой распаковки итога не съедает', (
      WidgetTester tester,
    ) async {
      await pumpTesting(
        tester,
        testServices(data: data, picked: archive),
        unpack:
            (
              PickedFile file, {
              void Function(ArchiveProgress progress)? onProgress,
            }) async {
              throw StateError('непредвиденное');
            },
      );
      await openExperimenter(tester);

      await tester.tap(find.byKey(const Key('sno-add-archive')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Распаковка остановлена'), findsOneWidget);
      // И раздел не остался занятым.
      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-archive-busy')), findsNothing);
      final TextButton pick = tester.widget(
        find.byKey(const Key('sno-add-archive')),
      );
      expect(pick.onPressed, isNotNull);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-01: не-архив получает отказ от распаковки', (
      WidgetTester tester,
    ) async {
      final List<PickedFile> unpacked = <PickedFile>[];
      await pumpTesting(
        tester,
        testServices(
          data: data,
          // Архив без расширения — и любой другой файл не-книга: что
          // это, решает распаковка, а не имя.
          picked: const PickedFile(name: 'Литература', path: '/picked/x'),
        ),
        unpack: recording(
          unpacked,
          report: (PickedFile file) =>
              ArchiveReport(archive: file.name, refusal: 'это не ZIP-архив'),
        ),
      );
      await openExperimenter(tester);

      await tester.tap(find.byKey(const Key('sno-add-archive')));
      await tester.pumpAndSettle();

      expect(unpacked.single.name, 'Литература');
      expect(
        find.textContaining('Архив не добавлен: это не ZIP-архив.'),
        findsOneWidget,
      );
      expect(await data.library.books(), isEmpty);

      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-01: два архива — итог у каждого свой', (
      WidgetTester tester,
    ) async {
      final List<PickedFile> unpacked = <PickedFile>[];
      await pumpTesting(
        tester,
        testServices(
          data: data,
          batch: const <PickedFile>[
            archive,
            PickedFile(name: 'Ещё.zip', path: '/picked/Ещё.zip'),
          ],
        ),
        unpack: recording(
          unpacked,
          report: (PickedFile file) =>
              ArchiveReport(archive: file.name, total: 1, already: 1),
        ),
      );
      await openExperimenter(tester);

      await tester.tap(find.byKey(const Key('sno-add-archive')));
      await tester.pumpAndSettle();

      expect(unpacked, hasLength(2));
      expect(find.text('Архивы: 2'), findsOneWidget);
      expect(find.textContaining('«Литература.zip»'), findsOneWidget);
      expect(find.textContaining('«Ещё.zip»'), findsOneWidget);

      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
      await unmount(tester);
    });
  });

  group('SNO-F-CFG-04: эталонное состояние и сброс', () {
    // Экран высокий: блок «Для экспериментатора» виден целиком, и
    // кнопку сброса не надо искать прокруткой.
    void tall(WidgetTester tester) {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize =
          const Size(600, 1600) * tester.view.devicePixelRatio;
    }

    Future<void> pumpSection(
      WidgetTester tester, {
      ArchiveUnpack? unpack,
      VoidCallback? onStateReset,
      bool visible = true,
      PickedFile? picked,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TestingScreen(
            services: testServices(data: data, picked: picked),
            flags: BranchFlags.of('I'),
            unpack: unpack,
            visible: visible,
            onStateReset: onStateReset,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Полка из архива: категория и две книги в ней.
    Future<List<Book>> archiveShelf() async {
      await data.categories.save(
        BookCategory(
          id: 'lit',
          title: 'Литература',
          position: 0,
          createdAt: DateTime.utc(2026, 10, 4),
        ),
      );
      final List<Book> books = <Book>[
        testBook(id: 'a', hash: 'hash-a').copyWith(categoryId: 'lit'),
        testBook(
          id: 'b',
          title: 'Дубровский',
          hash: 'hash-b',
        ).copyWith(categoryId: 'lit', shelfPosition: 1),
      ];
      for (final Book book in books) {
        await data.library.save(book);
      }
      return books;
    }

    ReferenceKeeper keeper() {
      return ReferenceKeeper(data: data, storage: MemoryBookStorage());
    }

    /// Держит кнопку сброса [held] и отпускает.
    Future<void> holdReset(WidgetTester tester, Duration held) async {
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('sno-reset-hold'))),
      );
      // Нажатие узнаётся не сразу: рядом прокрутка списка.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(held);
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('SNO-F-CFG-04: эталона нет — сказано, кнопки сброса нет', (
      WidgetTester tester,
    ) async {
      tall(tester);
      await pumpSection(tester);
      await openExperimenter(tester);

      expect(find.byKey(const Key('sno-reference-none')), findsOneWidget);
      expect(find.textContaining('Эталона ещё нет'), findsOneWidget);
      expect(find.byKey(const Key('sno-reset-hold')), findsNothing);
      expect(find.byKey(const Key('sno-reference-status')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-04: разложенный архив запоминается эталоном', (
      WidgetTester tester,
    ) async {
      tall(tester);
      final List<Book> books = await archiveShelf();
      final List<PickedFile> unpacked = <PickedFile>[];
      await pumpSection(
        tester,
        picked: archive,
        unpack: recording(
          unpacked,
          report: (PickedFile file) =>
              ArchiveReport(archive: file.name, total: 2, added: books),
        ),
      );
      await openExperimenter(tester);
      expect(find.byKey(const Key('sno-reference-none')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sno-add-archive')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();

      // Кнопки «запомнить» нет: эталон — полка, какой её положил архив.
      expect(find.byKey(const Key('sno-reference-none')), findsNothing);
      expect(find.textContaining('Категорий: 1, книг: 2'), findsOneWidget);
      expect(find.text('Сейчас: совпадает с эталоном'), findsOneWidget);
      expect(find.byKey(const Key('sno-reset-hold')), findsOneWidget);
      final ReferenceState? stored = await keeper().reference();
      expect(stored!.shelf.categories, <String>['Литература']);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-04: удержание сбрасывает к эталону', (
      WidgetTester tester,
    ) async {
      tall(tester);
      await keeper().remember(await archiveShelf());
      // Следы тестировщика.
      await data.reading.savePosition(
        const ReadingPosition(bookId: 'a', page: 7),
      );
      await data.settings.write(SettingsKeys.theme, 'sepia');
      await placeBook(data, 'b', null);
      int resets = 0;
      await pumpSection(tester, onStateReset: () => resets++);
      await openExperimenter(tester);
      expect(find.text('Сейчас: отличается от эталона'), findsOneWidget);
      expect(find.byKey(const Key('sno-reset-last')), findsNothing);

      await holdReset(tester, kResetHold + const Duration(milliseconds: 100));

      expect(
        find.text('Сброшено. Состояние совпадает с эталоном.'),
        findsOneWidget,
      );
      expect(find.text('Сейчас: совпадает с эталоном'), findsOneWidget);
      expect(find.byKey(const Key('sno-reset-last')), findsOneWidget);
      expect(resets, 1, reason: 'оболочке сказано перечитать настройки');
      expect(await data.reading.position('a'), isNull);
      expect(await data.settings.read(SettingsKeys.theme), isNull);
      expect((await data.library.bookById('b'))!.categoryId, 'lit');

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-04: отпустили раньше — ничего не произошло', (
      WidgetTester tester,
    ) async {
      tall(tester);
      await keeper().remember(await archiveShelf());
      await data.reading.savePosition(
        const ReadingPosition(bookId: 'a', page: 7),
      );
      int resets = 0;
      await pumpSection(tester, onStateReset: () => resets++);
      await openExperimenter(tester);

      await holdReset(tester, const Duration(milliseconds: 900));

      expect(find.byKey(const Key('sno-reset-result')), findsNothing);
      expect(resets, 0);
      expect((await data.reading.position('a'))!.page, 7);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-04: пока идёт распаковка, сброс выключен', (
      WidgetTester tester,
    ) async {
      tall(tester);
      await keeper().remember(await archiveShelf());
      final Completer<void> gate = Completer<void>();
      await pumpSection(
        tester,
        picked: archive,
        unpack:
            (
              PickedFile file, {
              void Function(ArchiveProgress progress)? onProgress,
            }) async {
              await gate.future;
              return ArchiveReport(archive: file.name);
            },
      );
      await openExperimenter(tester);
      HoldToConfirmButton button() {
        return tester.widget(find.byKey(const Key('sno-reset-hold')));
      }

      expect(button().onConfirmed, isNotNull);

      await tester.tap(find.byKey(const Key('sno-add-archive')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('sno-archive-busy')), findsOneWidget);
      expect(button().onConfirmed, isNull);

      gate.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
      expect(button().onConfirmed, isNotNull);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-04: вернулись в раздел — сверка заново', (
      WidgetTester tester,
    ) async {
      tall(tester);
      await keeper().remember(await archiveShelf());
      await pumpSection(tester);
      await openExperimenter(tester);
      expect(find.text('Сейчас: совпадает с эталоном'), findsOneWidget);

      // Ушли читать — раздел остался жить в оболочке — и вернулись.
      await pumpSection(tester, visible: false);
      await data.reading.savePosition(
        const ReadingPosition(bookId: 'a', page: 7),
      );
      await pumpSection(tester);

      expect(find.text('Сейчас: отличается от эталона'), findsOneWidget);

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
        repeats: 1,
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
        'Одинаковых файлов в архиве: 1 — такая книга стоит на полке один раз.',
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

    test('SNO-F-LIT-01: причина движка сказана своими словами', () {
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
  });

  group('SNO-F-CFG-03: код устройства', () {
    test('SNO-F-CFG-03: первые шесть знаков идентификатора узла', () {
      expect(deviceCodeOf('a91f3c0b7d2e4f60a91f3c0b7d2e4f60'), 'a91f3c');
      expect(deviceCodeOf('a91f'), 'a91f');
      expect(deviceCodeOf(''), '');
    });
  });
}

/// Доступ к файлам, который отвечает, когда велит тест.
class _GatedAccess implements StorageAccess {
  /// Вопросы о состоянии, по порядку; тест отвечает на каждый сам.
  final List<Completer<StorageAccessState>> asked =
      <Completer<StorageAccessState>>[];

  @override
  Future<StorageAccessState> state() {
    final Completer<StorageAccessState> answer =
        Completer<StorageAccessState>();
    asked.add(answer);
    return answer.future;
  }

  @override
  Future<void> request() async {}

  @override
  Future<List<String>> roots() async => const <String>['/device'];
}

/// Диалог выбора, который остаётся открытым, пока тест его не закроет.
class _HeldPicker implements BookFilePicker {
  /// Открытые диалоги выбора архивов, по порядку.
  final List<Completer<List<PickedFile>>> dialogs =
      <Completer<List<PickedFile>>>[];

  @override
  Future<PickedFile?> pickPdf() async => null;

  @override
  Future<List<PickedFile>> pickPdfs() async => const <PickedFile>[];

  @override
  Future<List<PickedFile>> pickArchives() {
    final Completer<List<PickedFile>> dialog = Completer<List<PickedFile>>();
    dialogs.add(dialog);
    return dialog.future;
  }
}
