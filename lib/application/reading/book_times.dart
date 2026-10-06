import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/settings/app_settings.dart';

/// Как часто, самое редкое, насчитанное время уходит в настройки, пока
/// книгу читают, в миллисекундах: приложение, убитое посреди чтения,
/// теряет не больше этого.
const int kBookTimeSaveEveryMs = 20000;

/// Сколько времени читатель провёл в каждой книге (SNO-F-MAP-01,
/// решение владельца Э3 от 05.10.2026; малая часть F-LIB-20).
///
/// Считается время, пока книга открыта на экране чтения, а приложение
/// видно: свёрнутое приложение и погашенный экран не считаются. Счёт —
/// по монотонным часам: перевод настенных часов его не меняет.
///
/// Лежит одной записью JSON в таблице настроек — «книга → миллисекунды».
/// Это след читателя, а не производное от файлов книг: сброс к эталону
/// стирает запись вместе с остальными настройками, и у следующего
/// участника счёт начинается с нуля (`sno/reference_state.dart`).
///
/// Отказ настроек счёт не роняет: время остаётся в памяти и ляжет при
/// следующей записи.
class BookTimes extends ChangeNotifier {
  /// Создаёт счётчик, который хранит себя в [settings] под ключом [key].
  ///
  /// [nowMs] — монотонные часы; в тестах подменяются.
  BookTimes({
    required AppSettingsRepository settings,
    required String key,
    int Function()? nowMs,
  }) : _settings = settings,
       _key = key,
       _nowMs = nowMs ?? _monotonicMs;

  static final Stopwatch _watch = Stopwatch()..start();

  static int _monotonicMs() => _watch.elapsedMilliseconds;

  final AppSettingsRepository _settings;
  final String _key;
  final int Function() _nowMs;

  final Map<String, int> _ms = <String, int>{};
  String? _open;

  /// Сколько времени было у открытой книги, когда её открыли.
  int _openBase = 0;
  int _since = 0;
  bool _visible = true;
  int _savedAt = 0;
  bool _dirty = false;
  Future<void> _saving = Future<void>.value();

  /// Какая книга сейчас открыта; `null` — никакая.
  String? get open => _open;

  /// Время по книгам, в миллисекундах, вместе с тем, что набежало в
  /// открытой книге к этому мигу.
  Map<String, int> get times {
    final Map<String, int> out = Map<String, int>.of(_ms);
    final String? open = _open;
    if (open != null && _visible) {
      final int running = _nowMs() - _since;
      if (running > 0) {
        out[open] = (out[open] ?? 0) + running;
      }
    }
    return out;
  }

  /// Сколько времени набежало в открытой книге за это открытие, в
  /// миллисекундах; ноль — книга не открыта.
  int get openedMs {
    final String? open = _open;
    if (open == null) {
      return 0;
    }
    final int passed = (times[open] ?? 0) - _openBase;
    return passed < 0 ? 0 : passed;
  }

