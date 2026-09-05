/// Промпты к выделению — чистые правила без базы и без Flutter.
///
/// **Спрашивает читатель, а не мы за него** (решение владельца,
/// 06.09.2026). Meaning и Translate перестали быть двумя вшитыми кнопками
/// и стали двумя записями из коробки: их можно править, переименовывать и
/// удалять, а рядом заводить свои — «словарная статья Кембриджа»,
/// «этимология», «разбери грамматику». Приложение знает про промпт ровно
/// две вещи: как он называется (это подпись на кнопке) и что подставить
/// в его текст.
///
/// Сами ответы модели появятся в S8. Здесь — модель данных, разбор мест
/// подстановки и слияние двух уровней: всё, что нельзя завести позже, не
/// переписывая таблицу с данными живых читателей.
library;

/// Сколько промптов помещается в панель над выделением.
///
/// Пять — не круглое число, а потолок: за ним панель перестаёт помещаться
/// в телефон в портрете и превращается в меню, а меню над выделением —
/// лишнее нажатие на каждое слово.
const int kMaxSelectionPrompts = 5;

/// Идентификатор промпта «Значение» из коробки.
const String kMeaningPromptId = 'prompt-meaning';

/// Идентификатор промпта «Перевод» из коробки.
const String kTranslatePromptId = 'prompt-translate';

/// Место подстановки в тексте промпта.
enum PromptSlot {
  /// Выделенный текст. Обязательное: без него модель получит вопрос без
  /// вопроса.
  selection('выделение'),

  /// Абзац вокруг выделения. Если этого места в промпте нет, абзац не
  /// извлекается вовсе — короткий запрос дешевле и быстрее.
  context('контекст'),

  /// Язык книги.
  bookLanguage('язык_книги'),

  /// Язык читателя.
  myLanguage('мой_язык');

  const PromptSlot(this.token);

  /// Имя внутри двойных скобок.
  final String token;

  /// Как место подстановки выглядит в тексте промпта.
  String get placeholder => '{{$token}}';
}

/// Что не так с промптом.
enum PromptProblem {
  /// Имя пустое: подпись на кнопке взять неоткуда.
  emptyName,

  /// Текст пустой.
  emptyBody,

  /// Нет обязательного `{{выделение}}`.
  noSelection,

  /// Встретилось неизвестное место подстановки.
  unknownSlot,
}

/// Человеческое объяснение того, почему промпт не сохраняется.
///
/// Живёт в домене, потому что спрашивать будут двое: редактор промптов
/// (S8) и тесты, которые проверяют разбор.
String describePromptProblem(PromptProblem problem) {
  switch (problem) {
    case PromptProblem.emptyName:
      return 'У промпта нет имени, а имя — это подпись на кнопке.';
    case PromptProblem.emptyBody:
      return 'Текст промпта пуст.';
    case PromptProblem.noSelection:
      return 'В тексте нет места подстановки {{выделение}}. Без него '
          'модель получит вопрос без самого вопроса.';
    case PromptProblem.unknownSlot:
      return 'Встретилось неизвестное место подстановки. Работают только '
          '{{выделение}}, {{контекст}}, {{язык_книги}} и {{мой_язык}}.';
  }
}

/// Итог разбора текста промпта.
class PromptCheck {
  /// Создаёт итог.
  const PromptCheck({
    required this.slots,
    required this.unknownSlots,
    required this.problems,
  });

  /// Какие места подстановки нашлись.
  final Set<PromptSlot> slots;

  /// Имена мест подстановки, которых мы не знаем, — как они написаны.
  final List<String> unknownSlots;

  /// Что мешает сохранить промпт. Пусто — можно сохранять.
  final List<PromptProblem> problems;

  /// Промпт годится к сохранению.
  bool get isValid => problems.isEmpty;

  /// Нужен ли этому промпту абзац вокруг выделения.
  ///
  /// Единственный потребитель — извлечение контекста: разбирать страницу
  /// по координатам ради промпта, которому абзац не нужен, значит платить
  /// за то, что не спросили.
  bool get needsContext => slots.contains(PromptSlot.context);

  @override
  String toString() =>
      'PromptCheck(мест: ${slots.length}, проблем: ${problems.length})';
}

