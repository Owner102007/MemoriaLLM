import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/prompts/selection_prompt.dart';
import 'package:memoria/domain/settings/app_settings.dart';

import '../data/test_data.dart';

/// Промпты в базе: два уровня, надгробия и заведение из коробки.
void main() {
  late AppData data;

  setUp(() async {
    data = await openTestData();
    await data.library.save(testBook());
  });

  tearDown(() async {
    await data.close();
  });

  SelectionPrompt prompt({
    required String id,
    String name = 'Своё',
    String body = 'Объясни {{выделение}}',
    String? bookId,
    int position = 0,
    bool primary = false,
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

  test('промпты из коробки заводятся при открытии базы', () async {
    final List<SelectionPrompt> master = await data.prompts.masterPrompts();
    expect(master.map((SelectionPrompt p) => p.name), <String>[
      'Значение',
      'Перевод',
    ]);
    expect(await data.settings.read(SettingsKeys.promptsSeeded), 'true');
  });

  test('удалённый промпт из коробки не возвращается', () async {
    // Промпт из коробки — обычная запись, и удаление её обязано пережить
    // перезапуск приложения. Иначе «удалить» означало бы «спрятать до
    // следующего запуска».
    await data.prompts.deletePrompt(kTranslatePromptId);
    expect(await data.prompts.seedDefaultsOnce(), isFalse);
    final List<SelectionPrompt> master = await data.prompts.masterPrompts();
    expect(master.map((SelectionPrompt p) => p.id), <String>[
      kMeaningPromptId,
    ]);
  });

  test('набор книги главнее мастерского, а «как у всех» его стирает', () async {
    await data.prompts.savePrompt(
      prompt(id: 'book-prompt', name: 'Грамматика', bookId: 'book-1'),
    );
    PromptSet set = await data.prompts.watchPromptsFor('book-1').first;
    expect(set.fromBook, isTrue);
    expect(set.prompts.map((SelectionPrompt p) => p.name), <String>[
      'Грамматика',
    ]);

    await data.prompts.resetBookPrompts('book-1');
    set = await data.prompts.watchPromptsFor('book-1').first;
    expect(set.fromBook, isFalse);
    expect(set.prompts.map((SelectionPrompt p) => p.name), <String>[
      'Значение',
      'Перевод',
    ]);
  });

  test('чужой книге набор не достаётся', () async {
    await data.library.save(testBook(id: 'book-2', hash: 'hash-2'));
    await data.prompts.savePrompt(
      prompt(id: 'book-prompt', name: 'Грамматика', bookId: 'book-1'),
    );
    final PromptSet other = await data.prompts.watchPromptsFor('book-2').first;
    expect(other.fromBook, isFalse);
    expect(other.prompts, hasLength(2));
  });

  test('удаление — надгробие, а не DELETE', () async {
    await data.prompts.savePrompt(prompt(id: 'mine', name: 'Своё'));
    await data.prompts.deletePrompt('mine');
    expect(
      (await data.prompts.masterPrompts()).map((SelectionPrompt p) => p.id),
      isNot(contains('mine')),
    );
    // Строка остаётся в таблице: иначе удаление на телефоне никогда не
    // доехало бы до ПК.
    final List<QueryRow> rows = await data.database
        .customSelect('SELECT id FROM selection_prompts WHERE is_deleted = 1')
        .get();
    expect(rows, isNotEmpty);
  });

  test('правка промпта переписывает метку изменения', () async {
    await data.prompts.savePrompt(prompt(id: 'mine', name: 'Своё'));
    final String? before = await _hlcOf(data, 'mine');
    await data.prompts.savePrompt(
      prompt(id: 'mine', name: 'Своё, но лучше'),
    );
    final String? after = await _hlcOf(data, 'mine');
    expect(after, isNotNull);
    expect(after, isNot(before));
    final List<SelectionPrompt> master = await data.prompts.masterPrompts();
    expect(
      master.firstWhere((SelectionPrompt p) => p.id == 'mine').name,
      'Своё, но лучше',
    );
  });

  test('удаление книги уносит её набор', () async {
    await data.prompts.savePrompt(
      prompt(id: 'book-prompt', bookId: 'book-1'),
    );
    await data.library.delete('book-1');
    await data.library.purgeDeleted();
    final List<QueryRow> rows = await data.database
        .customSelect(
          'SELECT id FROM selection_prompts WHERE id = ?',
          variables: <Variable<Object>>[const Variable<String>('book-prompt')],
        )
        .get();
    expect(rows, isEmpty);
  });
}

Future<String?> _hlcOf(AppData data, String id) async {
  final List<QueryRow> rows = await data.database
      .customSelect(
        'SELECT hlc FROM selection_prompts WHERE id = ?',
        variables: <Variable<Object>>[Variable<String>(id)],
      )
      .get();
  return rows.isEmpty ? null : rows.first.read<String>('hlc');
}