  /// Что о закрытии книги [bookId] знает счёт — журналу записи
  /// (`book.close`): сколько её читали на виду за это открытие и
  /// всего. Пусто — книга [bookId] сейчас не открыта.
  Map<String, Object?> closingFacts(String bookId) {
    if (_open != bookId) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      'read_ms': openedMs,
      'read_total_ms': times[bookId] ?? 0,
    };
  }

  /// То же об открытой сейчас книге, какой бы она ни была; пусто —
  /// книга не открыта.
  ///
  /// Нужно записи сессии: книгу, открытую в миг остановки записи,
  /// закрывает она сама и идентификатора книги на полке не знает
  /// (SNO-F-REC-16).
  Map<String, Object?> openFacts() {
    final String? open = _open;
    return open == null ? const <String, Object?>{} : closingFacts(open);
  }

  /// Читает записанное время. Зовётся при запуске и после сброса к
  /// эталону: записи нет — счёт пуст.
  ///
  /// Время, набежавшее в открытой книге, не теряется: оно ещё не в
  /// записи и досчитывается поверх прочитанного.
  Future<void> restore() async {
    await _saving;
    Map<String, int> stored = <String, int>{};
    try {
      stored = decodeBookTimes(await _settings.read(_key));
    } on Object {
      // Настройки не ответили: счёт начинается с того, что в памяти.
      return;
    }
    _ms
      ..clear()
      ..addAll(stored);
    _dirty = false;
    notifyListeners();
  }

  /// Книга [bookId] открылась на экране чтения.
  ///
  /// Если приложение в этот миг не видно — книга открывалась долго, и
  /// читатель успел уйти, — время пойдёт, когда он вернётся ([shown]).
  void opened(String bookId) {
    _settle();
    _open = bookId;
    _openBase = _ms[bookId] ?? 0;
    _since = _nowMs();
    // Срок до первой записи считается от открытия книги.
    _savedAt = _since;
  }

  /// Книгу [bookId] закрыли. Чужое закрытие — пока открыта другая
  /// книга — ничего не меняет.
  ///
  /// Вместе с экраном чтения уходит и тот, кто говорил «видно» и «не
  /// видно»: отметка «не видно» его не переживает — иначе следующей
  /// книге время не считалось бы вовсе.
  void closed(String bookId) {
    final String? open = _open;
    if (open != null && open != bookId) {
      return;
    }
    _settle();
    _open = null;
    _visible = true;
    if (open == null) {
      return;
    }
    _save();
    notifyListeners();
  }

  /// Приложение перестало быть видно: время стоит.
  void hidden() {
    if (!_visible) {
      return;
    }
    _settle();
    _visible = false;
    _save();
  }

  /// Приложение снова видно: время идёт с этого мига.
  void shown() {
    if (_visible) {
      return;
    }
    _visible = true;
    _since = _nowMs();
  }

  /// Напоминание от экрана чтения — страницу перелистнули: если с
  /// прошлой записи прошло больше [kBookTimeSaveEveryMs], насчитанное
  /// уходит в настройки.
  void tick() {
    if (_open == null || !_visible) {
      return;
    }
    if (_nowMs() - _savedAt >= kBookTimeSaveEveryMs) {
      _settle();
      _save();
    }
  }

  /// Ждёт, пока насчитанное ляжет в настройки.
  Future<void> settled() => _saving;

  /// Переносит набежавшее в открытой книге в счёт.
  void _settle() {
    final String? open = _open;
    final int now = _nowMs();
    if (open != null && _visible) {
      final int running = now - _since;
      if (running > 0) {
        _ms[open] = (_ms[open] ?? 0) + running;
        _dirty = true;
      }
    }
    _since = now;
  }

  void _save() {
    _savedAt = _nowMs();
    if (!_dirty) {
      return;
    }
    _dirty = false;
    final String encoded = encodeBookTimes(_ms);
    _saving = _saving.then((_) async {
      try {
        await _settings.write(_key, encoded);
      } on Object {
        // Не записалось: время в памяти цело и ляжет в следующий раз.
        _dirty = true;
      }
    });
  }
}

/// Время по книгам — строкой для настроек: JSON «книга → миллисекунды»,
/// ключи по алфавиту — одна и та же запись у одного и того же счёта.
String encodeBookTimes(Map<String, int> times) {
  final List<String> ids = times.keys.toList()..sort();
  return jsonEncode(<String, int>{
    for (final String id in ids)
      if (times[id]! > 0) id: times[id]!,
  });
}

/// Разбирает запись времени по книгам. Нет записи, запись не
/// разбирается или в ней не то — пустой счёт; отдельная негодная
/// строка пропускается.
Map<String, int> decodeBookTimes(String? raw) {
  if (raw == null || raw.isEmpty) {
    return <String, int>{};
  }
  Object? parsed;
  try {
    parsed = jsonDecode(raw);
  } on FormatException {
    return <String, int>{};
  }
  if (parsed is! Map<String, Object?>) {
    return <String, int>{};
  }
  final Map<String, int> out = <String, int>{};
  for (final MapEntry<String, Object?> entry in parsed.entries) {
    final Object? value = entry.value;
    if (value is int && value > 0) {
      out[entry.key] = value;
    } else if (value is double && value.isFinite && value > 0) {
      out[entry.key] = value.round();
    }
  }
  return out;
}
