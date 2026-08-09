import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/reading/reader_controller.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/sheet_placement.dart';
import 'package:memoria/domain/reading/text_geometry.dart';
import 'package:memoria/ui/reader/reader_settings_sheet.dart';

import '../support/fake_reading.dart';

/// Панель настроек проверяется на хранилище в памяти, а не на базе:
/// живые запросы drift оставляют после себя таймер, а в widget-тестах
/// время подменено, и тест падает на ровном месте (находка S3).
void main() {
  late FakeReadingRepository reading;
  late FakeReaderDocument document;
  late ReaderController controller;
  PageFlow? pickedFlow;
  PageDisplayMode? pickedMode;
  bool? pickedSnapBack;

  ReaderController build({Map<int, List<TextBox>>? boxes}) {
    document = FakeReaderDocument(
      pages: List<String>.filled(6, 'текст'),
      boxes: boxes ?? const <int, List<TextBox>>{},
    );
    reading = FakeReadingRepository();
    pickedFlow = null;
    pickedMode = null;
    pickedSnapBack = null;
    return controller = ReaderController(
      book: fakeBook(pageCount: 6),
      document: document,
      reading: reading,
    );
  }

  tearDown(() async {
    await controller.close();
    controller.dispose();
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    VoidCallback? onEditCrop,
    PageFlow flow = PageFlow.paged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderSettingsSheet(
            controller: controller,
            flow: flow,
            snapBack: true,
            onSnapBack: (bool value) => pickedSnapBack = value,
            onFlow: (PageFlow value) => pickedFlow = value,
            onDisplayMode: (PageDisplayMode mode) {
              pickedMode = mode;
              unawaited(controller.setDisplayMode(mode));
            },
            onEditCrop: onEditCrop ?? () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Панель длиннее тестового экрана: до нижних переключателей надо
  /// сперва домотать, иначе нажатие уходит в пустоту и тест падает так,
  /// будто сломана сама кнопка.
  Future<void> tapKey(WidgetTester tester, String key) async {
    final Finder finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('режим отображения переключается и запоминается', (
    WidgetTester tester,
  ) async {
    build();
    await pumpSheet(tester);

    await tapKey(tester, 'reader-mode-half');

    // Режим меняет экран, а не панель: вместе с ним поворачивается чтение.
    expect(pickedMode, PageDisplayMode.half);
    expect(controller.settings.displayMode, PageDisplayMode.half);
    final BookReadingSettings saved = await reading.settings(
      controller.book.id,
      ScreenOrientation.portrait,
    );
    expect(saved.displayMode, PageDisplayMode.half);
  });

  testWidgets('выбранный фильтр сразу получает заметную силу', (
    WidgetTester tester,
  ) async {
    build();
    await pumpSheet(tester);

    await tapKey(tester, 'reader-filter-nightRed');

    expect(controller.settings.filter, ReadingFilter.nightRed);
    expect(controller.settings.filterIntensity, greaterThanOrEqualTo(0.5));
    // Ползунок силы появляется только когда есть чему быть сильным.
    expect(find.byKey(const Key('reader-filter-intensity')), findsOneWidget);
  });

  testWidgets('ползунка силы нет, пока нет фильтра', (
    WidgetTester tester,
  ) async {
    build();
    await pumpSheet(tester);
    expect(find.byKey(const Key('reader-filter-intensity')), findsNothing);
  });

  testWidgets('автообрезка выключена по умолчанию и включается', (
    WidgetTester tester,
  ) async {
    build();
    await pumpSheet(tester);

    // Поля по умолчанию не режутся: страница показывается как свёрстана.
    expect(controller.settings.autoCrop, isFalse);
    // Пока обрезки нет, настраивать колонтитулы нечего.
    final SwitchListTile off = tester.widget(
      find.byKey(const Key('reader-runningheads-switch')),
    );
    expect(off.onChanged, isNull);

    await tapKey(tester, 'reader-autocrop-switch');
    expect(controller.settings.autoCrop, isTrue);

    final SwitchListTile on = tester.widget(
      find.byKey(const Key('reader-runningheads-switch')),
    );
    expect(on.onChanged, isNotNull);
  });

  testWidgets('ручная правка рамки открывается кнопкой', (
    WidgetTester tester,
  ) async {
    build();
    bool asked = false;
    await pumpSheet(tester, onEditCrop: () => asked = true);

    await tapKey(tester, 'reader-edit-crop');

    expect(asked, isTrue);
  });

  testWidgets('кнопка сброса рамки появляется только при ручной рамке', (
    WidgetTester tester,
  ) async {
    build();
    await pumpSheet(tester);
    expect(find.byKey(const Key('reader-reset-crop')), findsNothing);

    await controller.setManualCrop(
      const CropBox(left: 0.2, top: 0.2, right: 0.8, bottom: 0.8),
    );
    await tester.pump();
    expect(find.byKey(const Key('reader-reset-crop')), findsOneWidget);

    await tapKey(tester, 'reader-reset-crop');
    expect(controller.settings.manualCrop, isNull);
  });

  testWidgets('про двухколоночную страницу сказано прямо', (
    WidgetTester tester,
  ) async {
    build(
      boxes: <int, List<TextBox>>{
        1: <TextBox>[
          ...textBlock(
            left: 0.08,
            top: 0.1,
            right: 0.46,
            bottom: 0.9,
            lines: 20,
            charsPerLine: 15,
          ),
          ...textBlock(
            left: 0.54,
            top: 0.1,
            right: 0.92,
            bottom: 0.9,
            lines: 20,
            charsPerLine: 15,
          ),
        ],
      },
    );
    await controller.loadFrame();
    await pumpSheet(tester);

    expect(find.byKey(const Key('reader-columns-hint')), findsOneWidget);
  });

  testWidgets('способ листания переехал в настройки', (
    WidgetTester tester,
  ) async {
    build();
    await pumpSheet(tester);

    await tapKey(tester, 'reader-flow-continuous');

    expect(pickedFlow, PageFlow.continuous);
  });

  testWidgets('возврат масштаба выключается', (WidgetTester tester) async {
    build();
    await pumpSheet(tester);

    await tapKey(tester, 'reader-snapback-switch');
    expect(pickedSnapBack, isFalse);
  });

  testWidgets('сказано, зачем режимы поворачивают экран', (
    WidgetTester tester,
  ) async {
    build();
    await pumpSheet(tester);
    expect(find.byKey(const Key('reader-mode-hint')), findsOneWidget);
  });

  testWidgets('яркость, контраст и гамма меняются ползунками', (
    WidgetTester tester,
  ) async {
    build();
    await pumpSheet(tester);

    // Панель длиннее тестового экрана, и ползунки лежат ниже его края:
    // без прокрутки жест уходит в пустоту, а тест падает так, будто
    // сломан сам ползунок.
    Future<void> slide(String key, Offset by) async {
      final Finder finder = find.byKey(Key(key));
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.drag(finder, by);
      await tester.pump();
    }

    await slide('reader-brightness', const Offset(-80, 0));
    expect(controller.settings.brightness, lessThan(1));

    await slide('reader-contrast', const Offset(60, 0));
    expect(controller.settings.contrast, greaterThan(1));
  });

  testWidgets('запас по краям есть в панели и меняется ползунком', (
    WidgetTester tester,
  ) async {
    build();
    await pumpSheet(tester);

    // Щипок на странице — главный способ, но найти его читатель должен
    // не наугад: в панели про него написано, и то же самое делает ползунок.
    expect(find.byKey(const Key('reader-strip-fit-hint')), findsOneWidget);
    expect(controller.settings.stripFit, 1);

    final Finder slider = find.byKey(const Key('reader-strip-fit'));
    await tester.ensureVisible(slider);
    await tester.pump();
    await tester.drag(slider, const Offset(-120, 0));
    await tester.pump();

    expect(controller.settings.stripFit, lessThan(1));
    expect(controller.settings.stripFit, greaterThanOrEqualTo(kMinStripFit));
  });
}
