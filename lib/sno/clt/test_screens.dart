/// Экраны теста нагрузки (SNO-SCR-04; SNO-F-CLT-01, SNO-F-CLT-02,
/// SNO-F-CLT-03).
///
/// Три экрана: пароль экспериментатора (кадр SNO-SCR-04.1), пункт теста
/// — один на экран, со шкалой (SNO-SCR-04.2 и SNO-SCR-04.4), и «Спасибо,
/// ответы сохранены» (SNO-SCR-04.3). Что показано и что принято, решает
/// `load_test.dart`; здесь — только как это выглядит и чем нажимается.
///
/// Баллов на этих экранах нет нигде: показатели считаются при
/// завершении сессии и ложатся в архив записи, участнику они не
/// показываются.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../recording/summary.dart';
import 'load_test.dart';
import 'scenario.dart';

/// Шкала не длиннее этого показывается кнопками, длиннее — полосой.
const int kCltButtonDivisions = 10;

final List<LogicalKeyboardKey> _digitKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit0,
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

final List<LogicalKeyboardKey> _numpadKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.numpad0,
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
  LogicalKeyboardKey.numpad7,
  LogicalKeyboardKey.numpad8,
  LogicalKeyboardKey.numpad9,
];

/// Цифра клавиши [key] — верхнего ряда или цифрового блока; `null` —
/// клавиша не цифра.
int? cltDigitOf(LogicalKeyboardKey key) {
  final int top = _digitKeys.indexOf(key);
  if (top >= 0) {
    return top;
  }
  final int pad = _numpadKeys.indexOf(key);
  return pad >= 0 ? pad : null;
}

bool _isEnter(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter;
}

/// Показывает вопрос об усилии за блок [block] (кадр SNO-SCR-04.4).
///
/// Без пароля: блок закрывает экспериментатор. Ответ обязателен — с
/// экрана не уйти, пока он не дан; после ответа экран закрывается сам.
Future<void> openBlockEffort(
  NavigatorState navigator,
  LoadTest test,
  BlockMark block,
) async {
  final LoadTestRun? run = await test.begin(kCltBlockEnd, block: block);
  if (run == null) {
    return;
  }
  if (!navigator.mounted) {
    run.dispose();
    return;
  }
  await navigator.push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext context) {
        return LoadTestRunScreen(test: test, run: run);
      },
    ),
  );
}

/// Открывает итоговую часть теста: пароль, если замок закрыт, и пункты
/// по одному (кадры SNO-SCR-04.1 — SNO-SCR-04.3).
///
/// [dry] — пробный проход экспериментатора, когда записи нет: пароль
/// спрашивается всегда, ответы никуда не пишутся.
Future<void> openFinalTest(
  NavigatorState navigator,
  LoadTest test, {
  bool dry = false,
}) async {
  await test.load();
  if (test.scenario == null || !navigator.mounted) {
    return;
  }
  if (dry || !test.unlocked) {
    final bool? accepted = await navigator.push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) {
          return LoadTestPasswordScreen(test: test);
        },
      ),
    );
    if (accepted != true) {
      return;
    }
  }
  final LoadTestRun? run = await test.begin(kCltSessionEnd, dry: dry);
  if (run == null) {
    return;
  }
  if (!navigator.mounted) {
    run.dispose();
    return;
  }
  await navigator.push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext context) {
        return LoadTestRunScreen(test: test, run: run);
      },
    ),
  );
}

/// Пароль экспериментатора (SNO-F-CLT-01, кадр SNO-SCR-04.1).
///
/// Цифровая клавиатура, ввод скрыт. Три неверные попытки подряд —
/// минута ожидания с честным счётом секунд. Экран закрывается с `true`,
/// когда пароль принят.
class LoadTestPasswordScreen extends StatefulWidget {
  /// Создаёт экран.
  const LoadTestPasswordScreen({required this.test, super.key});

  /// Тест нагрузки.
  final LoadTest test;

  @override
  State<LoadTestPasswordScreen> createState() => _LoadTestPasswordState();
}

class _LoadTestPasswordState extends State<LoadTestPasswordScreen> {
  String _entered = '';
  bool _wrong = false;
  bool _checking = false;
  Timer? _countdown;

  bool get _locked => widget.test.lockedSeconds > 0;

