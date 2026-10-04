import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/reading/volume_keys.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/ui/reader/reader_scaffold.dart';
import 'package:memoria/ui/reader/reader_screen.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/test_services.dart';

/// F-READ-26: экран чтения и кнопки громкости.
///
/// Правило «листать или менять громкость» проверено числами в
/// `volume_keys_test`. Здесь — то, чего числами не проверить: что экран
/// включает перехват, только пока читатель смотрит на страницу, и что
/// нажатие в самом деле листает книгу.
void main() {
  late AppData data;
  late FakeVolumeKeys keys;

  setUp(() async {
    data = await openTestData();
    keys = FakeVolumeKeys();
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
    bool screenReader = false,
  }) async {
    for (final MapEntry<String, String> entry in settings.entries) {
      await data.settings.write(entry.key, entry.value);
    }
    final Book book = testBook();
    await data.library.save(book);
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(accessibleNavigation: screenReader),
          child: child!,
        ),
        home: ReaderScreen(
          book: book,
          services: testServices(
            data: data,
            document: FakeReaderDocument(
              pages: List<String>.generate(6, (int i) => 'страница ${i + 1}'),
            ),
            volumeKeys: keys,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String label(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('reader-page-label'))).data!;

  Future<void> showChrome(WidgetTester tester) async {
    tester
        .state<ReaderScaffoldState>(find.byType(ReaderScaffold))
        .toggleChrome();
    await tester.pumpAndSettle();
  }

  testWidgets('F-READ-26: короткое нажатие листает книгу', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);

    expect(keys.attached, isTrue);
    expect(keys.active, isTrue);
    expect(label(tester), '1 / 6');

    // «Тише» — вперёд, «громче» — назад.
    expect(keys.click(VolumeKey.down), VolumeKeyOutcome.forward);
    await tester.pumpAndSettle();
    expect(label(tester), '2 / 6');

    expect(keys.click(VolumeKey.down), VolumeKeyOutcome.forward);
    await tester.pumpAndSettle();
    expect(label(tester), '3 / 6');

    expect(keys.click(VolumeKey.up), VolumeKeyOutcome.back);
    await tester.pumpAndSettle();
    expect(label(tester), '2 / 6');

    await unmount(tester);
  });

  testWidgets('F-READ-26: удержание меняет громкость, страница на месте', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);

    const VolumeKey key = VolumeKey.down;
    expect(
      keys.send(const VolumeKeyEvent(key: key, pressed: true)),
      VolumeKeyOutcome.none,
    );
    for (int repeat = 1; repeat <= 4; repeat++) {
      expect(
        keys.send(VolumeKeyEvent(key: key, pressed: true, repeat: repeat)),
        VolumeKeyOutcome.lower,
      );
    }
    expect(
      keys.send(const VolumeKeyEvent(key: key, pressed: false)),
      VolumeKeyOutcome.none,
    );
    await tester.pumpAndSettle();
    expect(label(tester), '1 / 6');

    await unmount(tester);
  });

  testWidgets('F-READ-26: перевёрнутое направление берётся из настроек', (
    WidgetTester tester,
  ) async {
    await pumpReader(
      tester,
      settings: <String, String>{SettingsKeys.volumeDownForward: 'false'},
    );

    expect(keys.click(VolumeKey.up), VolumeKeyOutcome.forward);
    await tester.pumpAndSettle();
    expect(label(tester), '2 / 6');

    expect(keys.click(VolumeKey.down), VolumeKeyOutcome.back);
    await tester.pumpAndSettle();
    expect(label(tester), '1 / 6');

    await unmount(tester);
  });

  testWidgets('F-READ-26: выключено в настройках — перехвата нет', (
    WidgetTester tester,
  ) async {
    await pumpReader(
      tester,
      settings: <String, String>{SettingsKeys.volumeKeys: 'false'},
    );

    expect(keys.active, isFalse);
    expect(keys.switches, isNot(contains(true)));

    await unmount(tester);
  });

  testWidgets('F-READ-26: при экранном дикторе перехвата нет', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester, screenReader: true);

    expect(keys.active, isFalse);
    expect(keys.switches, isNot(contains(true)));

    await unmount(tester);
  });

  testWidgets('F-READ-26: под шторкой настроек кнопки — снова громкость', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);
    expect(keys.active, isTrue);

    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-settings-button')));
    await tester.pumpAndSettle();

    expect(keys.active, isFalse);
    // Событие, которое успело прийти, книгу не листает.
    expect(
      keys.send(const VolumeKeyEvent(key: VolumeKey.down, pressed: true)),
      VolumeKeyOutcome.lower,
    );
    expect(
      keys.send(const VolumeKeyEvent(key: VolumeKey.down, pressed: false)),
      VolumeKeyOutcome.none,
    );
    await tester.pumpAndSettle();
    expect(label(tester), '1 / 6');

    // Шторку закрыли — кнопки снова листают.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(keys.active, isTrue);

    await unmount(tester);
  });

  testWidgets('F-TEXT-12: поиск страницу не закрывает — кнопки листают', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);
    await showChrome(tester);

    await tester.tap(find.byKey(const Key('reader-search-button')));
    await tester.pumpAndSettle();
    // Узкий экран, читатель набирает запрос: панель — полоса у нижнего
    // края, страница видна, и перехват кнопок остаётся. Прежде панель
    // закрывала страницу целиком, и кнопки меняли громкость.
    expect(find.byKey(const Key('search-panel')), findsOneWidget);
    expect(keys.active, isTrue);

    // Найденного нет — перебирать нечего, и кнопки листают, как всегда.
    expect(keys.click(VolumeKey.down), VolumeKeyOutcome.forward);
    await tester.pumpAndSettle();
    expect(label(tester), '2 / 6');

    // Панель — не маршрут: её закрывает сам экран чтения.
    tester
        .state<ReaderScaffoldState>(find.byType(ReaderScaffold))
        .closeSearch();
    await tester.pumpAndSettle();
    expect(keys.active, isTrue);

    await unmount(tester);
  });

  testWidgets('F-READ-26: книгу закрыли — получателя и перехвата нет', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);
    expect(keys.active, isTrue);

    await unmount(tester);

    expect(keys.attached, isFalse);
    expect(keys.active, isFalse);
    expect(keys.click(VolumeKey.down), isNull);
  });
}
