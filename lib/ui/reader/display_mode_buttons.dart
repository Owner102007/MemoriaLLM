import 'package:flutter/material.dart';

import '../../domain/reading/reading.dart';

/// Кнопки-дроби ½ и ⅓ прямо в чтении.
///
/// Деление страницы — не настройка, а способ читать: к нему возвращаются
/// по десять раз за книгу, когда шрифт оказался мелким или, наоборот,
/// крупным. В панели настроек оно лежало через два нажатия и вслепую:
/// панель закрывает страницу, а решение принимается по странице.
///
/// Дробь на кнопке названа своим именем — «1» над «2», — а не значком,
/// который пришлось бы запоминать. Повторное нажатие возвращает страницу
/// целиком: кнопка включает режим и она же его выключает.
class DisplayModeButtons extends StatelessWidget {
  /// Создаёт пару кнопок.
  const DisplayModeButtons({
    required this.mode,
    required this.onMode,
    this.gainless = const <PageDisplayMode>{},
    super.key,
  });

  /// Текущий режим отображения.
  final PageDisplayMode mode;

  /// Читатель выбрал режим.
  final ValueChanged<PageDisplayMode> onMode;

  /// Режимы, которые на этой странице не увеличат текст.
  ///
  /// Такая дробь показывается погасшей — читатель видит заранее, что
  /// нажимать её незачем. Нажатие всё равно проходит: гасить кнопку
  /// насмерть значило бы спорить с человеком, который видит страницу
  /// своими глазами, а объяснение он получит от экрана чтения.
  final Set<PageDisplayMode> gainless;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _FractionButton(
          buttonKey: const Key('reader-mode-half-button'),
          denominator: 2,
          selected: mode == PageDisplayMode.half,
          gainless: gainless.contains(PageDisplayMode.half),
          onPressed: () => onMode(_toggle(PageDisplayMode.half)),
          tooltip: _tooltip(PageDisplayMode.half, 'Половина страницы'),
        ),
        _FractionButton(
          buttonKey: const Key('reader-mode-third-button'),
          denominator: 3,
          selected: mode == PageDisplayMode.third,
          gainless: gainless.contains(PageDisplayMode.third),
          onPressed: () => onMode(_toggle(PageDisplayMode.third)),
          tooltip: _tooltip(PageDisplayMode.third, 'Треть страницы'),
        ),
      ],
    );
  }

  String _tooltip(PageDisplayMode wanted, String name) {
    if (mode == wanted) {
      return 'Вернуть страницу целиком';
    }
    if (gainless.contains(wanted)) {
      return '$name: на этой странице не увеличит текст';
    }
    return name;
  }

  PageDisplayMode _toggle(PageDisplayMode wanted) {
    return mode == wanted ? PageDisplayMode.full : wanted;
  }
}

class _FractionButton extends StatelessWidget {
  const _FractionButton({
    required this.buttonKey,
    required this.denominator,
    required this.selected,
    required this.gainless,
    required this.onPressed,
    required this.tooltip,
  });

  /// Ключ ставится на саму кнопку, а не на обёртку.
  ///
  /// Иначе `find.byKey` в тестах находит обёртку, и всё, что спрашивает
  /// у кнопки её свойства, падает на ровном месте.
  final Key buttonKey;

  final int denominator;
  final bool selected;
  final bool gainless;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = selected
        ? scheme.secondary
        : (gainless
              // Не «серая кнопка», а именно приглушённая: она работает,
              // просто ничего не даст. Совсем выключенная кнопка не
              // объясняет, почему она выключена.
              ? scheme.onSurface.withValues(alpha: 0.38)
              : scheme.onSurface);
    return IconButton(
      key: buttonKey,
      // Кнопок в панели чтения много, а ширина телефона в портрете одна:
      // без уплотнения заголовок книги съедается кнопками до многоточия.
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        decoration: BoxDecoration(
          color: selected ? scheme.secondary.withValues(alpha: 0.18) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: _Fraction(denominator: denominator, color: color),
      ),
    );
  }
}

/// Дробь: единица над знаменателем, между ними черта.
///
/// Рисуется текстом, а не готовыми символами `½` и `⅓`: в системном
/// шрифте они есть не везде, а недостающий символ показывается пустым
/// прямоугольником — кнопка без картинки хуже, чем некрасивая кнопка.
class _Fraction extends StatelessWidget {
  const _Fraction({required this.denominator, required this.color});

  final int denominator;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final TextStyle digits = TextStyle(
      fontSize: 11,
      height: 1,
      fontWeight: FontWeight.w600,
      color: color,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('1', style: digits),
        Container(
          width: 12,
          height: 1.5,
          margin: const EdgeInsets.symmetric(vertical: 1.5),
          color: color,
        ),
        Text('$denominator', style: digits),
      ],
    );
  }
}
