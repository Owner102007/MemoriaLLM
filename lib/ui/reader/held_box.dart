import 'package:flutter/widgets.dart';

/// Держит [child] в размере [size], каким бы ни стало место вокруг.
///
/// F-DESK-02: пока окно на ПК тянут за край, лист остаётся в прежнем
/// размере — стоит у левого верхнего угла и не перекладывается. Окно
/// стало больше — вокруг листа видно фон; стало меньше — лист обрезан
/// краем окна. Растягивать готовую картинку страницы под каждый
/// промежуточный размер незачем: настоящий размер придёт, когда окно
/// отпустят, и лист переложат один раз.
///
/// Когда [size] равен месту вокруг, виджет ничего не меняет. Дерево при
/// этом одно и то же в обоих случаях — иначе просмотрщик под ним
/// пересоздавался бы на каждом переходе «держим — не держим».
class HeldBox extends StatelessWidget {
  /// Создаёт держатель.
  const HeldBox({required this.size, required this.child, super.key});

  /// Размер, в котором держится [child].
  final Size size;

  /// То, что держим.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: size.width,
        maxWidth: size.width,
        minHeight: size.height,
        maxHeight: size.height,
        child: child,
      ),
    );
  }
}
