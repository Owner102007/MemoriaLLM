import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/reading/reader_controller.dart';
import '../../domain/reading/reading.dart';
import '../../domain/reading/sheet_placement.dart';

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

  /// Как листается книга сейчас — живое значение, а не снимок.
  ///
  /// BUG-36: способ листания хранит экран чтения, а не контроллер книги,
  /// и шторка, получавшая его значением при открытии, не узнавала о
  /// смене: книга переключалась, а выбранной оставалась прежняя кнопка.
  final ValueNotifier<PageFlow> flow;

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
      animation: Listenable.merge(<Listenable>[controller, flow]),
      builder: (BuildContext context, Widget? child) {
        final ThemeData theme = Theme.of(context);
        final BookReadingSettings settings = controller.settings;
        final PageFlow current = flow.value;
        // BUG-15: режимы листа, полоса и обрезка полей действуют только
        // при листании по страницам. В ленте их в шторке нет: настройка,
        // которая ничего не меняет на экране, обманывает.
        final bool paged = current == PageFlow.paged;
        // BUG-12: ползунок меняет страницу вживую, а в базу пишет один
        // раз — когда его отпустили.
        void persist(double value) => unawaited(controller.persistSettings());
        void setRunningHeads(bool value) =>
            unawaited(controller.setIgnoreRunningHeads(value));
        final String? cropStatus = cropStatusLabel(
          settings: settings,
          frame: controller.bookFrame,
          loading: controller.isBookFrameLoading,
        );
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
                  if (paged) ...<Widget>[
                    const _Title(text: 'Режим отображения'),
                    const SizedBox(height: 8),
                    _ModeSelector(
                      controller: controller,
                      onDisplayMode: onDisplayMode,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Половина и треть переключаются кнопками ½ и ⅓ прямо '
                      'в чтении. Деление увеличивает текст только на '
                      'широком экране, поэтому чтение поворачивается само.',
                      key: const Key('reader-mode-hint'),
                      style: theme.textTheme.bodySmall,
                    ),
                    // BUG-13: подсказки «половина — это колонка» здесь
                    // больше нет. Страница режется поперёк в любой книге
                    // (решение владельца 23.08.2026), и обещать колонку
                    // было неправдой.
                    const SizedBox(height: 16),
                  ],
                  const _Title(text: 'Листание'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      for (final PageFlow value in PageFlow.values)
                        ChoiceChip(
                          key: Key('reader-flow-${value.name}'),
                          label: Text(pageFlowName(value)),
                          selected: current == value,
                          onSelected: (bool selected) {
                            if (selected) {
                              onFlow(value);
                            }
                          },
                        ),
                    ],
                  ),
                  if (paged) ...<Widget>[
                    const SizedBox(height: 16),
                    const _Title(text: 'Полоса на экране'),
                    _ValueSlider(
                      valueKey: const Key('reader-strip-fit'),
                      label: 'Запас по краям',
                      value: settings.stripFit,
                      min: kMinStripFit,
                      max: 1,
                      onChanged: (double value) => unawaited(
                        controller.setStripFit(value, persist: false),
                      ),
                      onChangeEnd: persist,
                    ),
                    Text(
                      'Полоса вписана в экран вплотную, и её крайняя строка '
                      'приходится на самый край — там, где у телефона '
                      'закруглённый угол и вырез камеры. Запас отодвигает её '
                      'от границы; страница при этом перерисовывается мельче, '
                      'поэтому текст остаётся резким.',
                      key: const Key('reader-strip-fit-hint'),
                      style: theme.textTheme.bodySmall,
                    ),
                    _ValueSlider(
                      valueKey: const Key('reader-dim-outside'),
                      label: 'Затемнение',
                      value: settings.dimOutside,
                      min: 0,
                      max: kMaxDimOutside,
                      onChanged: (double value) => unawaited(
                        controller.setDimOutside(value, persist: false),
                      ),
                      onChangeEnd: persist,
                    ),
                    Text(
                      'В половине и трети страница видна целиком, а всё, что '
                      'сейчас не читается, уходит в тень. Ноль гасить '
                      'перестаёт — страница показывается как есть.',
                      key: const Key('reader-dim-hint'),
                      style: theme.textTheme.bodySmall,
                    ),
                    // Нахлёст и полоска соседней страницы — про листы,
                    // как и всё в этом разделе.
                    _ValueSlider(
                      valueKey: const Key('reader-strip-overlap'),
                      label: 'Нахлёст',
                      value: settings.stripOverlap,
                      min: 0,
                      max: kMaxStripOverlap,
                      format: percentLabel,
                      onChanged: (double value) => unawaited(
                        controller.setStripOverlap(value, persist: false),
                      ),
                      onChangeEnd: persist,
                    ),
                    Text(
                      'Над полосой и под ней остаётся по столько экрана: '
                      'там видны затемнённые конец прочитанного и начало '
                      'следующего. В трети действует половина. Ноль — '
                      'полосы делятся чёткой линией.',
                      key: const Key('reader-overlap-hint'),
                      style: theme.textTheme.bodySmall,
                    ),
                    _ValueSlider(
                      valueKey: const Key('reader-neighbour-share'),
                      label: 'Соседняя страница',
                      value: settings.neighbourShare,
                      min: 0,
                      max: kMaxNeighbourShare,
                      format: percentLabel,
                      onChanged: (double value) => unawaited(
                        controller.setNeighbourShare(value, persist: false),
                      ),
                      onChangeEnd: persist,
                    ),
                    Text(
                      'На широком экране соседние страницы видны тёмными '
                      'полосками такой ширины. Ноль — закрыты фоном.',
                      key: const Key('reader-neighbour-hint'),
                      style: theme.textTheme.bodySmall,
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
                      onChanged: settings.autoCrop ? setRunningHeads : null,
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
                        if (settings.autoCrop) ...<Widget>[
                          const SizedBox(width: 8),
                          // F-READ-15: рамка книги считается заново, а
                          // выставленная руками при этом снимается.
                          TextButton(
                            key: const Key('reader-recompute-crop'),
                            onPressed: () =>
                                unawaited(controller.recomputeBookFrame()),
                            child: const Text('Пересчитать'),
                          ),
                        ] else if (settings.manualCrop != null) ...<Widget>[
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
                    if (cropStatus != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        cropStatus,
                        key: const Key('reader-crop-status'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ] else ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      'В ленте страница показывается целиком, как в обычном '
                      'просмотрщике. Режимы, полоса и обрезка полей вернутся '
                      'вместе с листанием по страницам.',
                      key: const Key('reader-ribbon-note'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
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
                      onChanged: (double value) => unawaited(
                        controller.setFilterIntensity(value, persist: false),
                      ),
                      onChangeEnd: persist,
                    ),
                  _ValueSlider(
                    valueKey: const Key('reader-brightness'),
                    label: 'Яркость',
                    value: settings.brightness,
                    min: 0.15,
                    max: 1,
                    onChanged: (double value) => unawaited(
                      controller.setBrightness(value, persist: false),
                    ),
                    onChangeEnd: persist,
                  ),
                  _ValueSlider(
                    valueKey: const Key('reader-contrast'),
                    label: 'Контраст',
                    value: settings.contrast,
                    min: 0.5,
                    max: 2,
                    onChanged: (double value) => unawaited(
                      controller.setContrast(value, persist: false),
                    ),
                    onChangeEnd: persist,
                  ),
                  _ValueSlider(
                    valueKey: const Key('reader-gamma'),
                    label: 'Гамма',
                    value: settings.gamma,
                    min: 0.5,
                    max: 2,
                    onChanged: (double value) =>
                        unawaited(controller.setGamma(value, persist: false)),
                    onChangeEnd: persist,
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

/// Режимы, которых нет на кнопках в чтении.
///
/// Половина и треть переехали в верхнюю панель чтения: к ним возвращаются
/// по десять раз за книгу, и место им там. Развороты остались здесь —
/// их выбирают один раз на книгу, обычно на большом экране.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.controller, required this.onDisplayMode});

  static const List<PageDisplayMode> _modes = <PageDisplayMode>[
    PageDisplayMode.full,
    PageDisplayMode.spread,
    PageDisplayMode.spreadHalf,
  ];

  final ReaderController controller;
  final ValueChanged<PageDisplayMode> onDisplayMode;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final PageDisplayMode mode in _modes)
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
    required this.onChangeEnd,
    this.format,
  });

  final Key valueKey;
  final String label;
  final double value;
  final double min;
  final double max;

  /// Ползунок сдвинули: значение меняется вживую, без записи.
  final ValueChanged<double> onChanged;

  /// Ползунок отпустили: значение пора записать (BUG-12).
  final ValueChanged<double> onChangeEnd;

  /// Как подписать значение; без него — число с двумя знаками.
  final String Function(double value)? format;

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
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            format?.call(safe) ?? safe.toStringAsFixed(2),
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Что сказать читателю о рамке книги (F-READ-15); `null` — нечего.
///
/// Рамка у книги одна, и читателю стоит знать, откуда она: выставлена
/// руками, посчитана по выборке страниц или ещё считается. Без этой
/// строки «Пересчитать» было бы кнопкой без видимого результата.
String? cropStatusLabel({
  required BookReadingSettings settings,
  required BookFrame? frame,
  required bool loading,
}) {
  if (settings.manualCrop != null) {
    return 'Рамка выставлена руками — одна на всю книгу';
  }
  if (!settings.autoCrop) {
    return null;
  }
  if (frame == null) {
    return loading ? 'Рамка книги считается…' : null;
  }
  if (!frame.hasContent) {
    return 'Содержимое не найдено — страница показывается целиком';
  }
  final int pages = frame.samples;
  final String counted = pages % 10 == 1 && pages % 100 != 11
      ? '$pages странице'
      : '$pages страницам';
  return frame.isMirrored
      ? 'Рамка книги — по $counted, поля зеркальные'
      : 'Рамка книги — по $counted';
}

/// Доля экрана — процентами: «7 %», а половины — «3,5 %».
String percentLabel(double share) {
  final double percent = share * 100;
  final double rounded = (percent * 2).round() / 2;
  final String text = rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1).replaceAll('.', ',');
  return '$text %';
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
