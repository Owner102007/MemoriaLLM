import 'package:flutter/material.dart';

import '../../domain/reading/reading_filter.dart';
import 'reading_filter_layer.dart';

/// Слои листа снизу вверх: страница под светофильтром, маска, пометки,
/// указатель места.
///
/// BUG-04, ALG-UI-15. Светофильтр оборачивал весь лист целиком — вместе с
/// маской, подсветкой найденного, панелью над выделением и указателем
/// места. При «Инверсии» тёмные поля вокруг страницы становились почти
/// белыми, а затемнение светлело: ночью вокруг страницы горела яркая
/// рамка. При «Ночном красном» краснели панель и маска.
///
/// Порядок слоёв записан в одном месте и проверяется тестом: **под
/// фильтром лежит только картинка страницы**, всё остальное — выше
/// (решение 12.09.2026: пометки рисуются поверх слоя светофильтра).
class ReaderLayers extends StatelessWidget {
  /// Создаёт слои.
  const ReaderLayers({
    required this.page,
    required this.filter,
    required this.mask,
    required this.progress,
    this.overlay,
    super.key,
  });

  /// Картинка страницы — просмотрщик. Единственное, что идёт под фильтр.
  final Widget page;

  /// Светофильтр.
  final ReadingFilterPipeline filter;

  /// Маска: фон вокруг листа и затемнение вне читаемой полосы.
  final Widget mask;

  /// Указатель места. Сам ставит себя в нужное поле экрана.
  final Widget progress;

  /// Подсветка найденного и панель над выделением.
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(child: ReadingFilterLayer(filter: filter, child: page)),
        Positioned.fill(child: mask),
        // Без `IgnorePointer` намеренно: подсветка нажатий не ловит (у
        // неё нет своей области), а панель действий обязана их ловить —
        // она и есть то, ради чего выделяют.
        if (overlay != null) Positioned.fill(child: overlay!),
        // Указатель места живёт поверх маски: гасить его вместе со
        // страницей незачем, а терять при листании — тем более.
        progress,
      ],
    );
  }
}
