import 'dart:async';

import 'store.dart';

/// Журнал записи: строки копятся в памяти и уходят на диск пачкой
/// (SNO-ALG-REC-01).
///
/// Событие записывается в память сразу и ничего не ждёт: действие
/// участника не должно стоять за диском. На диск накопленное уходит
/// раз в секунду ([flush]) — при сбое теряется не больше секунды
/// событий. Писатель один: две записи в файл разом не идут, а строки
/// встают в том порядке, в каком случились.
class EventJournal {
  /// Создаёт журнал поверх открытого файла.
  EventJournal(this._file);

  final JournalFile _file;
  final StringBuffer _pending = StringBuffer();
  Future<void>? _writing;
  bool _closed = false;

  /// Сколько строк принято.
  int lines = 0;

  /// Была ли ошибка записи на диск: место кончилось, файл пропал.
  ///
  /// Запись при этом не останавливается — следующая попытка может
  /// удаться, — но о потере экспериментатор обязан узнать.
  bool failed = false;

  /// Принимает строку события.
  void add(String line) {
    if (_closed) {
      return;
    }
    _pending
      ..write(line)
      ..write('\n');
    lines++;
  }

  /// Сбрасывает накопленное на диск.
  ///
  /// Возвращается, когда на диске всё, что было принято до вызова.
  Future<void> flush() {
    final Future<void>? writing = _writing;
    if (writing != null) {
      // Писатель уже идёт; он заберёт и то, что пришло следом.
      return writing;
    }
    if (_pending.isEmpty) {
      return Future<void>.value();
    }
    final Future<void> run = _drain();
    _writing = run;
    return run;
  }

  Future<void> _drain() async {
    try {
      while (_pending.isNotEmpty) {
        final String chunk = _pending.toString();
        _pending.clear();
        try {
          await _file.append(chunk);
        } on Object {
          failed = true;
        }
      }
    } finally {
      _writing = null;
    }
  }

  /// Дописывает оставшееся и закрывает файл.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    await flush();
    _closed = true;
    try {
      await _file.close();
    } on Object {
      failed = true;
    }
  }
}
