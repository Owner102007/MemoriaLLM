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
        readerKeyAction(key: LogicalKeyboardKey.f3, shift: true, hasHits: true),
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

  group('пока читатель набирает текст', () {
    test('пробел и Backspace принадлежат полю, а не книге', () {
      // Регрессия S6.1: клавиатурный узел стоит над `Scaffold` и отвечал
      // «разобрано» на клавиши листания, не спросив, не набирает ли
      // читатель прямо сейчас. Фразу с пробелами в поиске было не
      // набрать, а набранное — не стереть.
      expect(
        readerKeyAction(key: LogicalKeyboardKey.space, typing: true),
        isNull,
      );
      expect(
        readerKeyAction(key: LogicalKeyboardKey.backspace, typing: true),
        isNull,
      );
    });

    test('и стрелки с Page тоже: ими двигают курсор', () {
      for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
      ]) {
        expect(readerKeyAction(key: key, typing: true), isNull, reason: '$key');
      }
    });

    test('Enter в поле разбирает само поле', () {
      expect(
        readerKeyAction(
          key: LogicalKeyboardKey.enter,
          searching: true,
          hasHits: true,
          typing: true,
        ),
        isNull,
      );
    });

    test('Esc оставлен панели поиска: ей ближе', () {
      expect(
        readerKeyAction(key: LogicalKeyboardKey.escape, typing: true),
        isNull,
      );
    });

    test('F3 и Ctrl+F поле не ждёт никогда — они работают', () {
      expect(
        readerKeyAction(
          key: LogicalKeyboardKey.f3,
          hasHits: true,
          typing: true,
        ),
        ReaderKeyAction.nextHit,
      );
      expect(
        readerKeyAction(
          key: LogicalKeyboardKey.keyF,
          control: true,
          typing: true,
        ),
        ReaderKeyAction.openSearch,
      );
    });
  });

  group('F-READ-35: чтение во весь экран', () {
    test('F-READ-35: F11 разворачивает чтение там, где есть окно', () {
      expect(
        readerKeyAction(key: LogicalKeyboardKey.f11, canFullScreen: true),
        ReaderKeyAction.fullScreen,
      );
    });

    test('F-READ-35: без окна F11 не значит ничего', () {
      expect(readerKeyAction(key: LogicalKeyboardKey.f11), isNull);
    });

    test('F-READ-35: F11 работает и из поля поиска — поле его не ждёт', () {
      expect(
        readerKeyAction(
          key: LogicalKeyboardKey.f11,
          typing: true,
          searching: true,
          canFullScreen: true,
        ),
        ReaderKeyAction.fullScreen,
      );
    });

    test('F-READ-35: Esc выводит из полного экрана последним', () {
      EscapeTarget target({
        bool searching = false,
        bool outline = false,
        bool selecting = false,
        bool panels = false,
        bool fullScreen = true,
      }) {
        return escapeTarget(
          searching: searching,
          outline: outline,
          selecting: selecting,
          panels: panels,
          fullScreen: fullScreen,
        );
      }

      expect(target(searching: true), EscapeTarget.search);
      expect(target(outline: true), EscapeTarget.outline);
      // Поиск ближе оглавления: он открыт поверх.
      expect(target(searching: true, outline: true), EscapeTarget.search);
      expect(target(selecting: true), EscapeTarget.page);
      expect(target(panels: true), EscapeTarget.page);
      expect(target(), EscapeTarget.fullScreen);
    });

    test('F-READ-35: в обычном окне Esc делает то же, что раньше', () {
      expect(
        escapeTarget(
          searching: false,
          outline: false,
          selecting: false,
          panels: false,
          fullScreen: false,
        ),
        EscapeTarget.page,
      );
    });
  });
}
