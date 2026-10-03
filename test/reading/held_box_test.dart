import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/ui/reader/held_box.dart';

/// Считает, сколько раз его создавали заново.
class _Probe extends StatefulWidget {
  const _Probe({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      key: Key('sheet'),
      color: Color(0xFF101010),
      child: SizedBox.expand(),
    );
  }
}

/// F-DESK-02: пока окно на ПК тянут, лист держится в прежнем размере.
void main() {
  late int created;

  setUp(() => created = 0);

  /// Окно размера [window], в нём лист, который держат в размере [held].
  Widget windowOf(Size window, Size held) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: const Key('window'),
          width: window.width,
          height: window.height,
          child: HeldBox(
            size: held,
            child: _Probe(onInit: () => created++),
          ),
        ),
      ),
    );
  }

  final Finder sheet = find.byKey(const Key('sheet'));
  const Size small = Size(400, 300);
  const Size big = Size(640, 480);
  const Size tiny = Size(200, 120);

  Future<void> show(WidgetTester tester, {required Size window, Size? held}) {
    return tester.pumpWidget(windowOf(window, held ?? window));
  }

  testWidgets('F-DESK-02: окно растёт, а лист стоит как стоял', (
    WidgetTester tester,
  ) async {
    await show(tester, window: small);
    expect(tester.getSize(sheet), small);

    await show(tester, window: big, held: small);

    expect(tester.getSize(sheet), small);
    // У левого верхнего угла, а не посередине: страница не едет за
    // краем окна, пока его тянут.
    expect(tester.getTopLeft(sheet), Offset.zero);
    expect(tester.getSize(find.byKey(const Key('window'))), big);
  });

  testWidgets('F-DESK-02: окно сжимается — лист обрезан, а не сжат', (
    WidgetTester tester,
  ) async {
    await show(tester, window: small);

    await show(tester, window: tiny, held: small);

    expect(tester.getSize(sheet), small);
    expect(tester.getTopLeft(sheet), Offset.zero);
    // Что вышло за окно, обрезано его краем.
    expect(find.byType(ClipRect), findsOneWidget);
  });

  testWidgets('F-DESK-02: принятый размер перекладывает лист', (
    WidgetTester tester,
  ) async {
    await show(tester, window: small);
    await show(tester, window: big, held: small);

    await show(tester, window: big);

    expect(tester.getSize(sheet), big);
  });

  testWidgets('F-DESK-02: то, что держат, не создаётся заново', (
    WidgetTester tester,
  ) async {
    // Под держателем лежит просмотрщик книги: пересоздать его значило бы
    // показать белый лист и потерять место.
    await show(tester, window: small);
    await show(tester, window: big, held: small);
    await show(tester, window: big);
    await show(tester, window: tiny, held: big);
    await show(tester, window: tiny);

    expect(created, 1);
  });
}
