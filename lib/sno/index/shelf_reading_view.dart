import 'package:flutter/material.dart';

import 'shelf_reading.dart';

/// Сколько непрочитанных книг названо поимённо.
const int kNamedUnread = 3;

/// Число с пробелами между тройками цифр: `16 212`.
String describeCount(int value) {
  final String digits = value.abs().toString();
  final StringBuffer out = StringBuffer(value < 0 ? '-' : '');
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      out.write(' ');
    }
    out.write(digits[i]);
  }
  return out.toString();
}

/// Сколько прошло времени — словами: `1,4 с`, `40 с`, `6 мин 40 с`,
/// `1 ч 05 мин`.
String describeSpan(int ms) {
  final int safe = ms < 0 ? 0 : ms;
  if (safe < 10000) {
    final int tenths = (safe / 100).round();
    return '${tenths ~/ 10},${tenths % 10} с';
  }
  final int seconds = (safe / 1000).round();
  if (seconds < 60) {
    return '$seconds с';
  }
  final int minutes = seconds ~/ 60;
  if (minutes < 60) {
    return '$minutes мин ${(seconds % 60).toString().padLeft(2, '0')} с';
  }
  return '${minutes ~/ 60} ч ${(minutes % 60).toString().padLeft(2, '0')} мин';
}

/// Что написано в полоске над полкой, пока книги готовятся
/// (SNO-F-IDX-04); пусто — полоски нет.
String describeShelfReading(ShelfReadingProgress progress) {
  return switch (progress.phase) {
    ShelfReadingPhase.reading =>
      'Читаю книги · ${progress.booksDone} из ${progress.booksTotal}',
    ShelfReadingPhase.held =>
      'Чтение книг приостановлено: открыта книга · '
          '${progress.booksDone} из ${progress.booksTotal}',
    ShelfReadingPhase.mapping =>
      progress.mapTotal > 0
          ? 'Считаю карту · ${progress.mapDone} из ${progress.mapTotal}'
          : 'Считаю карту',
    ShelfReadingPhase.idle || ShelfReadingPhase.done => '',
  };
}

/// Какая доля подготовки позади — для полосы хода; `null` — не узнать.
double? shelfReadingShare(ShelfReadingProgress progress) {
  switch (progress.phase) {
    case ShelfReadingPhase.reading:
    case ShelfReadingPhase.held:
      if (progress.booksTotal <= 0) {
        return null;
      }
      final double inBook = progress.pages > 0
          ? progress.page / progress.pages
          : 0.0;
      final double share = (progress.booksDone + inBook) / progress.booksTotal;
      return share.clamp(0, 1).toDouble();
    case ShelfReadingPhase.mapping:
      if (progress.mapTotal <= 0) {
        return null;
      }
      return (progress.mapDone / progress.mapTotal).clamp(0, 1).toDouble();
    case ShelfReadingPhase.idle:
    case ShelfReadingPhase.done:
      return null;
  }
}

/// Что вышло с картой — одной строкой для экспериментатора.
String describeMapSummary(MapSummary map) {
  switch (map.state) {
    case MapSummary.built:
      return <String>[
        'Карта посчитана · книг: ${map.books}, групп: ${map.groups}',
        if (map.ms > 0) describeSpan(map.ms),
        if (map.fingerprint.isNotEmpty) 'отпечаток ${map.fingerprint}',
      ].join(' · ');
    case MapSummary.tooFew:
      return 'Карта не посчитана: книг на полке меньше трёх.';
    case MapSummary.tooMany:
      return 'Карта не посчитана: книг на полке слишком много.';
    default:
      return 'Карта не посчиталась — расчёт повторится при следующем '
          'запуске.';
  }
}

