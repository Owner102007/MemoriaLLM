import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/ui/reader/selection_sheet.dart';

/// Рычаги слоя выделения.
///
/// Сам слой без настоящего PDFium не поднять, а вот правило, по которому
/// он показывается и гаснет, проверяется здесь: именно оно решает, ловит
/// ли слой указатель — то есть работают ли под ним зоны листания.
void main() {
  test('слой невидим, пока им не пользуются', () {
    final SelectionLayerController controller = SelectionLayerController();
    expect(controller.active, isFalse);
    controller.dispose();
  });

  test('жест поднимает слой и говорит об этом один раз', () {
    final SelectionLayerController controller = SelectionLayerController();
    int notices = 0;
    controller.addListener(() => notices++);

    controller.start(const Offset(10, 20), word: true);
    expect(controller.active, isTrue);
    expect(notices, 1);

    // Второе слово подряд — тот же слой: перестраивать дерево незачем.
    controller.start(const Offset(40, 20), word: true);
    expect(notices, 1);

    controller.dispose();
  });

  test('снятие выделения гасит слой', () {
    final SelectionLayerController controller = SelectionLayerController();
    int notices = 0;
    controller.addListener(() => notices++);

    controller.start(const Offset(10, 20), word: true);
    controller.dismiss();
    expect(controller.active, isFalse);
    expect(notices, 2);

    // Снимать нечего — и говорить не о чем.
    controller.dismiss();
    expect(notices, 2);

    controller.dispose();
  });

  test('невидимый слой не рисуется вовсе — и это надо было обойти', () {
    // `Opacity(0)` в Flutter пропускает отрисовку ребёнка целиком, а
    // pdfrx просит растр страницы именно из неё. Слой с нулевой
    // прозрачностью так и остался бы пустым до первого жеста — и
    // моргание, ради которого всё затевалось, никуда бы не делось.
    expect(kSelectionLayerWarmOpacity, greaterThan(0));
    expect(
      (kSelectionLayerWarmOpacity * 255).round(),
      greaterThanOrEqualTo(1),
      reason: 'альфа обязана округляться хотя бы до единицы',
    );
    // И при этом остаться неотличимой от нуля глазом.
    expect((kSelectionLayerWarmOpacity * 255).round(), lessThanOrEqualTo(2));
  });
}
