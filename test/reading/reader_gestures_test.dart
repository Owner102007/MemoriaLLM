import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/reader_gestures.dart';

/// Жесты чтения: главное замечание владельца по проверке S6.
///
/// «Нельзя листать книгу, пока текст выделен» — и это не мелкая помеха, а
/// отобранная у читателя книга. Правило проверяется здесь числами, потому
/// что в живом дереве виджетов слой выделения требует настоящего PDFium.
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

    test('выделенный текст зоны не отменяет', () {
      // То самое замечание: книга не перестаёт быть книгой оттого, что в
      // ней что-то выделено.
      expect(
        readerTapAt(share: 0.05, selecting: true),
        ReaderTap.previousFragment,
      );
      expect(readerTapAt(share: 0.95, selecting: true), ReaderTap.nextFragment);
    });

    test('в середине при выделении нажатие снимает выделение', () {
      // Панели при этом не появляются: читатель просил убрать выделение,
      // а не открыть настройки.
      expect(
        readerTapAt(share: 0.5, selecting: true),
        ReaderTap.dismissSelection,
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
