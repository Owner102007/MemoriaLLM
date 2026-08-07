import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/llm/llm_query.dart';

import 'test_data.dart';

LlmQuery _query({
  String id = 'q-1',
  LlmTask task = LlmTask.meaning,
  String selection = 'ланиты',
  String? context = 'Её ланиты пылали',
  String? answer = 'Щёки, устаревшее',
  String? targetLanguage,
}) {
  return LlmQuery(
    id: id,
    task: task,
    selection: selection,
    createdAt: DateTime.utc(2026, 8, 5),
    bookId: 'book-1',
    context: context,
    sourceLanguage: 'ru',
    targetLanguage: targetLanguage,
    answer: answer,
    source: LlmSource.cloud,
    model: 'llama-3.1-8b',
    latencyMs: 420,
  );
}

void main() {
  late AppData data;

  setUp(() async {
    data = await openTestData();
    await data.library.save(testBook());
  });

  tearDown(() async {
    await data.close();
  });

  test('запись сохраняется со всеми полями', () async {
    await data.llmHistory.save(_query());
    final Stream<List<LlmQuery>> queries = data.llmHistory.watchForBook(
      'book-1',
    );
    final List<LlmQuery> history = await queries.first;

    expect(history, hasLength(1));
    expect(history.single.task, LlmTask.meaning);
    expect(history.single.source, LlmSource.cloud);
    expect(history.single.model, 'llama-3.1-8b');
    expect(history.single.latencyMs, 420);
    expect(history.single.answer, 'Щёки, устаревшее');
  });

  test('готовый ответ находится в кэше', () async {
    await data.llmHistory.save(_query());
    final LlmQuery? hit = await data.llmHistory.cached(
      task: LlmTask.meaning,
      selection: 'ланиты',
      context: 'Её ланиты пылали',
    );

    expect(hit, isNotNull);
    expect(hit?.answer, 'Щёки, устаревшее');
  });

  test('другой контекст — другой ответ, кэш не срабатывает', () async {
    await data.llmHistory.save(_query());
    final LlmQuery? miss = await data.llmHistory.cached(
      task: LlmTask.meaning,
      selection: 'ланиты',
      context: 'совсем другой абзац',
    );

    expect(miss, isNull);
  });

  test('перевод и объяснение не путаются между собой', () async {
    await data.llmHistory.save(_query());
    final LlmQuery? miss = await data.llmHistory.cached(
      task: LlmTask.translate,
      selection: 'ланиты',
      context: 'Её ланиты пылали',
    );

    expect(miss, isNull);
  });

  test('неудачный запрос в кэш не попадает', () async {
    await data.llmHistory.save(_query(id: 'q-fail', answer: null));
    final LlmQuery? miss = await data.llmHistory.cached(
      task: LlmTask.meaning,
      selection: 'ланиты',
      context: 'Её ланиты пылали',
    );

    expect(miss, isNull);
  });

  test('запрос без контекста ищется по пустому контексту', () async {
    await data.llmHistory.save(_query(id: 'q-bare', context: null));
    final LlmQuery? hit = await data.llmHistory.cached(
      task: LlmTask.meaning,
      selection: 'ланиты',
    );

    expect(hit?.id, 'q-bare');
  });

  test('удалённая запись не всплывает в кэше', () async {
    await data.llmHistory.save(_query());
    await data.llmHistory.delete('q-1');

    final LlmQuery? miss = await data.llmHistory.cached(
      task: LlmTask.meaning,
      selection: 'ланиты',
      context: 'Её ланиты пылали',
    );
    expect(miss, isNull);
  });
}