/// Разбирает промпт и говорит, годится ли он.
///
/// Разбор терпим к содержимому вокруг: текст промпта — это текст, в нём
/// могут быть любые скобки. Ошибкой считается только то, что выглядит
/// как место подстановки (`{{…}}`), но им не является.
PromptCheck checkPrompt({required String name, required String body}) {
  final Set<PromptSlot> slots = <PromptSlot>{};
  final List<String> unknown = <String>[];
  final List<PromptProblem> problems = <PromptProblem>[];

  for (final RegExpMatch match in _slotPattern.allMatches(body)) {
    final String token = (match.group(1) ?? '').trim();
    final PromptSlot? slot = _slotByToken(token);
    if (slot == null) {
      unknown.add(token);
    } else {
      slots.add(slot);
    }
  }

  if (name.trim().isEmpty) {
    problems.add(PromptProblem.emptyName);
  }
  if (body.trim().isEmpty) {
    problems.add(PromptProblem.emptyBody);
  }
  if (!slots.contains(PromptSlot.selection)) {
    problems.add(PromptProblem.noSelection);
  }
  if (unknown.isNotEmpty) {
    problems.add(PromptProblem.unknownSlot);
  }

  return PromptCheck(
    slots: slots,
    unknownSlots: List<String>.unmodifiable(unknown),
    problems: List<PromptProblem>.unmodifiable(problems),
  );
}

/// Подставляет в промпт то, что нашлось.
///
/// Пустое значение не оставляет после себя дыру: место подстановки
/// исчезает вместе с лишними пробелами вокруг него. Модель, получившая
/// «Переведи «слово» с языка  на », отвечает хуже, чем модель, получившая
/// «Переведи «слово»».
String fillPrompt(
  String body, {
  required String selection,
  String? context,
  String? bookLanguage,
  String? myLanguage,
}) {
  final Map<PromptSlot, String> values = <PromptSlot, String>{
    PromptSlot.selection: selection,
    PromptSlot.context: context ?? '',
    PromptSlot.bookLanguage: bookLanguage ?? '',
    PromptSlot.myLanguage: myLanguage ?? '',
  };
  final String filled = body.replaceAllMapped(_slotPattern, (Match match) {
    final String token = (match.group(1) ?? '').trim();
    final PromptSlot? slot = _slotByToken(token);
    if (slot == null) {
      return match.group(0)!;
    }
    return values[slot] ?? '';
  });
  return _tidy(filled);
}

/// Промпт к выделению.
class SelectionPrompt {
  /// Создаёт промпт.
  const SelectionPrompt({
    required this.id,
    required this.name,
    required this.body,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
    this.bookId,
    this.isPrimary = false,
  });

  /// Идентификатор.
  final String id;

  /// Книга, за которой закреплён промпт. `null` — мастер-набор.
  final String? bookId;

  /// Имя. Оно же подпись на кнопке в панели над выделением.
  final String name;

  /// Текст с местами подстановки.
  final String body;

  /// Порядок кнопок. Меньше — левее.
  final int position;

  /// Основной промпт набора.
  final bool isPrimary;

  /// Когда заведён.
  final DateTime createdAt;

  /// Когда правился.
  final DateTime updatedAt;

  /// Уровень книги, а не мастер-набор.
  bool get isBookLevel => bookId != null;

  /// Разбор текста этого промпта.
  PromptCheck get check => checkPrompt(name: name, body: body);

