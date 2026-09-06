import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/ui/reader/reader_keys.dart';

/// Раскладка клавиш чтения.
///
/// Проверяется таблицей, а не тыканьем в живой экран: клавиша — это
/// правило, и ошибка в нём выглядит как «приложение меня не слышит».
void main() {
  group('листание', () {
    test('вперёд листают стрелки, пробел и PageDown', () {
      for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.space,
      ]) {
        expect(readerKeyAction(key: key), ReaderKeyAction.next, reason: '$key');
      }
    });

    test('назад листают стрелки, PageUp и Shift+пробел', () {
      for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.backspace,
      ]) {
        expect(
          readerKeyAction(key: key),
          ReaderKeyAction.previous,
          reason: '$key',
        );
      }
      expect(
        readerKeyAction(key: LogicalKeyboardKey.space, shift: true),
        ReaderKeyAction.previous,
      );
    });

    test('клавиши листают и при выделенном тексте', () {
      // Того же требует и главное замечание владельца: выделение не
      // отбирает у читателя книгу. У раскладки на этот счёт нет ни
      // одного условия — и это проверяется тем, что признака выделения в
      // ней просто нет.
      expect(
        readerKeyAction(key: LogicalKeyboardKey.arrowRight, searching: true),
        ReaderKeyAction.next,
      );
    });
  });

  group('поиск', () {
    test('Ctrl+F открывает поиск', () {
      expect(
        readerKeyAction(key: LogicalKeyboardKey.keyF, control: true),
        ReaderKeyAction.openSearch,
      );
    });

    test('Ctrl с чем угодно другим ничего не значит', () {
      // Иначе Ctrl+стрелка листала бы книгу, а это системный жест
      // перемещения по словам.
      expect(
        readerKeyAction(key: LogicalKeyboardKey.arrowRight, control: true),
        isNull,
      );
      expect(
        readerKeyAction(key: LogicalKeyboardKey.escape, control: true),
        isNull,
      );
    });

    test('F3 ведёт по совпадениям, а Shift+F3 — назад', () {
      expect(
        readerKeyAction(key: LogicalKeyboardKey.f3, hasHits: true),
        ReaderKeyAction.nextHit,
      );
      expect(
        readerKeyAction(
          key: LogicalKeyboardKey.f3,
          shift: true,
          hasHits: true,
        ),
        ReaderKeyAction.previousHit,
      );
    });

    test('F3 без найденного молчит', () {
      expect(readerKeyAction(key: LogicalKeyboardKey.f3), isNull);
    });

    test('Enter — следующее совпадение, только пока ищут', () {
      expect(
        readerKeyAction(
          key: LogicalKeyboardKey.enter,
          searching: true,
          hasHits: true,
        ),
        ReaderKeyAction.nextHit,
      );
      // В обычном чтении Enter не листает: клавиша, делающая разное в
      // разных местах, хуже клавиши, не делающей ничего.
      expect(
        readerKeyAction(key: LogicalKeyboardKey.enter, hasHits: true),
        isNull,
      );
    });
  });

  test('Esc закрывает то, что открыто', () {
    expect(
      readerKeyAction(key: LogicalKeyboardKey.escape),
      ReaderKeyAction.dismiss,
    );
  });

  test('обычная буква не значит ничего', () {
    expect(readerKeyAction(key: LogicalKeyboardKey.keyF), isNull);
    expect(readerKeyAction(key: LogicalKeyboardKey.keyG), isNull);
  });
}