/// Подготовка книг — строками для раздела «Тестирование»
/// (SNO-F-IDX-04, кадр SNO-SCR-01.1).
///
/// Пока подготовка идёт — что делается сейчас; когда кончилась — её
/// итог: сколько книг и страниц прочитано, сколько это заняло, чего
/// прочитать не удалось и что вышло с картой.
List<String> describeShelfIndex(
  ShelfReadingProgress progress,
  ShelfIndexSummary? summary,
) {
  switch (progress.phase) {
    case ShelfReadingPhase.reading:
      return <String>[
        'Читаю текст · ${progress.booksDone} из ${progress.booksTotal}',
        if (progress.title.isNotEmpty)
          progress.pages > 0
              ? '«${progress.title}» · стр. ${progress.page} из '
                    '${progress.pages}'
              : '«${progress.title}»',
        if (progress.elapsedMs > 0)
          'Прошло ${describeSpan(progress.elapsedMs)}',
      ];
    case ShelfReadingPhase.held:
      return <String>[
        'Чтение книг приостановлено: открыта книга.',
        'Прочитано ${progress.booksDone} из ${progress.booksTotal}',
      ];
    case ShelfReadingPhase.mapping:
      return <String>[describeShelfReading(progress)];
    case ShelfReadingPhase.idle:
    case ShelfReadingPhase.done:
      break;
  }
  if (summary == null) {
    return const <String>['Книги ещё не читались.'];
  }
  if (!summary.complete) {
    return <String>[
      'Чтение книг не закончено — продолжится при следующем запуске.',
      if (summary.readMs > 0) 'Уже заняло ${describeSpan(summary.readMs)}',
    ];
  }
  if (summary.books == 0 && summary.unread.isEmpty) {
    return const <String>['Книг на полке нет.'];
  }
  final List<String> named = <String>[
    for (final String title in summary.unread.take(kNamedUnread)) '«$title»',
  ];
  final int rest = summary.unread.length - named.length;
  final MapSummary? map = summary.map;
  return <String>[
    'Прочитано книг: ${describeCount(summary.books)} · '
        '${describeCount(summary.pages)} стр.',
    if (summary.readMs > 0) 'Заняло ${describeSpan(summary.readMs)}',
    if (summary.scans > 0) 'Без текста (сканы): ${summary.scans}',
    if (summary.unread.isNotEmpty)
      'Не прочитаны: ${summary.unread.length} — ${named.join(', ')}'
          '${rest > 0 ? ' и ещё $rest' : ''}',
    if (map != null) describeMapSummary(map),
  ];
}

/// Стоит ли предложить экспериментатору пройти полку ещё раз: чтение
/// не закончено, есть непрочитанные книги или карта не посчиталась.
bool shelfIndexNeedsRetry(
  ShelfReadingProgress progress,
  ShelfIndexSummary? summary,
) {
  if (progress.busy) {
    return false;
  }
  if (summary == null || !summary.complete) {
    return true;
  }
  return summary.unread.isNotEmpty || summary.map?.state == MapSummary.failed;
}

/// Полоска над полкой, пока книги готовятся (SNO-F-IDX-04).
///
/// Есть, только пока подготовка идёт: когда текст прочитан и карта
/// посчитана, полоски нет вовсе. Нажатий не принимает.
class ShelfReadingStrip extends StatelessWidget {
  /// Создаёт полоску.
  const ShelfReadingStrip({required this.reading, super.key});

  /// Подготовка книг.
  final ShelfReading reading;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: reading,
      builder: (BuildContext context, Widget? child) {
        final ShelfReadingProgress progress = reading.progress;
        if (!progress.busy) {
          return const SizedBox.shrink();
        }
        final ThemeData theme = Theme.of(context);
        return IgnorePointer(
          child: Material(
            key: const Key('sno-shelf-reading'),
            color: theme.colorScheme.surface,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                LinearProgressIndicator(
                  value: shelfReadingShare(progress),
                  minHeight: 2,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Text(
                    describeShelfReading(progress),
                    key: const Key('sno-shelf-reading-text'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Блок «Подготовка книг» раздела «Тестирование» (SNO-F-IDX-04).
class ShelfIndexBlock extends StatelessWidget {
  /// Создаёт блок.
  const ShelfIndexBlock({required this.reading, super.key});

  /// Подготовка книг.
  final ShelfReading reading;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: reading,
      builder: (BuildContext context, Widget? child) {
        final ThemeData theme = Theme.of(context);
        final ShelfReadingProgress progress = reading.progress;
        final ShelfIndexSummary? summary = reading.summary;
        final List<String> lines = describeShelfIndex(progress, summary);
        return Padding(
          key: const Key('sno-shelf-index'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          // Блок раскрытого списка ставит детей по середине: колонка во
          // всю ширину держит строки у левого края.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Подготовка книг', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              if (progress.busy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: LinearProgressIndicator(
                    value: shelfReadingShare(progress),
                  ),
                ),
              for (final String line in lines)
                Text(line, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (shelfIndexNeedsRetry(progress, summary))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('sno-shelf-index-retry'),
                    onPressed: reading.start,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Прочитать книги'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
