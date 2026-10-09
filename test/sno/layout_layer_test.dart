import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/prompts/selection_prompt.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/layout_frames.dart';
import 'package:memoria/sno/recording/layout_probe.dart';
import 'package:memoria/sno/recording/recording_overlay.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/ui/reader/selection_panel.dart';

import '../support/recording_fakes.dart';

/// Шаг 30, SNO-F-REC-03, SNO-ALG-REC-02: кадры раскладки на настоящем
/// экране под слоем записи.
///
/// Экран-заглушка: место под страницу с листом внутри, панель, которая
/// выезжает сверху, кнопка, открывающая диалог, и второй экран поверх
/// первого. Сессия — на памяти и подменённом времени. Проверяется, что
/// кадры ложатся, когда раскладка меняется, и только тогда; что в них
/// лежат видимые зоны с их местом в окне и порядком наложения, а
/// невидимых нет; что касание, принятое страницей, лежит в её зоне.
void main() {
  late SessionKit kit;
  late ValueNotifier<bool> chrome;
  int pageTaps = 0;
  int panelTaps = 0;

  final ParticipantCode code = ParticipantCode(
    code: kTestCode,
    generated: true,
    generatedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
  );

  setUp(() {
    kit = SessionKit();
    chrome = ValueNotifier<bool>(false);
    pageTaps = 0;
    panelTaps = 0;
  });
  tearDown(() {
    kit.session.dispose();
    chrome.dispose();
  });

  /// Лист: страница 600×800 пунктов в масштабе 0,5 со сдвигом 20, 10 —
  /// на своём месте; место листа отступает от края окна на 100, 50.
  SheetGeometry sheet() {
    return sheetGeometry(
      pages: const <({int page, double width, double height})>[
        (page: 3, width: 600, height: 800),
      ],
      scale: 0.5,
      left: 20,
      top: 10,
      strip: const SheetBox(0, 0.25, 1, 0.75),
      stripIndex: 2,
      strips: 2,
    );
  }

  Widget screen() {
    return Scaffold(
      body: Builder(
        builder: (BuildContext context) {
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: LayoutProbe(
                  kind: LayoutKind.page,
                  child: GestureDetector(
                    key: const Key('page'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => pageTaps++,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 100, top: 50),
                      child: LayoutSheetProbe(geometry: sheet),
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: chrome,
                builder: (BuildContext context, bool shown, Widget? child) {
                  return Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 180),
                      offset: shown ? Offset.zero : const Offset(0, -1),
                      child: LayoutProbe(
                        kind: LayoutKind.panelTop,
                        active: shown,
                        child: SizedBox(
                          height: 56,
                          child: TextButton(
                            key: const Key('panel'),
                            onPressed: () => panelTaps++,
                            child: const Text('панель'),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: TextButton(
                  key: const Key('open-dialog'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (BuildContext context) => const LayoutProbe(
                      kind: LayoutKind.dialog,
                      id: 'note',
                      child: AlertDialog(content: Text('заметка')),
                    ),
                  ),
                  child: const Text('диалог'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> pumpOverlay(WidgetTester tester, {Widget? home}) async {
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (BuildContext context, Widget? page) {
          return RecordingOverlay(
            session: kit.session,
            navigator: navigator,
            child: page!,
          );
        },
        home: home ?? screen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpRecording(WidgetTester tester, {Widget? home}) async {
    await pumpOverlay(tester, home: home);
    await kit.session.start(code);
    await tester.pump();
    // Первый кадр записи ложится устоявшимся, когда простоял.
    await tester.pump(const Duration(milliseconds: 150));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Кадры, как они лежат «на диске».
  Future<List<Map<String, Object?>>> frames(WidgetTester tester) async {
    kit.session.tick();
    await tester.pump();
    return kit.store.layoutLines(kit.folder);
  }

  LayoutFrame last(List<Map<String, Object?>> lines) {
    return LayoutFrame.fromJson(lines.last)!;
  }

  List<String> kindsOf(LayoutFrame frame) => <String>[
    for (final LayoutRegion region in frame.regions) region.kind.wire,
  ];

  group('SNO-F-REC-03: слой есть только во время записи', () {
    testWidgets('SNO-F-REC-03: записи нет — слой не слушает кадры, и '
        'кадров нет', (WidgetTester tester) async {
      await pumpOverlay(tester);

      expect(LayoutLayer.listening, 0);
      chrome.value = true;
      await tester.pump(const Duration(milliseconds: 300));
      expect(kit.store.layouts, isEmpty);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-03: слой заводит старт записи и снимает её '
        'остановка', (WidgetTester tester) async {
      await pumpRecording(tester);
      expect(LayoutLayer.listening, 1);

      await kit.session.stop(StopReason.experimenter);
      await tester.pump();
      expect(LayoutLayer.listening, 0);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-03: слой сняли посреди записи — слушателей не '
        'осталось', (WidgetTester tester) async {
      await pumpRecording(tester);

      await unmount(tester);

      expect(LayoutLayer.listening, 0);
    });
  });

  group('SNO-F-REC-03: что лежит в кадре', () {
    testWidgets('SNO-F-REC-03: первый кадр записи — устоявшийся: окно, '
        'место под страницу, лист и точка записи поверх всего', (
      WidgetTester tester,
    ) async {
      await pumpRecording(tester);

      final List<Map<String, Object?>> lines = await frames(tester);
      expect(lines, hasLength(1));
      expect(lines.single['n'], 1);
      expect(lines.single['moving'], isFalse);
      final LayoutFrame frame = last(lines);
      expect(frame.viewport.width, 800);
      expect(frame.viewport.height, 600);
      // Скрытой панели в кадре нет.
      expect(kindsOf(frame), <String>['page', 'recording_dot']);
      expect(frame.regions.first.rect, const LayoutRect(0, 0, 800, 600));
      expect(frame.regions.last.z, greaterThan(frame.regions.first.z));
      // Лист — в окне: место листа отступает на 100, 50.
      final LayoutPage page = frame.sheet!.pages.single;
      expect(page.page, 3);
      expect(page.x, closeTo(120, 0.05));
      expect(page.y, closeTo(60, 0.05));
      expect(frame.sheet!.scale, closeTo(0.5, 1e-5));
      expect(frame.sheet!.strip.top, closeTo(160, 0.05));

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-03: ничего не меняется — кадров нет', (
      WidgetTester tester,
    ) async {
      await pumpRecording(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(await frames(tester), hasLength(1));

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-03: панель выезжает — кадр «в движении» в '
        'начале и один устоявшийся в конце', (WidgetTester tester) async {
      await pumpRecording(tester);

      chrome.value = true;
      for (int i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 150));

      final List<Map<String, Object?>> lines = await frames(tester);
      final List<Map<String, Object?>> moving = <Map<String, Object?>>[
        for (final Map<String, Object?> line in lines.skip(1))
          if (line['moving'] == true) line,
      ];
      final List<Map<String, Object?>> settled = <Map<String, Object?>>[
        for (final Map<String, Object?> line in lines.skip(1))
          if (line['moving'] == false) line,
      ];
      expect(moving, isNotEmpty);
      // Не чаще пяти в секунду: анимация 180 мс — не больше двух.
      expect(moving.length, lessThanOrEqualTo(2));
      expect(settled, hasLength(1));
      expect(identical(lines.last, settled.single), isTrue);
      final LayoutFrame frame = last(lines);
      expect(kindsOf(frame), <String>['page', 'panel_top', 'recording_dot']);
      expect(frame.regions[1].rect, const LayoutRect(0, 0, 800, 56));

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-03: диалог — зона выше страницы', (
      WidgetTester tester,
    ) async {
      await pumpRecording(tester);

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 150));

      final LayoutFrame frame = last(await frames(tester));
      final LayoutRegion page = frame.regions.firstWhere(
        (LayoutRegion region) => region.kind == LayoutKind.page,
      );
      final LayoutRegion dialog = frame.regions.firstWhere(
        (LayoutRegion region) => region.kind == LayoutKind.dialog,
      );
      expect(dialog.id, 'note');
      expect(dialog.z, greaterThan(page.z));
      expect(frame.locate(400, 300).zone, 'dialog');

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-03: экран под другим маршрутом в кадр не '
        'попадает', (WidgetTester tester) async {
      await pumpRecording(tester);

      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator),
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => const LayoutProbe(
              kind: LayoutKind.screen,
              id: 'второй',
              child: Scaffold(body: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 150));

      final LayoutFrame frame = last(await frames(tester));
      expect(kindsOf(frame), <String>['screen', 'recording_dot']);
      expect(frame.regions.first.id, 'второй');
      expect(frame.sheet, isNull);

      await unmount(tester);
    });
  });

  group('SNO-F-REC-03: касание и кадр сходятся', () {
    testWidgets('SNO-F-REC-03: касание, принятое страницей, лежит в зоне '
        'страницы и на листе; принятое панелью — в зоне панели', (
      WidgetTester tester,
    ) async {
      await pumpRecording(tester);
      chrome.value = true;
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 150));

      await tester.tapAt(const Offset(300, 300));
      await tester.tap(find.byKey(const Key('panel')));
      await tester.pump();
      expect(pageTaps, 1);
      expect(panelTaps, 1);

      kit.session.tick();
      await tester.pump();
      final List<Map<String, Object?>> taps = kit.store.inputLines(kit.folder);
      expect(taps, hasLength(2));
      final LayoutFrame frame = last(await frames(tester));
      final LayoutHit onPage = frame.locate(
        (taps[0]['x']! as num).toDouble(),
        (taps[0]['y']! as num).toDouble(),
      );
      expect(onPage.zone, 'page');
      expect(onPage.page, 3);
      // (300 − 120) / 0,5 = 360 пунктов, (300 − 60) / 0,5 = 480.
      expect(onPage.xPt, closeTo(360, 0.2));
      expect(onPage.yPt, closeTo(480, 0.2));
      expect(onPage.dimmed, isFalse);
      final LayoutHit onPanel = frame.locate(
        (taps[1]['x']! as num).toDouble(),
        (taps[1]['y']! as num).toDouble(),
      );
      expect(onPanel.zone, 'panel_top');

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-03: панель над выделением — зона ровно по своей '
        'панели, а не по всему листу', (WidgetTester tester) async {
      await pumpRecording(
        tester,
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              const Positioned.fill(
                child: LayoutProbe(
                  kind: LayoutKind.page,
                  child: SizedBox.expand(),
                ),
              ),
              Positioned.fill(
                child: SelectionPanel(
                  anchor: const Rect.fromLTWH(300, 300, 120, 20),
                  prompts: PromptSet.empty,
                  onPrompt: (SelectionPrompt prompt) {},
                  onQuote: () {},
                  onNote: () {},
                  onCopy: () {},
                ),
              ),
            ],
          ),
        ),
      );

      final LayoutFrame frame = last(await frames(tester));
      final LayoutRegion panel = frame.regions.firstWhere(
        (LayoutRegion region) => region.kind == LayoutKind.selectionPanel,
      );
      final Rect drawn = tester.getRect(
        find.byKey(const Key('selection-panel')),
      );
      expect(panel.rect.left, closeTo(drawn.left, 0.06));
      expect(panel.rect.top, closeTo(drawn.top, 0.06));
      expect(panel.rect.width, closeTo(drawn.width, 0.06));
      expect(panel.rect.height, closeTo(drawn.height, 0.06));
      expect(panel.z, greaterThan(frame.regions.first.z));

      await unmount(tester);
    });
  });
}
