import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/reading/reader_controller.dart';
import '../../domain/reading/reading.dart';

/// Панель читательской рамки: режим, обрезка полей, светофильтр.
///
/// Всё меняется на живой странице: панель полупрозрачная и не закрывает
/// текст целиком, потому что подбирать яркость и гамму вслепую нельзя —
/// решение принимается глазами, а глаза смотрят на книгу, а не на ползунок.
class ReaderSettingsSheet extends StatelessWidget {
  /// Создаёт панель.
  const ReaderSettingsSheet({
    required this.controller,
    required this.flow,
    required this.onFlow,
    required this.onDisplayMode,
    required this.onEditCrop,
    super.key,
  });

  /// Состояние книги.
  final ReaderController controller;

  /// Как листается книга сейчас.
  final PageFlow flow;

  /// Сменить способ листания.
  final ValueChanged<PageFlow> onFlow;

  /// Сменить режим отображения.
  ///
  /// Режим меняет не панель, а экран: вместе с режимом поворачивается
  /// чтение, а поворот — дело экрана, не панели.
  final ValueChanged<PageDisplayMode> onDisplayMode;

  /// Открыть ручную правку рамки.
  final VoidCallback onEditCrop;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final ThemeData theme = Theme.of(context);
        final BookReadingSettings settings = controller.settings;
        return Material(
          color: theme.colorScheme.surface.withValues(alpha: 0.97),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const _Title(text: 'Режим отображения'),
                  const SizedBox(height: 8),
                  _ModeSelector(
                    controller: controller,
                    onDisplayMode: onDisplayMode,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Деление страницы увеличивает текст только на широком '
                    'экране, поэтому чтение поворачивается само.',
                    key: const Key('reader-mode-hint'),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (controller.frame?.hasColumns ?? false) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      'Страница двухколоночная: половина — это колонка.',
                      key: const Key('reader-columns-hint'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 16),
                  const _Title(text: 'Листание'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      for (final PageFlow value in PageFlow.values)
                        ChoiceChip(
                          key: Key('reader-flow-${value.name}'),
                          label: Text(pageFlowName(value)),
                          selected: flow == value,
                          onSelected: (bool selected) {
                            if (selected) {
                              onFlow(value);
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _Title(text: 'Поля'),
                  SwitchListTile(
                    key: const Key('reader-autocrop-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Обрезать белые поля'),
                    subtitle: const Text(
                      'Страница займёт больше экрана, но её края будут '
                      'подрезаны автоматически',
                    ),
                    value: settings.autoCrop,
                    onChanged: (bool value) =>
                        unawaited(controller.setAutoCrop(value)),
                  ),
                  SwitchListTile(
                    key: const Key('reader-runningheads-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Не считать колонтитулы'),
                    subtitle: const Text(
                      'Номера страниц и заголовки не мешают обрезке',
                    ),
                    value: settings.ignoreRunningHeads,
                    onChanged: settings.autoCrop
                        ? (bool value) =>
                              unawaited(controller.setIgnoreRunningHeads(value))
                        : null,
                  ),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('reader-edit-crop'),
                          onPressed: onEditCrop,
                          icon: const Icon(Icons.crop),
                          label: const Text('Поправить рамку'),
                        ),
                      ),
                      if (settings.manualCrop != null) ...<Widget>[
                        const SizedBox(width: 8),
                        TextButton(
                          key: const Key('reader-reset-crop'),
                          onPressed: () =>
                              unawaited(controller.setManualCrop(null)),
                          child: const Text('Сбросить'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _Title(text: 'Светофильтр'),
                  const SizedBox(height: 8),
                  _FilterSelector(controller: controller),
                  if (settings.filter != ReadingFilter.none)
                    _ValueSlider(
                      valueKey: const Key('reader-filter-intensity'),
                      label: 'Сила фильтра',
                      value: settings.filterIntensity,
                      min: 0,
                      max: 1,
                      onChanged: (double value) =>
                          unawaited(controller.setFilterIntensity(value)),
                    ),
                  _ValueSlider(
                    valueKey: const Key('reader-brightness'),
                    label: 'Яркость',
                    value: settings.brightness,
                    min: 0.15,
                    max: 1,
                    onChanged: (double value) =>
                        unawaited(controller.setBrightness(value)),
                  ),
                  _ValueSlider(
                    valueKey: const Key('reader-contrast'),
                    label: 'Контраст',
                    value: settings.contrast,
                    min: 0.5,
                    max: 2,
                    onChanged: (double value) =>
                        unawaited(controller.setContrast(value)),
                  ),
                  _ValueSlider(
                    valueKey: const Key('reader-gamma'),
                    label: 'Гамма',
                    value: settings.gamma,
                    min: 0.5,
                    max: 2,
                    onChanged: (double value) =>
                        unawaited(controller.setGamma(value)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleSmall);
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.controller, required this.onDisplayMode});

  final ReaderController controller;
  final ValueChanged<PageDisplayMode> onDisplayMode;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final PageDisplayMode mode in PageDisplayMode.values)
          ChoiceChip(
            key: Key('reader-mode-${mode.name}'),
            label: Text(displayModeName(mode)),
            selected: controller.settings.displayMode == mode,
            onSelected: (bool selected) {
              if (selected) {
                onDisplayMode(mode);
              }
            },
          ),
      ],
    );
  }
}

class _FilterSelector extends StatelessWidget {
  const _FilterSelector({required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final ReadingFilter filter in ReadingFilter.values)
          ChoiceChip(
            key: Key('reader-filter-${filter.name}'),
            label: Text(readingFilterName(filter)),
            selected: controller.settings.filter == filter,
            onSelected: (bool selected) {
              if (selected) {
                unawaited(controller.setFilter(filter));
              }
            },
          ),
      ],
    );
  }
}

class _ValueSlider extends StatelessWidget {
  const _ValueSlider({
    required this.valueKey,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final Key valueKey;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double safe = value.clamp(min, max);
    return Row(
      children: <Widget>[
        SizedBox(
          width: 96,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Expanded(
          child: Slider(
            key: valueKey,
            min: min,
            max: max,
            value: safe,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            safe.toStringAsFixed(2),
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Человеческое название режима отображения.
String displayModeName(PageDisplayMode mode) {
  switch (mode) {
    case PageDisplayMode.full:
      return 'Страница';
    case PageDisplayMode.half:
      return 'Половина';
    case PageDisplayMode.third:
      return 'Треть';
    case PageDisplayMode.spread:
      return 'Разворот';
    case PageDisplayMode.spreadHalf:
      return 'Полразворота';
  }
}

/// Человеческое название способа листания.
String pageFlowName(PageFlow flow) {
  switch (flow) {
    case PageFlow.continuous:
      return 'Лента';
    case PageFlow.paged:
      return 'По страницам';
  }
}

/// Человеческое название светофильтра.
String readingFilterName(ReadingFilter filter) {
  switch (filter) {
    case ReadingFilter.none:
      return 'Без фильтра';
    case ReadingFilter.nightRed:
      return 'Ночной красный';
    case ReadingFilter.warm:
      return 'Тёплый';
    case ReadingFilter.sepia:
      return 'Сепия';
    case ReadingFilter.invert:
      return 'Инверсия';
  }
}
