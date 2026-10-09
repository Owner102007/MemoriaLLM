/// «Место записи (айтрекер)» — один раз на ПК, за 3–5 минут
/// (SNO-F-EYE-05, кадр SNO-SCR-07.0).
///
/// Пять шагов: камера над экраном, монитор, размер экрана по банковской
/// карте (или по диагонали), расстояние рулеткой и самопроверка с живой
/// картинкой камеры. Пока экран открыт, окно стоит на весь выбранный
/// монитор: и рамка карты, и строка самопроверки «окно» меряются там,
/// где пойдёт запись. Уходя, экран закрывает спутник и возвращает окно.
///
/// Место пишется само (BUG-57): как только самопроверка закончилась — с
/// камерой, монитором, размером экрана и расстоянием, какие стоят на
/// экране, — и потом при каждой смене размера и расстояния, пока
/// проверка есть. Смена камеры или монитора проверку снимает, и место
/// остаётся прежним до новой проверки: в место не попадает камера,
/// которую не проверяли. Кнопка внизу — «Готово»: она только закрывает
/// экран.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../recording/layout_frames.dart';
import '../recording/layout_probe.dart';
import 'eye_link.dart';
import 'eye_place.dart';
import 'eye_process.dart';
import 'eye_protocol.dart';
import 'eye_tracker.dart';
import 'eye_window.dart';

/// Длина замера самопроверки на этом экране, секунд (без прогрева).
const double kPlaceCheckSeconds = 5;

/// Открывает «Место записи» поверх приложения. Идущая «Проверка
/// айтрекера» закрывается: спутник у машины один.
Future<void> openEyePlace(NavigatorState navigator, EyeTracker eye) {
  unawaited(eye.closeTrial());
  return navigator.push(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => EyePlaceScreen(eye: eye),
    ),
  );
}

/// Строка самопроверки «окно» (SNO-ALG-EYE-04): окно стоит на весь
/// выбранный монитор. Её меряет приложение, а не спутник.
EyeCheckRow windowCheckRow({
  required EyeWindowLock? lock,
  required EyeMonitor? monitor,
}) {
  if (lock == null || monitor == null) {
    return const EyeCheckRow(
      id: 'window',
      verdict: EyeVerdict.fail,
      text: 'Окно не встало на весь монитор',
    );
  }
  if (!lock.found || lock.monitor != monitor.id) {
    return const EyeCheckRow(
      id: 'window',
      verdict: EyeVerdict.fail,
      text: 'Окно не на выбранном мониторе',
    );
  }
  if (lock.widthPx != monitor.widthPx || lock.heightPx != monitor.heightPx) {
    return EyeCheckRow(
      id: 'window',
      verdict: EyeVerdict.fail,
      text:
          'Окно не на весь экран: ${lock.widthPx}×${lock.heightPx} из '
          '${monitor.widthPx}×${monitor.heightPx}',
      value: <int>[lock.widthPx, lock.heightPx],
    );
  }
  return EyeCheckRow(
    id: 'window',
    verdict: EyeVerdict.good,
    text: 'Окно на весь экран: ${lock.widthPx}×${lock.heightPx}',
    value: <int>[lock.widthPx, lock.heightPx],
  );
}

/// Первая оценка пикселей на миллиметр для монитора [monitor]: место,
/// уже заданное на нём, — по нему; сведения системы — по ним; иначе —
/// обычные 96 точек на дюйм с масштабом Windows [dpr].
double initialPxPerMm(EyeMonitor monitor, EyePlace? place, double dpr) {
  if (place != null && place.monitor == monitor.id) {
    return place.pxPerMm;
  }
  final int? mm = monitor.widthMm;
  if (mm != null && mm > 0) {
    return monitor.widthPx / mm;
  }
  return dpr * 96 / 25.4;
}

/// Экран «Место записи».
class EyePlaceScreen extends StatefulWidget {
  /// Создаёт экран. [openSettings] открывает параметры камеры Windows;
  /// подменяется в тестах.
  const EyePlaceScreen({
    required this.eye,
    this.openSettings = openCameraSettings,
    super.key,
  });

  /// Айтрекер.
  final EyeTracker eye;

  /// Открывает параметры камеры Windows.
  final Future<bool> Function() openSettings;

  @override
  State<EyePlaceScreen> createState() => _EyePlaceScreenState();
}

class _EyePlaceScreenState extends State<EyePlaceScreen> {
  EyeLink? _link;
  String? _linkError;
  bool _connecting = true;

  List<EyeCamera> _cameras = const <EyeCamera>[];
  EyeCamera? _camera;

