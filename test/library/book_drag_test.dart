import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/ui/library/book_drag.dart';

void main() {
  group('как берётся книга', () {
    test('на телефоне — только долгим нажатием', () {
      // Палец сначала прокручивает полку. Если книга поднималась бы по
      // касанию, прокрутка перестала бы работать вовсе.
      expect(dragStartsImmediately(TargetPlatform.android), isFalse);
      expect(dragStartsImmediately(TargetPlatform.iOS), isFalse);
    });

    test('на ПК — сразу, мышью', () {
      // Мышь ничего не прокручивает движением по экрану, и полсекунды
      // ожидания с зажатой кнопкой там — неоткуда взявшаяся задержка.
      expect(dragStartsImmediately(TargetPlatform.windows), isTrue);
      expect(dragStartsImmediately(TargetPlatform.linux), isTrue);
      expect(dragStartsImmediately(TargetPlatform.macOS), isTrue);
    });

    test('ответ есть для каждой платформы', () {
      // Функция обязана быть исчерпывающей: новая платформа не должна
      // молча оказаться без способа взять книгу.
      for (final TargetPlatform platform in TargetPlatform.values) {
        expect(() => dragStartsImmediately(platform), returnsNormally);
      }
    });
  });
}
