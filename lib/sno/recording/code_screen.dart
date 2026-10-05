import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/library/archive_scan.dart';
import '../participant_code.dart';
import 'session.dart';

/// О чём предупредить перед стартом записи; пусто — не о чем.
///
/// Предупреждение, а не запрет (SNO-F-REC-01): экспериментатор может
/// знать, что зарядка уже воткнута.
List<String> describeReadinessWarnings(Readiness readiness) {
  final int? battery = readiness.batteryPercent;
  final int? free = readiness.freeBytes;
  return <String>[
    if (readiness.lowBattery && battery != null)
      'Заряд $battery % — поставьте устройство на зарядку.',
    if (readiness.lowSpace && free != null)
      'Свободного места ${describeFileSize(free)} — записи может не '
          'хватить.',
  ];
}

/// Код участника перед стартом записи (SNO-SCR-01.2, SNO-F-CFG-05).
///
/// Код выдаёт приложение и показывает крупно: участник вписывает его в
/// бланк, и запись начинается только после «Код записан». Участнику,
/// который пришёл повторно или уже записывался на другом устройстве,
/// экспериментатор вводит прежний код — он принимается только при
/// верной контрольной цифре.
///
/// Экран закрывается с кодом, с которым начинать запись, или без него
/// — если старт отменили.
class ParticipantCodeScreen extends StatefulWidget {
  /// Создаёт экран.
  const ParticipantCodeScreen({
    required this.proposed,
    required this.readiness,
    required this.parse,
    required this.minutes,
    super.key,
  });

  /// Код, выданный приложением.
  final ParticipantCode proposed;

  /// Заряд и свободное место — для предупреждений.
  final Readiness readiness;

  /// Разбирает введённый код; `null` — код не сходится.
  final ParticipantCode? Function(String input) parse;

  /// Сколько минут продлится запись.
  final int minutes;

  @override
  State<ParticipantCodeScreen> createState() => _ParticipantCodeScreenState();
}

class _ParticipantCodeScreenState extends State<ParticipantCodeScreen> {
  final TextEditingController _field = TextEditingController();

  /// Вводят ли прежний код вместо выданного.
  bool _entering = false;

  /// Что не так с введённым кодом; `null` — пока ничего.
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _accept() {
    final ParticipantCode? entered = widget.parse(_field.text);
    if (entered == null) {
      setState(() => _error = 'Код не сходится — проверьте цифры');
      return;
    }
    Navigator.of(context).pop(entered);
  }

  List<Widget> _proposed(ThemeData theme) {
    return <Widget>[
      Text('Ваш код', style: theme.textTheme.titleMedium),
      const SizedBox(height: 12),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          widget.proposed.display,
          key: const Key('sno-code'),
          style: theme.textTheme.displayLarge?.copyWith(
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
      const SizedBox(height: 12),
      const Text('Впишите его в бланк'),
      const SizedBox(height: 28),
      FilledButton(
        key: const Key('sno-code-confirm'),
        onPressed: () => Navigator.of(context).pop(widget.proposed),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Код записан'),
        ),
      ),
      const SizedBox(height: 8),
      TextButton(
        key: const Key('sno-code-enter'),
        onPressed: () => setState(() => _entering = true),
        child: const Text('У участника уже есть код'),
      ),
    ];
  }

  List<Widget> _entry(ThemeData theme) {
    return <Widget>[
      Text('Код, уже выданный участнику', style: theme.textTheme.titleMedium),
      const SizedBox(height: 12),
      TextField(
        key: const Key('sno-code-field'),
        controller: _field,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        // Восемь цифр и дефис посередине, как код написан в бланке.
        maxLength: kCodeLength + 1,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp('[0-9-]')),
        ],
        style: theme.textTheme.headlineMedium,
        decoration: InputDecoration(
          hintText: '0000-0000',
          errorText: _error,
          counterText: '',
        ),
        onChanged: (String value) {
          if (_error != null) {
            setState(() => _error = null);
          }
        },
        onSubmitted: (String value) => _accept(),
      ),
      const SizedBox(height: 20),
      FilledButton(
        key: const Key('sno-code-accept'),
        onPressed: _accept,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Продолжить'),
        ),
      ),
      const SizedBox(height: 8),
      TextButton(
        key: const Key('sno-code-new'),
        onPressed: () => setState(() {
          _entering = false;
          _error = null;
        }),
        child: const Text('Вернуться к выданному коду'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> warnings = describeReadinessWarnings(widget.readiness);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('sno-code-cancel'),
          tooltip: 'Не начинать запись',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Код участника'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            children: <Widget>[
              ...(_entering ? _entry(theme) : _proposed(theme)),
              const SizedBox(height: 20),
              for (final String warning in warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    warning,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              Text(
                'Запись начнётся после подтверждения и продлится '
                '${widget.minutes} мин.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
