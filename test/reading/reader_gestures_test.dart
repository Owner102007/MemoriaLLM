import 'dart:ui' show Offset, PointerDeviceKind;

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/reader_gestures.dart';

/// Жесты чтения: что считать нажатием и что оно значит.
///
/// Правила проверяются здесь числами, потому что в живом дереве виджетов
/// слой выделения и сам просмотрщик требуют настоящего PDFium.
void main() {
  group('зоны листания', () {
    test('края листают, середина показывает панели', () {
      expect(
        readerTapAt(share: 0.1, selecting: false),
        ReaderTap.previousFragment,
      );
      expect(readerTapAt(share: 0.9, selecting: false), ReaderTap.nextFragment);
      expect(readerTapAt(share: 0.5, selecting: false), ReaderTap.toggleChrome);
    });

    test('F-READ-22: при выделении нажатие в любой зоне снимает '
        'выделение и не листает', () {
      // Решение владельца 03.10.2026, отменяет решение 06.09.2026:
      // читатель, промахнувшийся мимо панели над выделением, терял и
      // выделение, и страницу разом.
      for (final double share in <double>[-0.2, 0.05, 0.3, 0.5, 0.7, 0.95]) {
        expect(
          readerTapAt(share: share, selecting: true),
          ReaderTap.dismissSelection,
          reason: 'доля ширины $share',
        );
      }
    });

    test('F-READ-22: без выделения зоны листают как прежде', () {
      expect(
        readerTapAt(share: 0.05, selecting: false),
        ReaderTap.previousFragment,
      );
      expect(
        readerTapAt(share: 0.95, selecting: false),
        ReaderTap.nextFragment,
      );
    });

    test('границы зон принадлежат середине', () {
      // Ровно на границе — не листание: иначе нажатие в неё вело бы себя
      // по-разному от округления.
      expect(
        readerTapAt(share: kReaderTapZone, selecting: false),
        ReaderTap.toggleChrome,
      );
      expect(
        readerTapAt(share: 1 - kReaderTapZone, selecting: false),
        ReaderTap.toggleChrome,
      );
    });

    test('промах за край экрана всё равно листает', () {
      expect(
        readerTapAt(share: -0.2, selecting: false),
        ReaderTap.previousFragment,
      );
      expect(readerTapAt(share: 1.2, selecting: false), ReaderTap.nextFragment);
    });
  });

  group('BUG-37: нажатие узнаём сами', () {
    const Offset at = Offset(300, 200);
    const Duration quick = Duration(milliseconds: 80);

    /// Наблюдатель с часами, которые переводит тест.
    ({TapWatch watch, void Function(Duration) wait}) build() {
      Duration now = const Duration(seconds: 10);
      final TapWatch watch = TapWatch(clock: () => now);
      return (watch: watch, wait: (Duration by) => now += by);
    }

    Offset? tap(
      TapWatch watch, {
      int pointer = 1,
      Offset down = at,
      Offset? up,
      Duration held = quick,
      Duration start = Duration.zero,
      PointerDeviceKind kind = PointerDeviceKind.touch,
      bool primary = true,
    }) {
      watch.down(
        pointer: pointer,
        position: down,
        time: start,
        kind: kind,
        primary: primary,
      );
      return watch.up(
        pointer: pointer,
        position: up ?? down,
        time: start + held,
      );
    }

    test('BUG-37: короткое касание — нажатие, и известно оно сразу', () {
      // Сразу — значит в тот же вызов, которым поднят палец: ждать
      // трети секунды, не окажется ли нажатие двойным, незачем.
      final TapWatch watch = build().watch;
      expect(tap(watch), at);
    });

    test('BUG-37: два быстрых нажатия — два нажатия', () {
      final TapWatch watch = build().watch;
      expect(tap(watch), at);
      expect(
        tap(watch, pointer: 2, start: const Duration(milliseconds: 150)),
        at,
      );
    });

    test('BUG-37: на пороге удержания решает распознаватель', () {
      // Он живёт по таймеру, а метки времени события с таймером
      // расходятся на миллисекунды. Сверяй мы порог ещё и по меткам,
      // касание на самой границе не стало бы ни нажатием, ни выделением.
      final TapWatch watch = build().watch;
      expect(tap(watch, held: kTouchSelectionDelay), at);
    });

    test('BUG-37: заведомое удержание — не нажатие и без распознавателя', () {
      // Страховка: вдвое дольше порога — уже точно не нажатие.
      final TapWatch watch = build().watch;
      final Duration long = kTouchSelectionDelay * kHoldBackstop;
      expect(tap(watch, held: long), isNull);
      expect(tap(watch, held: long - const Duration(milliseconds: 1)), at);
    });

    test('BUG-37: мышь можно держать дольше пальца', () {
      // У мыши удержание — полсекунды: раньше просмотрщик слово не
      // выделяет, и неторопливый щелчок обязан остаться щелчком.
      final TapWatch watch = build().watch;
      const PointerDeviceKind mouse = PointerDeviceKind.mouse;
      expect(tap(watch, kind: mouse, held: kMouseHoldDelay), at);
      expect(
        tap(watch, kind: mouse, held: kMouseHoldDelay * kHoldBackstop),
        isNull,
      );
    });

    test('BUG-37: сдвиг дальше допуска — не нажатие', () {
      final TapWatch watch = build().watch;
      expect(tap(watch, up: at + const Offset(kTouchTapSlop + 1, 0)), isNull);
      // В пределах допуска палец дрожит, а не тянет.
      const Offset near = Offset(300 + kTouchTapSlop - 1, 200);
      expect(tap(watch, up: near), near);
    });

    test('BUG-37: у мыши допуск мал — дальше начинается выделение', () {
      final TapWatch watch = build().watch;
      expect(
        tap(
          watch,
          kind: PointerDeviceKind.mouse,
          up: at + const Offset(kPreciseTapSlop + 1, 0),
        ),
        isNull,
      );
      expect(tap(watch, kind: PointerDeviceKind.mouse), at);
    });

    test('BUG-37: ушёл и вернулся — всё равно не нажатие', () {
      // Палец, который съездил в сторону и вернулся, что-то тянул.
      final TapWatch watch = build().watch;
      watch.down(
        pointer: 1,
        position: at,
        time: Duration.zero,
        kind: PointerDeviceKind.touch,
      );
      watch.move(pointer: 1, position: at + const Offset(60, 0));
      watch.move(pointer: 1, position: at);
      expect(watch.up(pointer: 1, position: at, time: quick), isNull);
    });

    test('BUG-37: второй палец — щипок, а не два нажатия', () {
      final TapWatch watch = build().watch;
      for (final int pointer in <int>[1, 2]) {
        watch.down(
          pointer: pointer,
          position: at,
          time: Duration.zero,
          kind: PointerDeviceKind.touch,
        );
      }
      expect(watch.up(pointer: 1, position: at, time: quick), isNull);
      expect(watch.up(pointer: 2, position: at, time: quick), isNull);
      // Пальцы убраны — следующее касание снова обычное.
      expect(tap(watch, pointer: 3), at);
    });

    test('BUG-37: правая кнопка мыши — не нажатие', () {
      final TapWatch watch = build().watch;
      expect(tap(watch, kind: PointerDeviceKind.mouse, primary: false), isNull);
    });

    test('BUG-37: началось выделение — жест нажатием уже не станет', () {
      // Распознаватель удержания живёт по таймеру, и его слово —
      // последнее: иначе одно касание и выделило бы слово, и листнуло.
      final TapWatch watch = build().watch;
      watch.down(
        pointer: 1,
        position: at,
        time: Duration.zero,
        kind: PointerDeviceKind.touch,
      );
      watch.spoil();
      expect(watch.up(pointer: 1, position: at, time: quick), isNull);
      // Испорчен один жест, а не все последующие.
      expect(tap(watch, pointer: 2), at);
    });

    test('BUG-37: выделение без касания ничего не портит', () {
      final TapWatch watch = build().watch;
      watch.spoil();
      expect(tap(watch), at);
    });

    test('BUG-37: отобранный системой указатель — не нажатие', () {
      final TapWatch watch = build().watch;
      watch.down(
        pointer: 1,
        position: at,
        time: Duration.zero,
        kind: PointerDeviceKind.touch,
      );
      watch.cancel(pointer: 1);
      expect(watch.up(pointer: 1, position: at, time: quick), isNull);
      expect(tap(watch, pointer: 2), at);
    });

    test('BUG-37: сообщение просмотрщика о том же нажатии — эхо', () {
      // Он пришлёт его через 300 мс; исполнять второй раз нельзя —
      // страница перелистнулась бы дважды.
      final ({TapWatch watch, void Function(Duration) wait}) kit = build();
      expect(tap(kit.watch), at);
      kit.wait(const Duration(milliseconds: 300));
      expect(kit.watch.echoes(), isTrue);
    });

    test('BUG-37: эхо отвергнутого жеста тоже эхо', () {
      // Жест решён нами, чем бы ни кончился: если просмотрщик счёл
      // нажатием то, что мы отвергли, листать по его слову нельзя.
      final ({TapWatch watch, void Function(Duration) wait}) kit = build();
      final Duration long = kTouchSelectionDelay * kHoldBackstop;
      expect(tap(kit.watch, held: long), isNull);
      kit.wait(const Duration(milliseconds: 300));
      expect(kit.watch.echoes(), isTrue);
    });

    test('BUG-37: после двух быстрых нажатий эхо не копится', () {
      // О двойном нажатии просмотрщик одиночным не сообщает вовсе.
      // Счётчик «жду два сообщения» проглотил бы следующее настоящее.
      final ({TapWatch watch, void Function(Duration) wait}) kit = build();
      expect(tap(kit.watch), at);
      expect(tap(kit.watch, pointer: 2), at);
      kit.wait(kViewerTapEcho + const Duration(milliseconds: 1));
      expect(kit.watch.echoes(), isFalse);
    });

    test('BUG-37: нажатие без указателя — не эхо', () {
      // Так нажимают средства доступности: событий указателя нет, и
      // сообщение просмотрщика — единственное, что о нажатии известно.
      final ({TapWatch watch, void Function(Duration) wait}) kit = build();
      expect(kit.watch.echoes(), isFalse);
    });

    test('BUG-37: нажатие, оставленное просмотрщику, — не эхо', () {
      // Пока текст выделен, нажатие исполняет просмотрщик: только он
      // отличает страницу от ручки выделения. Его сообщение обязано
      // дойти до дела — и ровно один раз.
      final ({TapWatch watch, void Function(Duration) wait}) kit = build();
      expect(tap(kit.watch), at);
      kit.watch.leaveToViewer();
      kit.wait(const Duration(milliseconds: 300));
      expect(kit.watch.echoes(), isFalse);
      expect(kit.watch.echoes(), isTrue);
    });

    test('BUG-37: следующее нажатие забывает оставленное', () {
      // Просмотрщик мог и не сообщить: нажали по ручке выделения или
      // дважды подряд. Следующее нажатие, исполненное сразу, не должно
      // исполниться ещё раз из-за старой пометки.
      final ({TapWatch watch, void Function(Duration) wait}) kit = build();
      expect(tap(kit.watch), at);
      kit.watch.leaveToViewer();
      expect(tap(kit.watch, pointer: 2), at);
      kit.wait(const Duration(milliseconds: 300));
      expect(kit.watch.echoes(), isTrue);
    });

    test('BUG-37: допуск и порог зависят от указателя', () {
      expect(tapSlopFor(PointerDeviceKind.touch), kTouchTapSlop);
      expect(tapSlopFor(PointerDeviceKind.stylus), kTouchTapSlop);
      expect(tapSlopFor(PointerDeviceKind.mouse), kPreciseTapSlop);
      expect(tapHoldLimitFor(PointerDeviceKind.touch), kTouchSelectionDelay);
      expect(tapHoldLimitFor(PointerDeviceKind.mouse), kMouseHoldDelay);
      // Эхо обязано пережить ожидание двойного нажатия с запасом.
      expect(kViewerTapEcho.inMilliseconds, greaterThan(300 * 2));
    });
  });

  group('чем начинается выделение', () {
    test('мышь и трекпад — протяжкой', () {
      expect(selectionStartsOnDrag(PointerDeviceKind.mouse), isTrue);
      expect(selectionStartsOnDrag(PointerDeviceKind.trackpad), isTrue);
    });

    test('палец и перо — удержанием', () {
      expect(selectionStartsOnDrag(PointerDeviceKind.touch), isFalse);
      expect(selectionStartsOnDrag(PointerDeviceKind.stylus), isFalse);
      expect(selectionStartsOnDrag(PointerDeviceKind.invertedStylus), isFalse);
    });

    test('неизвестный указатель ведёт себя как палец', () {
      // Незнакомое устройство лучше считать пальцем: лишнее ожидание
      // раздражает, а выделение, начавшееся от случайного движения,
      // ломает листание.
      expect(selectionStartsOnDrag(PointerDeviceKind.unknown), isFalse);
    });

    test('наборы указателей делят все виды без остатка', () {
      // Экран чтения строит из этой функции два набора распознавателей.
      // Пересечение означало бы указатель, у которого выделение начинают
      // сразу оба жеста; дыра — указатель, которым выделить нельзя вовсе.
      final Set<PointerDeviceKind> drag = <PointerDeviceKind>{
        for (final PointerDeviceKind kind in PointerDeviceKind.values)
          if (selectionStartsOnDrag(kind)) kind,
      };
      final Set<PointerDeviceKind> hold = <PointerDeviceKind>{
        for (final PointerDeviceKind kind in PointerDeviceKind.values)
          if (!selectionStartsOnDrag(kind)) kind,
      };
      expect(drag.intersection(hold), isEmpty);
      expect(drag.union(hold), PointerDeviceKind.values.toSet());
      expect(drag, isNotEmpty);
      expect(hold, isNotEmpty);
    });

    test('порог удержания заметно короче обычного', () {
      // Стандартные 500 мс владелец назвал слишком долгими, а меньше
      // сотни — это уже случайное касание при листании.
      expect(kTouchSelectionDelay.inMilliseconds, lessThan(500));
      expect(kTouchSelectionDelay.inMilliseconds, greaterThanOrEqualTo(150));
    });
  });
}
