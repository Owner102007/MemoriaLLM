import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/ui/reader/key_bindings.dart';

/// F-READ-25, ALG-READ-05: таблица клавиш листания.
///
/// Таблица — это правило, а не виджет: что листает, что переезжает и что
/// назначить нельзя, проверяется числами. Экран с таблицей — в
/// `keys_screen_test`, клавиши в самой книге — в `reader_keys_test`.
void main() {
  const KeyStroke space = KeyStroke(LogicalKeyboardKey.space);
  const KeyStroke shiftSpace = KeyStroke(LogicalKeyboardKey.space, shift: true);
  const KeyStroke j = KeyStroke(LogicalKeyboardKey.keyJ);
  const KeyBindings standard = KeyBindings.standard;

  group('F-READ-25: таблица из коробки', () {
    test('вперёд — пробел, PgDn, → и ↓', () {
      expect(standard.forward.map(keyStrokeLabel).toList(), <String>[
        'Пробел',
        'PgDn',
        '→',
        '↓',
      ]);
    });

    test('назад — Shift+пробел, PgUp, ←, ↑ и Backspace', () {
      expect(standard.back.map(keyStrokeLabel).toList(), <String>[
        'Shift+Пробел',
        'PgUp',
        '←',
        '↑',
        'Backspace',
      ]);
    });

    test('пробел листает вперёд, а с Shift — назад', () {
      expect(standard.turnFor(LogicalKeyboardKey.space), TurnKey.forward);
      expect(
        standard.turnFor(LogicalKeyboardKey.space, shift: true),
        TurnKey.back,
      );
    });

    test('Shift не мешает клавише, у которой своего сочетания нет', () {
      // Так было и до таблицы: Shift+→ листает туда же, куда →.
      expect(
        standard.turnFor(LogicalKeyboardKey.arrowRight, shift: true),
        TurnKey.forward,
      );
      expect(
        standard.turnFor(LogicalKeyboardKey.pageUp, shift: true),
        TurnKey.back,
      );
    });

    test('посторонняя клавиша никуда не листает', () {
      expect(standard.turnFor(LogicalKeyboardKey.keyJ), isNull);
      expect(standard.ownerOf(j), isNull);
    });
  });

  group('F-READ-25: назначение', () {
    test('новая клавиша листает, таблица из коробки не тронута', () {
      final KeyBindings next = standard.assign(TurnKey.forward, j);

      expect(next.turnFor(LogicalKeyboardKey.keyJ), TurnKey.forward);
      expect(next.forward.last, j);
      expect(standard.turnFor(LogicalKeyboardKey.keyJ), isNull);
    });

    test('клавиша, занятая другим действием, переезжает', () {
      final KeyBindings next = standard.assign(TurnKey.back, space);

      expect(next.turnFor(LogicalKeyboardKey.space), TurnKey.back);
      expect(next.forward.contains(space), isFalse);
      expect(next.back.contains(space), isTrue);
      // Shift+пробел остался где был.
      expect(next.ownerOf(shiftSpace), TurnKey.back);
    });

    test('назначенная дважды клавиша записана один раз', () {
      final KeyBindings next = standard
          .assign(TurnKey.forward, j)
          .assign(TurnKey.forward, j);

      expect(next.forward.where((KeyStroke stroke) => stroke == j).length, 1);
    });

    test('убранная клавиша больше не листает', () {
      final KeyBindings next = standard.without(TurnKey.forward, space);

      expect(next.turnFor(LogicalKeyboardKey.space), isNull);
      expect(next.turnFor(LogicalKeyboardKey.pageDown), TurnKey.forward);
      // Shift+пробел — другая клавиша, и она на месте.
      expect(next.turnFor(LogicalKeyboardKey.space, shift: true), TurnKey.back);
    });

    test('у действия можно убрать все клавиши', () {
      KeyBindings next = standard;
      for (final KeyStroke stroke in standard.forward) {
        next = next.without(TurnKey.forward, stroke);
      }

      expect(next.forward, isEmpty);
      expect(next.back, standard.back);
    });
  });

  group('F-READ-25: запись в настройки', () {
    test('таблица переживает запись и чтение', () {
      final KeyBindings custom = standard
          .assign(TurnKey.forward, j)
          .without(TurnKey.forward, space)
          .assign(
            TurnKey.back,
            const KeyStroke(LogicalKeyboardKey.keyK, shift: true),
          );

      expect(KeyBindings.parse(standard.encode()), standard);
      expect(KeyBindings.parse(custom.encode()), custom);
    });

    test('нет настройки — таблица из коробки', () {
      expect(KeyBindings.parse(null), standard);
    });

    test('испорченная настройка — таблица из коробки', () {
      // Клавиатура, которая перестала листать из-за испорченной строки,
      // хуже забытой настройки.
      expect(KeyBindings.parse(''), standard);
      expect(KeyBindings.parse('мусор'), standard);
      expect(KeyBindings.parse('f:32'), standard);
    });

    test('пустые списки — законная настройка, а не порча', () {
      final KeyBindings empty = KeyBindings.parse('f:;b:');

      expect(empty.forward, isEmpty);
      expect(empty.back, isEmpty);
      expect(empty.turnFor(LogicalKeyboardKey.space), isNull);
    });

    test('нечитаемые и служебные клавиши из записи выпадают', () {
      final int escape = LogicalKeyboardKey.escape.keyId;
      final int f3 = LogicalKeyboardKey.f3.keyId;
      final KeyBindings parsed = KeyBindings.parse(
        'f:32,$escape,так,$f3,,32;b:s32',
      );

      expect(parsed.forward, <KeyStroke>[space]);
      expect(parsed.back, <KeyStroke>[shiftSpace]);
    });

    test('клавиша, записанная обоим действиям, остаётся у первого', () {
      final KeyBindings parsed = KeyBindings.parse('f:32;b:32,s32');

      expect(parsed.forward, <KeyStroke>[space]);
      expect(parsed.back, <KeyStroke>[shiftSpace]);
    });

    test('клавиша с незнакомым кодом сохраняется как есть', () {
      // Так приходят кнопки листалок и педалей, которых Flutter по имени
      // не знает.
      const int code = 0x1100000042;
      final KeyBindings parsed = KeyBindings.parse('f:$code;b:');

      expect(parsed.forward.single.key.keyId, code);
      expect(parsed.turnFor(const LogicalKeyboardKey(code)), TurnKey.forward);
      expect(KeyBindings.parse(parsed.encode()), parsed);
    });
  });

  group('F-READ-25: что можно назначить', () {
    test('клавиши со своим делом в чтении назначить нельзя', () {
      for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.numpadEnter,
        LogicalKeyboardKey.f3,
        LogicalKeyboardKey.f11,
        LogicalKeyboardKey.tab,
      ]) {
        expect(isAssignableKey(key), isFalse, reason: '$key');
        expect(isModifierKey(key), isFalse, reason: '$key');
      }
    });

    test('модификатор сам по себе — не клавиша', () {
      for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.shiftRight,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altRight,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.capsLock,
      ]) {
        expect(isAssignableKey(key), isFalse, reason: '$key');
        expect(isModifierKey(key), isTrue, reason: '$key');
      }
    });

    test('буквы, цифры и функциональные клавиши назначаются', () {
      for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.keyJ,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.f5,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.home,
      ]) {
        expect(isAssignableKey(key), isTrue, reason: '$key');
      }
    });
  });

  group('F-READ-25: подписи клавиш', () {
    test('буква подписана буквой, с Shift — сочетанием', () {
      expect(keyStrokeLabel(j), 'J');
      expect(
        keyStrokeLabel(const KeyStroke(LogicalKeyboardKey.keyJ, shift: true)),
        'Shift+J',
      );
    });

    test('у клавиши без имени подпись всё равно не пустая', () {
      const KeyStroke unknown = KeyStroke(LogicalKeyboardKey(0x1100000042));

      expect(keyStrokeLabel(unknown).trim(), isNotEmpty);
    });
  });
}