  List<EyeMonitor> _monitors = const <EyeMonitor>[];
  EyeMonitor? _monitor;
  EyeWindowLock? _lock;

  double _pxPerMm = 96 / 25.4;
  ScreenSizeSource _source = ScreenSizeSource.system;

  final TextEditingController _diagonal = TextEditingController();
  final TextEditingController _distance = TextEditingController(
    text: '${kDefaultDistanceMm ~/ 10}',
  );
  final FocusNode _cardFocus = FocusNode(debugLabel: 'eye-card');
  String? _diagonalError;

  EyeCheck? _check;
  bool _checking = false;
  String? _stage;
  EyePreview? _preview;
  String? _saveError;

  /// Место с этой проверкой сохранено (BUG-57).
  bool _saved = false;

  /// Когда закончилась проверка: у места — время проверки, а не правки
  /// расстояния после неё.
  DateTime? _checkedAt;

  /// Проверку провёл спутник. Спутник не ответил (не запустился, вышел,
  /// не уложился во время) — это не проверка места, и место прежнее.
  bool _measured = false;

  /// Номер сохранения: запоздавший ответ прежнего не в счёт.
  int _saving = 0;
  bool _closed = false;

  EyeTracker get _eye => widget.eye;

  @override
  void initState() {
    super.initState();
    unawaited(_begin());
  }

  Future<void> _begin() async {
    final EyePlace? place = _eye.place ?? await _eye.loadPlace();
    if (place != null) {
      _distance.text = '${(place.distanceMm / 10).round()}';
    }
    final List<EyeMonitor> monitors = await _eye.window.monitors();
    if (_closed) {
      return;
    }
    EyeMonitor? monitor;
    for (final EyeMonitor m in monitors) {
      if (place != null && m.id == place.monitor) {
        monitor = m;
      }
    }
    monitor ??= _firstWhere(monitors, (EyeMonitor m) => m.current);
    monitor ??= monitors.isEmpty ? null : monitors.first;
    setState(() {
      _monitors = monitors;
    });
    if (monitor != null) {
      await _chooseMonitor(monitor, place: place);
    }
    if (_closed) {
      return;
    }
    await _connect(place);
  }

  static T? _firstWhere<T>(List<T> items, bool Function(T item) test) {
    for (final T item in items) {
      if (test(item)) {
        return item;
      }
    }
    return null;
  }

  Future<void> _connect(EyePlace? place) async {
    if (_closed) {
      return;
    }
    setState(() {
      _connecting = true;
      _linkError = null;
    });
    try {
      final EyeLink link = await _eye.connect();
      if (_closed) {
        await link.close();
        return;
      }
      _link = link;
      link.onProgress = _onProgress;
      final List<EyeCamera> cameras = await link.cameras();
      if (_closed) {
        return;
      }
      EyeCamera? camera;
      if (place != null) {
        camera =
            _firstWhere(
              cameras,
              (EyeCamera c) => c.path != null && c.path == place.camera.path,
            ) ??
            _firstWhere(cameras, (EyeCamera c) => c.name == place.camera.name);
      }
      camera ??= cameras.isEmpty ? null : cameras.first;
      setState(() {
        _cameras = cameras;
        _camera = camera;
        _connecting = false;
      });
    } on EyeError catch (e) {
      if (!_closed) {
        setState(() {
          _connecting = false;
          _linkError = describeEyeError(e);
        });
      }
    }
  }

  Future<void> _chooseMonitor(EyeMonitor monitor, {EyePlace? place}) async {
    if (_closed) {
      return;
    }
    setState(() {
      _monitor = monitor;
      _check = null;
      _saved = false;
    });
    final EyeWindowLock? lock = await _eye.window.lock(monitor.id);
    if (_closed) {
      // Экран закрыли, пока окно вставало на монитор: замок снимается
      // здесь — уходя, экран снимал ещё не поставленный.
      unawaited(_eye.window.unlock());
      return;
    }
    final double dpr = lock?.dpr ?? 1;
    setState(() {
      _lock = lock;
      _pxPerMm = initialPxPerMm(monitor, place ?? _eye.place, dpr);
      final EyePlace? known = place ?? _eye.place;
      _source = known != null && known.monitor == monitor.id
          ? known.sizeSource
          : ScreenSizeSource.system;
    });
  }

  void _onProgress(Map<String, Object?> message) {
    if (_closed) {
      return;
    }
    final EyePreview? preview = EyePreview.fromMessage(message);
    if (preview != null) {
      setState(() => _preview = preview);
      return;
    }
    final Object? stage = message['stage'];
    setState(() {
      _stage = switch (stage) {
        'warmup' => 'Камера прогревается…',
        'measure' => 'Замер…',
        'switch' => '1080p не держит частоту — пробую 720p…',
        'keep' => '720p кадров не прибавил — остаётся 1080p',
        _ => _stage,
      };
    });
  }

