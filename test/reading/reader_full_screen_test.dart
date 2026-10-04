import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/reading/full_screen.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/infrastructure/platform/windows_full_screen.dart';
import 'package:memoria/ui/reader/reader_scaffold.dart';
import 'package:memoria/ui/reader/reader_screen.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/test_services.dart';

/// Файл, который переехал: книга ведёт на несуществующий путь.
const BookSource _gone = FilePathSource('/нет/такой/книги.pdf');

/// Файл, который читатель показывает заново.
const PickedFile _found = PickedFile(
  name: 'Онегин.pdf',
  path: '/книги/Онегин.pdf',
);

/// F-READ-35: чтение во весь экран на ПК.
///
/// Геометрия режима — полоса вплотную, указатель места не поверх
/// страницы — проверена числами в `sheet_placement_test` и
/// `progress_slot_test`, порядок `Esc` — в `reader_keys_test`. Здесь —
/// то, чего числами не проверить: что экран чтения разворачивает окно
/// кнопкой и клавишей, помнит режим и возвращает окно, закрывая книгу.
/// Само окно разворачивает `windows/runner`; здесь вместо него стоит
/// заглушка, а договор канала проверен отдельно.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppData data;
  late FakeFullScreenWindow window;

  setUp(() async {
    data = await openTestData();
    window = FakeFullScreenWindow();
  });
  tearDown(() async => data.close());

  /// Снимает дерево виджетов и даёт базе прибраться: живые запросы drift
  /// при отписке планируют уборку обычным таймером, а в widget-тестах
  /// время подменено, и оставшийся таймер валит тест.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpReader(
    WidgetTester tester, {
    Map<String, String> settings = const <String, String>{},
    bool hasWindow = true,
  }) async {
    for (final MapEntry<String, String> entry in settings.entries) {
      await data.settings.write(entry.key, entry.value);
    }
    final Book book = testBook();
    await data.library.save(book);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          book: book,
          services: testServices(
            data: data,
            document: FakeReaderDocument(
              pages: List<String>.generate(6, (int i) => 'страница ${i + 1}'),
            ),
            window: hasWindow ? window : const NoFullScreenWindow(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> showChrome(WidgetTester tester) async {
    tester
        .state<ReaderScaffoldState>(find.byType(ReaderScaffold))
        .toggleChrome();
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  final Finder button = find.byKey(const Key('reader-full-screen-button'));

  String tooltip(WidgetTester tester) =>
      tester.widget<IconButton>(button).tooltip!;

  Future<String?> remembered() =>
      data.settings.read(SettingsKeys.readingFullScreen);

  testWidgets('F-READ-35: кнопка разворачивает чтение и возвращает окно', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);
    await showChrome(tester);
    expect(window.full, isFalse);
    expect(tooltip(tester), 'Во весь экран (F11)');

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(window.full, isTrue);
    expect(tooltip(tester), 'Вернуть окно (F11)');
    expect(await remembered(), 'true');

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(window.full, isFalse);
    expect(tooltip(tester), 'Во весь экран (F11)');
    expect(await remembered(), 'false');

    await unmount(tester);
  });

  testWidgets('F-READ-35: F11 делает то же, что кнопка', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);

    await press(tester, LogicalKeyboardKey.f11);
    expect(window.full, isTrue);
    expect(await remembered(), 'true');

    await press(tester, LogicalKeyboardKey.f11);
    expect(window.full, isFalse);
    expect(window.requests, <bool>[true, false]);

    await unmount(tester);
  });

  testWidgets('F-READ-35: Esc возвращает окно, когда закрывать нечего', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);
    await press(tester, LogicalKeyboardKey.f11);
    expect(window.full, isTrue);

    // Панели на экране — первый Esc прячет их, окно остаётся.
    await showChrome(tester);
    await press(tester, LogicalKeyboardKey.escape);
    expect(window.full, isTrue);

    await press(tester, LogicalKeyboardKey.escape);
    expect(window.full, isFalse);
    expect(await remembered(), 'false');

    await unmount(tester);
  });

  testWidgets('F-READ-35: режим запоминается — книга открывается так же', (
    WidgetTester tester,
  ) async {
    await pumpReader(
      tester,
      settings: <String, String>{SettingsKeys.readingFullScreen: 'true'},
    );
    expect(window.requests, <bool>[true]);
    expect(window.full, isTrue);

    await showChrome(tester);
    expect(tooltip(tester), 'Вернуть окно (F11)');

    await unmount(tester);
  });

  testWidgets('F-READ-35: без записанного режима окно не трогается', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);
    expect(window.requests, isEmpty);

    await unmount(tester);
    expect(window.requests, isEmpty, reason: 'возвращать было нечего');
  });

  testWidgets('F-READ-35: закрытая книга возвращает окно, режим остаётся', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);
    await press(tester, LogicalKeyboardKey.f11);
    expect(window.full, isTrue);

    await unmount(tester);
    expect(window.full, isFalse, reason: 'на полке окно обычное');
    expect(await remembered(), 'true', reason: 'следующая книга — так же');
  });

  testWidgets('F-READ-35: платформа отказала — режим не включён', (
    WidgetTester tester,
  ) async {
    window.works = false;
    await pumpReader(tester);
    await showChrome(tester);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(window.requests, <bool>[true]);
    expect(window.full, isFalse);
    expect(tooltip(tester), 'Во весь экран (F11)');
    expect(await remembered(), isNull);

    await unmount(tester);
  });

  testWidgets('F-READ-35: книга не открылась — окно остаётся обычным', (
    WidgetTester tester,
  ) async {
    // Сообщение об ошибке во весь монитор ни к чему, а выйти из режима
    // оттуда было бы нечем: клавиши чтения живут на странице.
    await data.settings.write(SettingsKeys.readingFullScreen, 'true');
    // Отпечаток — как у файла, который покажут заново: перепривязка
    // сверяет их (BUG-19), и выдуманный был бы чужим файлом.
    final Book book = testBook(hash: await memoryBookHash())
        .copyWith(source: _gone);
    await data.library.save(book);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          book: book,
          services: AppServices(
            data: data,
            opener: _MissingThenFound(),
            picker: FakeBookFilePicker(_found),
            storage: MemoryBookStorage(),
            coverStore: MemoryCoverStore(),
            access: FakeStorageAccess(),
            window: window,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-failure-message')), findsOneWidget);
    expect(window.requests, isEmpty);

    // Файл показали заново, книга открылась — и выбор читателя в силе.
    await tester.tap(find.byKey(const Key('reader-relink')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-relink')), findsNothing);
    expect(window.requests, <bool>[true]);
    expect(window.full, isTrue);

    await unmount(tester);
  });

  testWidgets('F-READ-35: без окна нет ни кнопки, ни клавиши', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester, hasWindow: false);
    await showChrome(tester);
    expect(button, findsNothing);

    await press(tester, LogicalKeyboardKey.f11);
    expect(window.requests, isEmpty);

    await unmount(tester);
  });

  group('F-READ-35: канал окна Windows', () {
    const MethodChannel channel = MethodChannel('memoria/window');

    void answer(Future<Object?>? Function(MethodCall call)? handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
    }

    tearDown(() => answer(null));

    test('F-READ-35: платформе уходит, развернуть окно или вернуть', () async {
      final List<MethodCall> calls = <MethodCall>[];
      answer((MethodCall call) async {
        calls.add(call);
        return true;
      });
      final WindowsFullScreen window = WindowsFullScreen();

      expect(window.available, isTrue);
      expect(await window.setFullScreen(true), isTrue);
      expect(await window.setFullScreen(false), isTrue);
      expect(calls, hasLength(2));
      expect(calls.first.method, 'setFullScreen');
      expect(calls.first.arguments, true);
      expect(calls.last.arguments, false);
    });

    test('F-READ-35: отказ платформы — окно осталось каким было', () async {
      answer((MethodCall call) async => false);
      expect(await WindowsFullScreen().setFullScreen(true), isFalse);

      answer((MethodCall call) async {
        throw PlatformException(code: 'window');
      });
      expect(await WindowsFullScreen().setFullScreen(true), isFalse);
    });

    test('F-READ-35: канала нет — чтение идёт в окне', () async {
      expect(await WindowsFullScreen().setFullScreen(true), isFalse);
    });
  });
}

/// Открыватель, который в первый раз не находит файл, а потом находит.
class _MissingThenFound implements DocumentOpener {
  int _calls = 0;

  @override
  Future<ReaderDocument> open(BookSource source, {String? password}) async {
    _calls++;
    if (_calls == 1) {
      throw const DocumentOpenException(DocumentProblem.missing, _gone);
    }
    return FakeReaderDocument(pages: <String>['страница один']);
  }
}