  /// Копия с изменениями.
  SelectionPrompt copyWith({
    String? id,
    String? bookId,
    bool dropBookId = false,
    String? name,
    String? body,
    int? position,
    bool? isPrimary,
    DateTime? updatedAt,
  }) {
    return SelectionPrompt(
      id: id ?? this.id,
      bookId: dropBookId ? null : (bookId ?? this.bookId),
      name: name ?? this.name,
      body: body ?? this.body,
      position: position ?? this.position,
      isPrimary: isPrimary ?? this.isPrimary,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'SelectionPrompt($name, книга: $bookId)';
}

/// Набор промптов, с которым открыт экран чтения.
class PromptSet {
  /// Создаёт набор.
  const PromptSet({required this.prompts, required this.fromBook});

  /// Пустой набор.
  static const PromptSet empty = PromptSet(
    prompts: <SelectionPrompt>[],
    fromBook: false,
  );

  /// Промпты по порядку кнопок.
  final List<SelectionPrompt> prompts;

  /// Набор принадлежит книге, а не мастеру.
  ///
  /// Ровно это и включает в чтении кнопку «вернуть как у всех»: пока
  /// набор мастерский, возвращать нечего.
  final bool fromBook;

  /// Основной промпт набора.
  SelectionPrompt? get primary {
    for (final SelectionPrompt prompt in prompts) {
      if (prompt.isPrimary) {
        return prompt;
      }
    }
    return prompts.isEmpty ? null : prompts.first;
  }

  /// Есть ли куда добавить ещё один.
  bool get hasRoom => prompts.length < kMaxSelectionPrompts;
}

/// Складывает два уровня в один набор.
///
/// **Книга главнее мастера, и главнее целиком.** Стоит читателю изменить
/// хоть один промпт для этой книги — за ней закрепляется весь набор, а
/// «вернуть как у всех» стирает его и возвращает мастерский. Частичного
/// наследования нет намеренно: набор из «трёх мастерских и одного
/// своего» пришлось бы сливать по строкам на двух устройствах сразу, а
/// это ровно тот случай, где CRDT честно отдаёт непредсказуемый порядок
/// кнопок. Цена решения записана в известные проблемы: новый
/// мастер-промпт в книгу с собственным набором сам не приедет.
///
/// Порядок кнопок задаёт [SelectionPrompt.position]; при равных местах
/// разводит имя, чтобы набор не перетасовывался от запуска к запуску.
/// Промптов берётся не больше [kMaxSelectionPrompts] — потолок держится
/// здесь, а не в интерфейсе: база могла приехать с устройства, где стоит
/// версия новее.
PromptSet mergePromptLevels({
  required List<SelectionPrompt> master,
  required List<SelectionPrompt> book,
}) {
  final List<SelectionPrompt> chosen = book.isNotEmpty ? book : master;
  final List<SelectionPrompt> sorted = List<SelectionPrompt>.of(chosen)
    ..sort(_byPosition);
  final List<SelectionPrompt> capped = sorted.length > kMaxSelectionPrompts
      ? sorted.sublist(0, kMaxSelectionPrompts)
      : sorted;
  return PromptSet(
    prompts: List<SelectionPrompt>.unmodifiable(_singlePrimary(capped)),
    fromBook: book.isNotEmpty,
  );
}

/// Копирует мастер-набор на уровень книги.
///
/// Это и есть «поправка для книги»: первая же правка в чтении делает
/// книге собственный набор. Идентификаторы берутся новые — строка уровня
/// книги не двойник мастерской, а отдельная запись, которая уедет в
/// синхронизацию сама по себе.
List<SelectionPrompt> forkPromptsForBook({
  required List<SelectionPrompt> master,
  required String bookId,
  required String Function() newId,
  required DateTime now,
}) {
  final List<SelectionPrompt> sorted = List<SelectionPrompt>.of(master)
    ..sort(_byPosition);
  final List<SelectionPrompt> forked = <SelectionPrompt>[];
  for (int i = 0; i < sorted.length && i < kMaxSelectionPrompts; i++) {
    final SelectionPrompt source = sorted[i];
    forked.add(
      SelectionPrompt(
        id: newId(),
        bookId: bookId,
        name: source.name,
        body: source.body,
        position: i,
        isPrimary: source.isPrimary,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
  return _singlePrimary(forked);
}

/// Промпты из коробки.
///
/// Заводятся **записями**, а не кодом: их можно править, переименовать и
/// удалить, как любой свой. Отсюда и требование к заведению — один раз
/// за жизнь базы: читатель, удаливший «Перевод», не должен находить его
/// снова после перезапуска.
///
/// **Идентификаторы у них постоянные, а не случайные.** Промпты
/// синхронизируются, а заводит их каждое устройство само, при первом
/// запуске: со случайными идентификаторами телефон и ПК завели бы по
/// своей паре, и слияние в S11 отдало бы читателю четыре промпта вместо
/// двух. С постоянными строки совпадают, слияние схлопывает их в одну, а
/// правка побеждает по метке HLC — как и должно быть у CRDT.
List<SelectionPrompt> defaultPrompts({required DateTime now}) {
  return <SelectionPrompt>[
    SelectionPrompt(
      id: kMeaningPromptId,
      name: 'Значение',
      body:
          'Объясни значение выражения «{{выделение}}» ({{язык_книги}}) так, '
          'как оно употреблено здесь: {{контекст}}\n'
          'Дай короткое определение, разбор грамматики, если он уместен, '
          'и один пример. Отвечай на языке {{мой_язык}}.',
      position: 0,
      isPrimary: true,
      createdAt: now,
      updatedAt: now,
    ),
    SelectionPrompt(
      id: kTranslatePromptId,
      name: 'Перевод',
      body:
          'Переведи «{{выделение}}» с языка {{язык_книги}} на {{мой_язык}}.\n'
          'Вот отрывок, в котором это встретилось: {{контекст}}\n'
          'Переводи по смыслу отрывка, а не по словарю; неочевидные места '
          'поясни одной фразой.',
      position: 1,
      createdAt: now,
      updatedAt: now,
    ),
  ];
}

/// Промпты читателя. Реализация живёт в `infrastructure`.
abstract interface class PromptRepository {
  /// Живой мастер-набор.
  Stream<List<SelectionPrompt>> watchMasterPrompts();

  /// Разовый снимок мастер-набора.
  Future<List<SelectionPrompt>> masterPrompts();

  /// Разовый снимок набора книги. Пусто — у книги своего набора нет.
  Future<List<SelectionPrompt>> bookPrompts(String bookId);

  /// Живой набор для чтения: уровень книги, если он есть, иначе мастер.
  Stream<PromptSet> watchPromptsFor(String bookId);

  /// Добавляет или обновляет промпт.
  Future<void> savePrompt(SelectionPrompt prompt);

  /// Помечает промпт удалённым.
  Future<void> deletePrompt(String id);

  /// Стирает набор книги — «вернуть как у всех».
  Future<void> resetBookPrompts(String bookId);

  /// Заводит промпты из коробки, если этого ещё не делали.
  ///
  /// Возвращает `true`, если записи заведены именно сейчас.
  Future<bool> seedDefaultsOnce();
}

/// Один основной на набор.
///
/// База — место, куда данные приезжают с другого устройства, и двух
/// основных промптов там не может быть ровно до первого слияния. Правило
/// живёт в домене, потому что чинить набор придётся и показу, и
/// редактору: первый помеченный остаётся, с остальных пометка снимается,
/// а если её нет ни у кого — основным становится первый.
List<SelectionPrompt> _singlePrimary(List<SelectionPrompt> prompts) {
  if (prompts.isEmpty) {
    return prompts;
  }
  int primaryAt = -1;
  for (int i = 0; i < prompts.length; i++) {
    if (prompts[i].isPrimary) {
      primaryAt = i;
      break;
    }
  }
  final int chosen = primaryAt < 0 ? 0 : primaryAt;
  final List<SelectionPrompt> fixed = <SelectionPrompt>[];
  for (int i = 0; i < prompts.length; i++) {
    final SelectionPrompt prompt = prompts[i];
    if (prompt.isPrimary == (i == chosen)) {
      fixed.add(prompt);
    } else {
      fixed.add(prompt.copyWith(isPrimary: i == chosen));
    }
  }
  return fixed;
}

int _byPosition(SelectionPrompt a, SelectionPrompt b) {
  final int byPosition = a.position.compareTo(b.position);
  if (byPosition != 0) {
    return byPosition;
  }
  return a.name.compareTo(b.name);
}

PromptSlot? _slotByToken(String token) {
  for (final PromptSlot slot in PromptSlot.values) {
    if (slot.token == token) {
      return slot;
    }
  }
  return null;
}

/// Убирает следы исчезнувших мест подстановки.
///
/// Пустая подстановка оставляет за собой двойные пробелы, повисшие скобки
/// и строки из одних знаков препинания. Чистка нарочно скромная: трогать
/// текст читателя сильнее, чем нужно, — значит спорить с ним.
String _tidy(String value) {
  final List<String> lines = value.split('\n');
  final List<String> kept = <String>[];
  for (final String line in lines) {
    final String squeezed = line.replaceAll(_spaces, ' ').trim();
    final String cleaned = squeezed
        .replaceAll(_emptyQuotes, '')
        .replaceAll(_danglingPunctuation, '')
        .replaceAll(_spaceBeforePunctuation, '')
        .trim();
    if (cleaned.isEmpty || _onlyPunctuation.hasMatch(cleaned)) {
      continue;
    }
    kept.add(cleaned);
  }
  return kept.join('\n');
}

final RegExp _slotPattern = RegExp(r'\{\{([^{}]*)\}\}');
final RegExp _spaces = RegExp(r'[ \t]+');
final RegExp _emptyQuotes = RegExp('«»|""|\'\'');
final RegExp _danglingPunctuation = RegExp(r'\(\s*\)|\[\s*\]');
final RegExp _spaceBeforePunctuation = RegExp(r'\s+(?=[,.;:!?])');
final RegExp _onlyPunctuation = RegExp(r'^[\s\p{P}\p{S}]+$', unicode: true);