  Future<void> _runCheck() async {
    final EyeLink? link = _link;
    if (link == null || _checking) {
      return;
    }
    setState(() {
      _checking = true;
      _stage = 'Камера открывается…';
      _check = null;
      _saved = false;
      _preview = null;
    });
    EyeCheck check;
    bool measured = true;
    try {
      final String? dir = await _eye.eyeFolder();
      check = await link.selfcheck(
        camera: _camera,
        seconds: kPlaceCheckSeconds,
        dir: dir,
        preview: true,
      );
    } on EyeError catch (e) {
      check = EyeCheck.unavailable(describeEyeError(e));
      measured = false;
    }
    check = check.withRow(windowCheckRow(lock: _lock, monitor: _monitor));
    if (_closed) {
      return;
    }
    setState(() {
      _check = check;
      _checking = false;
      _stage = null;
      _measured = measured;
      _checkedAt = DateTime.now();
    });
    // BUG-57: проверка закончилась — место пишется сразу, без кнопки.
    unawaited(_persist());
  }

  /// После правки размера или расстояния: место с прежней проверкой и
  /// новыми числами пишется заново.
  void _changed() {
    if (_check != null) {
      unawaited(_persist());
    }
  }

  void _nudge(int steps) {
    setState(() {
      _pxPerMm = nudgePxPerMm(_pxPerMm, steps).clamp(kMinPxPerMm, kMaxPxPerMm);
      _source = ScreenSizeSource.card;
    });
    _changed();
  }

