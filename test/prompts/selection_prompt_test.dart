import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/prompts/selection_prompt.dart';

/// Промпты к выделению: разбор мест подстановки и слияние двух уровней.
///
/// Всё здесь — чистая математика над строками и списками, поэтому
/// проверяется числами, а не на живой базе и не на экране.
SelectionPrompt _prompt({
  String id = 'p',
  String name = 'Значение',
  String body = 'Объясни {{выделение}}',
  int position = 0,
  bool primary = false,
  String? bookId,
}) {
  return SelectionPrompt(
    id: id,
    bookId: bookId,
    name: name,
    body: body,
    position: position,
    isPrimary: primary,
    createdAt: DateTime.utc(2026, 9, 6),
    updatedAt: DateTime.utc(2026, 9, 6),
  );
}

void main() {
  group('разбор мест подстановки', () {
    test('{{выделение}} обязательно', () {
      final PromptCheck check = checkPrompt(
        name: 'Этимология',
        body: 'Расскажи про происхождение этого слова',
      );
      expect(check.isValid, isFalse);
      expect(check.problems, contains(PromptProblem.noSelection));
    });

    test('промпт с выделением сохраняется', () {
      final PromptCheck check = checkPrompt(
        name: 'Этимология',
        body: 'Откуда взялось «{{выделение}}»?',
      );
      expect(check.isValid, isTrue);
      expect(check.slots, <PromptSlot>{PromptSlot.selection});
    });

    test('неизвестное место подстановки — ошибка, а не молчание', () {
      final PromptCheck check = checkPrompt(
        name: 'Своё',
        body: 'Объясни {{выделение}} на языке {{язык_читателя}}',
      );
      expect(check.isValid, isFalse);
      expect(check.problems, contains(PromptProblem.unknownSlot));
      expect(check.unknownSlots, <String>['язык_читателя']);
    });

    test('пустое имя и пустой текст не проходят', () {
      final PromptCheck empty = checkPrompt(name: '  ', body: '   ');
      expect(empty.problems, contains(PromptProblem.emptyName));
      expect(empty.problems, contains(PromptProblem.emptyBody));
    });

    test('нужен ли промпту абзац — видно из его текста', () {
      expect(
        checkPrompt(name: 'a', body: '{{выделение}}').needsContext,
        isFalse,
      );
      expect(
        checkPrompt(
          name: 'a',
          body: '{{выделение}} в отрывке {{контекст}}',
        ).needsContext,
        isTrue,
      );
    });

    test('обычные скобки в тексте промпта — не место подстановки', () {
      final PromptCheck check = checkPrompt(
        name: 'a',
        body: 'Объясни {{выделение}} (коротко, в {скобках})',
      );
      expect(check.isValid, isTrue);
      expect(check.unknownSlots, isEmpty);
    });
  });

  group('подстановка', () {
    test('подставляется всё, что дали', () {
      final String filled = fillPrompt(
        'Переведи «{{выделение}}» с {{язык_книги}} на {{мой_язык}}. '
        'Отрывок: {{контекст}}',
        selection: 'ineffable',
        context: 'It was an ineffable joy.',
        bookLanguage: 'английского',
        myLanguage: 'русский',
      );
      expect(filled, contains('«ineffable»'));
      expect(filled, contains('с английского на русский'));
      expect(filled, contains('It was an ineffable joy.'));
    });

    test('пустая подстановка не оставляет дыры', () {
      // Без контекста промпт не должен превращаться в «Отрывок:» с
      // пустотой после двоеточия: модель отвечает на это хуже, чем на
      // короткий вопрос без отрывка.
      final String filled = fillPrompt(
        'Объясни «{{выделение}}».\nОтрывок: {{контекст}}',
        selection: 'слово',
      );
      expect(filled, 'Объясни «слово».');
    });

    test('неизвестное место подстановки остаётся как есть', () {
      // Сохранить такой промпт нельзя, но если он всё-таки приехал с
      // устройства с версией новее, текст не должен молча испортиться.
      final String filled = fillPrompt(
        '{{выделение}} и {{завтрашнее_место}}',
        selection: 'слово',
      );
      expect(filled, contains('{{завтрашнее_место}}'));
    });
  });

  group('слияние двух уровней', () {
    test('набор книги главнее мастерского целиком', () {
      final PromptSet set = mergePromptLevels(
        master: <SelectionPrompt>[
          _prompt(id: 'm1', name: 'Значение'),
          _prompt(id: 'm2', name: 'Перевод', position: 1),
        ],
        book: <SelectionPrompt>[
          _prompt(id: 'b1', name: 'Грамматика', bookId: 'book-1'),
        ],
      );
      expect(set.fromBook, isTrue);
      expect(set.prompts.map((SelectionPrompt p) => p.name), <String>[
        'Грамматика',
      ]);
    });

    test('без набора книги берётся мастерский', () {
      final PromptSet set = mergePromptLevels(
        master: <SelectionPrompt>[_prompt(id: 'm1')],
        book: const <SelectionPrompt>[],
      );
      expect(set.fromBook, isFalse);
      expect(set.prompts.single.id, 'm1');
    });

    test('порядок задаёт место, а при равных — имя', () {
      final PromptSet set = mergePromptLevels(
        master: <SelectionPrompt>[
          _prompt(id: 'c', name: 'Юля', position: 2),
          _prompt(id: 'a', name: 'Аня'),
          _prompt(id: 'b', name: 'Боря'),
        ],
        book: const <SelectionPrompt>[],
      );
      expect(set.prompts.map((SelectionPrompt p) => p.name), <String>[
        'Аня',
        'Боря',
        'Юля',
      ]);
    });

    test('больше пяти в панель не попадает', () {
      final PromptSet set = mergePromptLevels(
        master: <SelectionPrompt>[
          for (int i = 0; i < 8; i++)
            _prompt(id: 'p$i', name: 'Промпт $i', position: i),
        ],
        book: const <SelectionPrompt>[],
      );
      expect(set.prompts, hasLength(kMaxSelectionPrompts));
      expect(set.hasRoom, isFalse);
    });

    test('основной остаётся ровно один', () {
      // Двух основных в базе быть не может ровно до первого слияния
      // с другого устройства — и после него набор обязан остаться
      // осмысленным.
      final PromptSet set = mergePromptLevels(
        master: <SelectionPrompt>[
          _prompt(id: 'a', name: 'Аня', primary: true),
          _prompt(id: 'b', name: 'Боря', position: 1, primary: true),
        ],
        book: const <SelectionPrompt>[],
      );
      expect(
        set.prompts
            .where((SelectionPrompt p) => p.isPrimary)
            .map((SelectionPrompt p) => p.id),
        <String>['a'],
      );
      expect(set.primary!.id, 'a');
    });

    test('без пометки основным становится первый', () {
      final PromptSet set = mergePromptLevels(
        master: <SelectionPrompt>[
          _prompt(id: 'a', name: 'Аня'),
          _prompt(id: 'b', name: 'Боря', position: 1),
        ],
        book: const <SelectionPrompt>[],
      );
      expect(set.primary!.id, 'a');
      expect(set.prompts.first.isPrimary, isTrue);
    });
  });

  group('поправка для книги', () {
    test('мастер-набор копируется книге новыми записями', () {
      int counter = 0;
      final List<SelectionPrompt> forked = forkPromptsForBook(
        master: <SelectionPrompt>[
          _prompt(id: 'm1', name: 'Значение', primary: true),
          _prompt(id: 'm2', name: 'Перевод', position: 1),
        ],
        bookId: 'book-1',
        newId: () => 'new-${counter++}',
        now: DateTime.utc(2026, 9, 6),
      );
      expect(forked.map((SelectionPrompt p) => p.bookId), <String>[
        'book-1',
        'book-1',
      ]);
      // Идентификаторы новые: строка уровня книги — отдельная запись,
      // которая уедет в синхронизацию сама по себе, а не двойник
      // мастерской.
      expect(forked.map((SelectionPrompt p) => p.id), <String>[
        'new-0',
        'new-1',
      ]);
      expect(forked.map((SelectionPrompt p) => p.name), <String>[
        'Значение',
        'Перевод',
      ]);
      expect(forked.first.isPrimary, isTrue);
    });

    test('места перенумеровываются подряд', () {
      final List<SelectionPrompt> forked = forkPromptsForBook(
        master: <SelectionPrompt>[
          _prompt(id: 'm1', name: 'Б', position: 7),
          _prompt(id: 'm2', name: 'А', position: 3),
        ],
        bookId: 'book-1',
        newId: () => 'x',
        now: DateTime.utc(2026, 9, 6),
      );
      expect(forked.map((SelectionPrompt p) => p.position), <int>[0, 1]);
      expect(forked.first.name, 'А');
    });
  });

  group('промпты из коробки', () {
    test('их два, оба годные, и первый — основной', () {
      final List<SelectionPrompt> defaults = defaultPrompts(
        now: DateTime.utc(2026, 9, 6),
      );
      expect(defaults, hasLength(2));
      for (final SelectionPrompt prompt in defaults) {
        expect(
          prompt.check.isValid,
          isTrue,
          reason: 'промпт «${prompt.name}» из коробки обязан сохраняться',
        );
      }
      expect(defaults.first.isPrimary, isTrue);
      expect(defaults.last.isPrimary, isFalse);
    });

    test('идентификаторы постоянные', () {
      // Промпты синхронизируются, а заводит их каждое устройство само.
      // Со случайными идентификаторами телефон и ПК завели бы по своей
      // паре, и слияние отдало бы читателю четыре промпта вместо двух.
      final List<SelectionPrompt> first = defaultPrompts(
        now: DateTime.utc(2026, 9, 6),
      );
      final List<SelectionPrompt> second = defaultPrompts(
        now: DateTime.utc(2027),
      );
      expect(first.map((SelectionPrompt p) => p.id), <String>[
        kMeaningPromptId,
        kTranslatePromptId,
      ]);
      expect(
        second.map((SelectionPrompt p) => p.id),
        first.map((SelectionPrompt p) => p.id),
      );
    });

    test('оба просят контекст и оба знают языки', () {
      for (final SelectionPrompt prompt in defaultPrompts(
        now: DateTime.utc(2026, 9, 6),
      )) {
        expect(prompt.check.needsContext, isTrue);
        expect(prompt.check.slots, contains(PromptSlot.myLanguage));
      }
    });
  });
}