  @override
  void initState() {
    super.initState();
    if (_locked) {
      _watchLock();
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  /// Раз в секунду перерисовывает счёт ожидания, пока ввод закрыт.
  void _watchLock() {
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_locked) {
        timer.cancel();
      }
      setState(() {});
    });
  }

  void _type(int digit) {
    if (_checking || _locked || _entered.length >= kCltPasswordLimit) {
      return;
    }
    setState(() {
      _entered = '$_entered$digit';
      _wrong = false;
    });
  }

  void _erase() {
    if (_checking || _entered.isEmpty) {
      return;
    }
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _submit() async {
    if (_checking || _locked || _entered.isEmpty) {
      return;
    }
    final String input = _entered;
    setState(() => _checking = true);
    final PasswordOutcome outcome = await widget.test.enter(input);
    if (!mounted) {
      return;
    }
    if (outcome == PasswordOutcome.accepted) {
      // Экран могли закрыть, пока пароль проверялся: тогда закрывать
      // уже нечего, а `pop` снял бы экран под ним.
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        Navigator.of(context).pop(true);
      }
      return;
    }
    setState(() {
      _checking = false;
      _entered = '';
      _wrong = outcome == PasswordOutcome.wrong;
    });
    if (outcome == PasswordOutcome.locked) {
      _watchLock();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    final int? digit = cltDigitOf(key);
    if (digit != null) {
      _type(digit);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      _erase();
      return KeyEventResult.handled;
    }
    if (_isEnter(key)) {
      unawaited(_submit());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Места под знаки пароля: набранное — точками, остальное — чертой.
  String _slots() {
    final int wanted = widget.test.passwordLength;
    final int places = _entered.length > wanted ? _entered.length : wanted;
    return <String>[
      for (int i = 0; i < places; i++) i < _entered.length ? '•' : '_',
    ].join(' ');
  }

  Widget _key(Widget child, {required String name, VoidCallback? onPressed}) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        width: 76,
        height: 56,
        child: OutlinedButton(
          key: Key('sno-clt-key-$name'),
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
          child: child,
        ),
      ),
    );
  }

  Widget _digit(ThemeData theme, int digit) {
    return _key(
      Text('$digit', style: theme.textTheme.titleLarge),
      name: '$digit',
      onPressed: _checking || _locked ? null : () => _type(digit),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int seconds = widget.test.lockedSeconds;
    final bool busy = _checking || seconds > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Cognitive load test')),
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Пароль экспериментатора',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _slots(),
                    key: const Key('sno-clt-password-slots'),
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 44,
                    child: Center(
                      child: seconds > 0
                          ? Text(
                              'Три неверные попытки. Ввод закрыт ещё на '
                              '$seconds с.',
                              key: const Key('sno-clt-password-locked'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.colorScheme.error),
                            )
                          : _wrong
                          ? Text(
                              'Неверный пароль',
                              key: const Key('sno-clt-password-wrong'),
                              style: TextStyle(color: theme.colorScheme.error),
                            )
                          : null,
                    ),
                  ),
                  for (int row = 0; row < 3; row++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (int column = 1; column <= 3; column++)
                          _digit(theme, row * 3 + column),
                      ],
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _key(
                        const Icon(Icons.backspace_outlined),
                        name: 'back',
                        onPressed: _checking || _entered.isEmpty
                            ? null
                            : _erase,
                      ),
                      _digit(theme, 0),
                      _key(
                        const Icon(Icons.check),
                        name: 'ok',
                        onPressed: busy || _entered.isEmpty
                            ? null
                            : () => unawaited(_submit()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Часть теста на экране: пункты по одному и «Спасибо» в конце
/// (SNO-F-CLT-02, SNO-F-CLT-03; кадры SNO-SCR-04.2 — SNO-SCR-04.4).
///
/// На экране пункта — только его текст, шкала с подписями краёв,
/// «Назад» и «Дальше». Вопрос об усилии после блока закрыть нельзя,
/// пока ответ не дан, и после ответа экран уходит сам; с итоговой
/// части уйти можно — она продолжится с того же пункта. На ПК шкала
/// выбирается мышью, цифрами и стрелками, «Дальше» — клавишей ввода.
class LoadTestRunScreen extends StatefulWidget {
  /// Создаёт экран. Прохождение [run] экран забирает себе и снимает,
  /// когда закрывается.
  const LoadTestRunScreen({required this.test, required this.run, super.key});

  /// Тест нагрузки.
  final LoadTest test;

  /// Прохождение части.
  final LoadTestRun run;

  @override
  State<LoadTestRunScreen> createState() => _LoadTestRunState();
}

class _LoadTestRunState extends State<LoadTestRunScreen> {
  /// Экран, с которого пришли: запись знает, где участник.
  late final String _cameFrom;

  /// Уходит ли экран сам: второй раз его не закрывают.
  bool _leaving = false;

  bool get _effort => widget.run.part.when == kCltBlockEnd && !widget.run.dry;

  @override
  void initState() {
    super.initState();
    _cameFrom = widget.test.session.context.screen;
    widget.test.session.screen('clt');
    widget.run.addListener(_changed);
    widget.test.addListener(_changed);
  }

  @override
  void dispose() {
    widget.run.removeListener(_changed);
    widget.test.removeListener(_changed);
    widget.test.session.screen(_cameFrom);
    widget.run.dispose();
    super.dispose();
  }

  /// Отвечать ли здесь уже не на что: сессию завершили, или усилие за
  /// этот блок оценили на другом экране — на экране завершения,
  /// который открылся поверх, когда запись остановилась.
  bool get _stale {
    final LoadTestRun run = widget.run;
    if (run.finished) {
      return false;
    }
    final BlockMark? block = run.block;
    return run.orphaned ||
        (_effort && block != null && widget.test.effortGiven(block));
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    setState(() {});
    if (_leaving) {
      return;
    }
    // Вопрос об усилии — один: ответ дан, и участник снова там, откуда
    // пришёл. Экран, которому отвечать уже не на что, уходит тоже:
    // держать участника на вопросе без выхода нельзя.
    if ((_effort && widget.run.finished) || _stale) {
      _leaving = true;
      // Именно этот экран, а не верхний: поверх него может стоять
      // экран завершения сессии.
      final ModalRoute<Object?>? route = ModalRoute.of(context);
      if (route == null) {
        return;
      }
      if (route.isCurrent) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).removeRoute(route);
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final LoadTestRun run = widget.run;
    final LogicalKeyboardKey key = event.logicalKey;
    if (run.finished) {
      if (_isEnter(key) && !_effort) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final int? digit = cltDigitOf(key);
    final CltScale scale = run.item.scale;
    if (digit != null &&
        scale.divisions <= kCltButtonDivisions &&
        scale.holds(digit)) {
      run.choose(digit);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      run.nudge(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      run.nudge(1);
      return KeyEventResult.handled;
    }
    if (_isEnter(key) && run.canNext) {
      unawaited(run.next());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  List<Widget> _item(ThemeData theme) {
    final LoadTestRun run = widget.run;
    final BlockMark? block = run.block;
    return <Widget>[
      if (run.dry)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Пробный проход: ответы не сохраняются',
            key: const Key('sno-clt-dry'),
            style: theme.textTheme.bodySmall,
          ),
        ),
      Text(
        block != null
            ? 'Блок ${block.number} закончен'
            : '${run.index + 1} из ${run.length}',
        key: const Key('sno-clt-progress'),
        style: theme.textTheme.titleSmall,
      ),
      const SizedBox(height: 12),
      Text(
        run.item.text,
        key: const Key('sno-clt-text'),
        style: theme.textTheme.titleLarge,
      ),
      const SizedBox(height: 28),
      CltScaleInput(
        scale: run.item.scale,
        value: run.selected,
        onChanged: run.saving ? null : run.choose,
        onNudge: run.saving ? null : run.nudge,
      ),
      const SizedBox(height: 28),
      if (run.saveFailed)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Ответ не записался на диск: проверьте свободное место.',
            key: const Key('sno-clt-save-failed'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      Row(
        children: <Widget>[
          if (run.length > 1)
            TextButton(
              key: const Key('sno-clt-back'),
              onPressed: run.canBack ? run.back : null,
              child: const Text('Назад'),
            ),
          const Spacer(),
          FilledButton(
            key: const Key('sno-clt-next'),
            onPressed: run.canNext ? () => unawaited(run.next()) : null,
            child: const Text('Дальше'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _done(ThemeData theme) {
    final LoadTestRun run = widget.run;
    return <Widget>[
      const SizedBox(height: 32),
      Icon(
        Icons.check_circle_outline,
        size: 48,
        color: theme.colorScheme.primary,
      ),
      const SizedBox(height: 16),
      Text(
        run.dry
            ? 'Пробный проход окончен: ответы не сохранялись'
            : 'Спасибо, ответы сохранены',
        key: const Key('sno-clt-thanks'),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge,
      ),
      if (run.saveFailed)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Последний ответ не записался на диск: проверьте свободное '
            'место.',
            key: const Key('sno-clt-save-failed'),
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      const SizedBox(height: 28),
      Center(
        child: FilledButton(
          key: const Key('sno-clt-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Готово'),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final LoadTestRun run = widget.run;
    // С вопроса об усилии не уйти, пока ответ не дан.
    final bool free = !_effort || run.finished;
    return PopScope<Object?>(
      canPop: free,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: free,
          title: Text(_effort ? 'Оценка усилия' : 'Cognitive load test'),
        ),
        body: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  children: run.finished ? _done(theme) : _item(theme),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Шкала пункта (SNO-F-CLT-02): деления и подписи краёв.
///
/// Короткая шкала — 1…7, 1…9 — кнопками в ряд. Длинная — 0…100 с шагом
/// 5, двадцать одно деление — полосой: по ней нажимают или ведут
/// пальцем, выбранное число стоит крупно над ней, а кнопки по краям
/// сдвигают его на одно деление — деление на телефоне уже пальца.
class CltScaleInput extends StatelessWidget {
  /// Создаёт шкалу. [onChanged] и [onNudge] — `null`, пока выбирать
  /// нельзя.
  const CltScaleInput({
    required this.scale,
    required this.value,
    required this.onChanged,
    this.onNudge,
    super.key,
  });

  /// Шкала.
  final CltScale scale;

  /// Выбранное значение; `null` — не выбрано.
  final int? value;

  /// Выбрано деление.
  final ValueChanged<int>? onChanged;

  /// Выбранное просят сдвинуть на столько делений.
  final ValueChanged<int>? onNudge;

  Widget _buttons(ThemeData theme) {
    final ColorScheme scheme = theme.colorScheme;
    final ValueChanged<int>? changed = onChanged;
    return Row(
      children: <Widget>[
        for (final int division in scale.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Material(
                key: Key('sno-clt-value-$division'),
                color: division == value ? scheme.primary : scheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  side: BorderSide(
                    color: division == value ? scheme.primary : scheme.outline,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: changed == null ? null : () => changed(division),
                  child: SizedBox(
                    height: 52,
                    child: Center(
                      child: Text(
                        '$division',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: division == value
                              ? scheme.onPrimary
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _strip(ThemeData theme) {
    final ColorScheme scheme = theme.colorScheme;
    final ValueChanged<int>? changed = onChanged;
    final ValueChanged<int>? nudge = onNudge;
    final List<int> values = scale.values;
    final int? chosen = value;
    return Column(
      children: <Widget>[
        Text(
          chosen == null ? '—' : '$chosen',
          key: const Key('sno-clt-strip-value'),
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            IconButton(
              key: const Key('sno-clt-less'),
              icon: const Icon(Icons.remove),
              tooltip: 'Меньше',
              onPressed: nudge == null ? null : () => nudge(-1),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double width = constraints.maxWidth;
                  void pick(double dx) {
                    if (changed == null || width <= 0) {
                      return;
                    }
                    final int raw = (dx / width * values.length).floor();
                    final int last = values.length - 1;
                    changed(values[raw < 0 ? 0 : (raw > last ? last : raw)]);
                  }

                  return GestureDetector(
                    key: const Key('sno-clt-strip'),
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (TapDownDetails details) {
                      pick(details.localPosition.dx);
                    },
                    onHorizontalDragStart: (DragStartDetails details) {
                      pick(details.localPosition.dx);
                    },
                    onHorizontalDragUpdate: (DragUpdateDetails details) {
                      pick(details.localPosition.dx);
                    },
                    child: SizedBox(
                      height: 56,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          for (int i = 0; i < values.length; i++)
                            Expanded(
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                height: values[i] == chosen
                                    ? 56
                                    : (i.isEven ? 34 : 24),
                                decoration: BoxDecoration(
                                  color: values[i] == chosen
                                      ? scheme.primary
                                      : (chosen != null && values[i] < chosen
                                            ? scheme.primary.withValues(
                                                alpha: 0.45,
                                              )
                                            : scheme.outline),
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              key: const Key('sno-clt-more'),
              icon: const Icon(Icons.add),
              tooltip: 'Больше',
              onPressed: nudge == null ? null : () => nudge(1),
            ),
          ],
        ),
      ],
    );
  }

  Widget _labels(ThemeData theme) {
    final TextStyle? style = theme.textTheme.bodySmall;
    final String? low = scale.labels[scale.min];
    final String? high = scale.labels[scale.max];
    String? middle;
    for (final MapEntry<int, String> label in scale.labels.entries) {
      if (label.key != scale.min && label.key != scale.max) {
        middle = label.value;
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: Text(low ?? '', style: style)),
        if (middle != null)
          Expanded(
            child: Text(middle, textAlign: TextAlign.center, style: style),
          ),
        Expanded(
          child: Text(high ?? '', textAlign: TextAlign.end, style: style),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (scale.divisions <= kCltButtonDivisions)
          _buttons(theme)
        else
          _strip(theme),
        const SizedBox(height: 8),
        _labels(theme),
      ],
    );
  }
}