  KeyEventResult _onCardKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _nudge(1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _nudge(-1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _nudge(10);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _nudge(-10);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _applyDiagonal() {
    final EyeMonitor? monitor = _monitor;
    final double? inches = double.tryParse(
      _diagonal.text.trim().replaceAll(',', '.'),
    );
    if (monitor == null || inches == null || inches < 7 || inches > 100) {
      setState(() => _diagonalError = 'Диагональ — от 7 до 100 дюймов');
      return;
    }
    setState(() {
      _diagonalError = null;
      _pxPerMm = pxPerMmFromDiagonal(
        inches: inches,
        widthPx: monitor.widthPx,
        heightPx: monitor.heightPx,
      );
      _source = ScreenSizeSource.diagonal;
    });
    _changed();
  }

  int? get _distanceMm {
    final int? cm = int.tryParse(_distance.text.trim());
    if (cm == null) {
      return null;
    }
    final int mm = cm * 10;
    return mm < kMinDistanceMm || mm > kMaxDistanceMm ? null : mm;
  }

  /// Пишет место с текущей проверкой (BUG-57). Проверки нет — писать
  /// нечего: место остаётся прежним.
  Future<void> _persist() async {
    final EyeCamera? camera = _camera;
    final EyeMonitor? monitor = _monitor;
    final EyeCheck? check = _check;
    if (camera == null || monitor == null || check == null || !_measured) {
      return;
    }
    final int? distance = _distanceMm;
    if (distance == null) {
      setState(() {
        _saved = false;
        _saveError =
            'Расстояние — от ${kMinDistanceMm ~/ 10} до '
            '${kMaxDistanceMm ~/ 10} см: место не сохранено';
      });
      return;
    }
    final EyePlace place = EyePlace(
      camera: camera,
      monitor: monitor.id,
      monitorName: monitor.name,
      widthPx: monitor.widthPx,
      heightPx: monitor.heightPx,
      pxPerMm: _pxPerMm,
      sizeSource: _source,
      distanceMm: distance,
      verdict: check.verdict,
      checkedAt: _checkedAt ?? DateTime.now(),
      mode: check.mode,
      fps: check.fps,
      checks: check.rows,
    );
    final int run = ++_saving;
    try {
      await _eye.savePlace(place);
    } on Object {
      if (mounted && run == _saving) {
        setState(() {
          _saved = false;
          _saveError = 'Место записи не сохранилось';
        });
      }
      return;
    }
    if (mounted && run == _saving) {
      setState(() {
        _saved = true;
        _saveError = null;
      });
    }
  }

  @override
  void dispose() {
    _closed = true;
    final EyeLink? link = _link;
    _link = null;
    if (link != null) {
      unawaited(link.close());
    }
    unawaited(_eye.window.unlock());
    _diagonal.dispose();
    _distance.dispose();
    _cardFocus.dispose();
    super.dispose();
  }

  Widget _section(ThemeData theme, String number, String title, Widget body) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 28,
            child: Text(number, style: theme.textTheme.titleMedium),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                body,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraPicker() {
    if (_connecting) {
      return const Text('Запускаю айтрекер…', key: Key('eye-place-connecting'));
    }
    final String? error = _linkError;
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            error,
            key: const Key('eye-place-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(
            key: const Key('eye-place-retry'),
            onPressed: () => unawaited(_connect(_eye.place)),
            child: const Text('Запустить ещё раз'),
          ),
        ],
      );
    }
    if (_cameras.isEmpty) {
      return const Text('Камер не найдено', key: Key('eye-place-no-camera'));
    }
    return DropdownButton<EyeCamera>(
      key: const Key('eye-place-camera'),
      value: _camera,
      isExpanded: true,
      items: <DropdownMenuItem<EyeCamera>>[
        for (final EyeCamera camera in _cameras)
          DropdownMenuItem<EyeCamera>(value: camera, child: Text(camera.name)),
      ],
      onChanged: _checking
          ? null
          : (EyeCamera? camera) => setState(() {
              _camera = camera;
              _check = null;
              _saved = false;
            }),
    );
  }

  Widget _monitorPicker() {
    if (_monitors.isEmpty) {
      return const Text(
        'Мониторы не определились',
        key: Key('eye-place-no-monitor'),
      );
    }
    return DropdownButton<String>(
      key: const Key('eye-place-monitor'),
      value: _monitor?.id,
      isExpanded: true,
      items: <DropdownMenuItem<String>>[
        for (final EyeMonitor monitor in _monitors)
          DropdownMenuItem<String>(
            value: monitor.id,
            child: Text(monitor.label),
          ),
      ],
      onChanged: _checking
          ? null
          : (String? id) {
              final EyeMonitor? monitor = _firstWhere(
                _monitors,
                (EyeMonitor m) => m.id == id,
              );
              if (monitor != null) {
                unawaited(_chooseMonitor(monitor));
              }
            },
    );
  }

  Widget _card(ThemeData theme) {
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final double width = kCardWidthMm * _pxPerMm / dpr;
    final double height = kCardHeightMm * _pxPerMm / dpr;
    final EyeMonitor? monitor = _monitor;
    final String size = monitor == null
        ? ''
        : '${(monitor.widthPx / _pxPerMm).round()} × '
              '${(monitor.heightPx / _pxPerMm).round()} мм';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Приложите банковскую карту к экрану и подгоните рамку стрелками '
          '(←→ — 0,1 мм, ↑↓ — 1 мм) или мышью за правый край.',
        ),
        const SizedBox(height: 8),
        Focus(
          focusNode: _cardFocus,
          autofocus: false,
          onKeyEvent: _onCardKey,
          child: GestureDetector(
            onTap: _cardFocus.requestFocus,
            onHorizontalDragUpdate: (DragUpdateDetails details) {
              final double next = (width + details.delta.dx) * dpr;
              setState(() {
                _pxPerMm = pxPerMmFromCard(next)
                    .clamp(kMinPxPerMm, kMaxPxPerMm);
                _source = ScreenSizeSource.card;
              });
              _changed();
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: AnimatedBuilder(
                animation: _cardFocus,
                builder: (BuildContext context, Widget? child) {
                  return Container(
                    key: const Key('eye-place-card'),
                    width: width,
                    height: height,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _cardFocus.hasFocus
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(
                        3.18 * _pxPerMm / dpr,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            IconButton(
              key: const Key('eye-place-card-minus'),
              tooltip: 'Уже на 0,1 мм',
              onPressed: () => _nudge(-1),
              icon: const Icon(Icons.remove),
            ),
            IconButton(
              key: const Key('eye-place-card-plus'),
              tooltip: 'Шире на 0,1 мм',
              onPressed: () => _nudge(1),
              icon: const Icon(Icons.add),
            ),
            FilledButton.tonal(
              key: const Key('eye-place-card-ok'),
              onPressed: () {
                setState(() => _source = ScreenSizeSource.card);
                _changed();
              },
              child: const Text('Совпадает'),
            ),
            Text(
              '${_pxPerMm.toStringAsFixed(2)} пикселей на мм · экран $size '
              '(${_source.words})',
              key: const Key('eye-place-scale'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            SizedBox(
              width: 160,
              child: TextField(
                key: const Key('eye-place-diagonal'),
                controller: _diagonal,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Диагональ, дюймов',
                  errorText: _diagonalError,
                ),
                onSubmitted: (String value) => _applyDiagonal(),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const Key('eye-place-diagonal-apply'),
              onPressed: _applyDiagonal,
              child: const Text('Ввести диагональ'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _distanceField() {
    return SizedBox(
      width: 220,
      child: TextField(
        key: const Key('eye-place-distance'),
        controller: _distance,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: const InputDecoration(
          labelText: 'От глаз до экрана, см',
          helperText: 'рулеткой, в обычной позе; место стула отметьте',
        ),
        onChanged: (String value) {
          setState(() {});
          _changed();
        },
      ),
    );
  }

  Widget _previewBox(ThemeData theme) {
    final EyePreview? preview = _preview;
    if (preview == null) {
      return const SizedBox.shrink();
    }
    final List<double>? face = preview.face;
    final Widget picture = SizedBox(
      width: 320,
      child: AspectRatio(
        aspectRatio: preview.width / preview.height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.memory(
              preview.jpeg,
              key: const Key('eye-place-preview'),
              gaplessPlayback: true,
              fit: BoxFit.fill,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stack) {
                    return const ColoredBox(color: Colors.black);
                  },
            ),
            if (face != null)
              CustomPaint(
                painter: _FacePainter(face, theme.colorScheme.primary),
              ),
          ],
        ),
      ),
    );
    // BUG-58: картинка нарочно редкая — пять кадров в секунду, чтобы не
    // отнимать частоту, которую меряет проверка; иначе кажется, что
    // камера медленная.
    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          picture,
          const SizedBox(height: 4),
          Text(
            'Картинка — 5 кадров в секунду; частоту камеры показывает '
            'строка «Частота».',
            key: const Key('eye-place-preview-note'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _checkView(ThemeData theme) {
    final EyeCheck? check = _check;
    final bool denied = check?.row('camera')?.value == 'camera_denied';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: <Widget>[
            _previewBox(theme),
            if (_checking)
              Text(_stage ?? 'Проверяю…', key: const Key('eye-place-stage')),
          ],
        ),
        if (check != null) ...<Widget>[
          const SizedBox(height: 8),
          for (final EyeCheckRow row in check.rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                key: Key('eye-place-row-${row.id}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    switch (row.verdict) {
                      EyeVerdict.good => Icons.check_circle_outline,
                      EyeVerdict.warn => Icons.error_outline,
                      EyeVerdict.fail => Icons.cancel_outlined,
                    },
                    size: 18,
                    color: row.verdict == EyeVerdict.fail
                        ? theme.colorScheme.error
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(row.text)),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                'Итог: ${check.verdict.words}',
                key: const Key('eye-place-verdict'),
                style: theme.textTheme.titleSmall,
              ),
              if (_saved)
                Row(
                  key: const Key('eye-place-saved'),
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.check,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    const Text('Сохранено'),
                  ],
                ),
            ],
          ),
          if (denied)
            TextButton.icon(
              key: const Key('eye-place-settings'),
              onPressed: () => unawaited(widget.openSettings()),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Открыть параметры камеры'),
            ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            OutlinedButton(
              key: const Key('eye-place-check'),
              onPressed: _link == null || _checking
                  ? null
                  : () => unawaited(_runCheck()),
              child: Text(check == null ? 'Проверить' : 'Проверить ещё раз'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // SNO-F-REC-03: экран места записи — зона кадра раскладки.
    return LayoutProbe(
      kind: LayoutKind.screen,
      id: 'eye_place',
      child: _view(context),
    );
  }

  Widget _view(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? saveError = _saveError;
    return Scaffold(
      appBar: AppBar(title: const Text('Место записи (айтрекер)')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          _section(theme, '1', 'Камера над экраном', _cameraPicker()),
          _section(
            theme,
            '2',
            'Монитор, на котором пойдёт запись',
            _monitorPicker(),
          ),
          _section(theme, '3', 'Размер экрана', _card(theme)),
          _section(theme, '4', 'Расстояние', _distanceField()),
          _section(theme, '5', 'Самопроверка', _checkView(theme)),
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FilledButton(
                  key: const Key('eye-place-done'),
                  onPressed: () => unawaited(Navigator.of(context).maybePop()),
                  child: const Text('Готово'),
                ),
                if (saveError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      saveError,
                      key: const Key('eye-place-save-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  _FacePainter(this.face, this.color);

  final List<double> face;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect box = Rect.fromLTRB(
      face[0] * size.width,
      face[1] * size.height,
      face[2] * size.width,
      face[3] * size.height,
    );
    canvas.drawRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size.width / 200)
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_FacePainter oldDelegate) {
    return oldDelegate.face != face || oldDelegate.color != color;
  }
}
