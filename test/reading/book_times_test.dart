import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/reading/book_times.dart';

import '../support/recording_fakes.dart';

/// SNO-F-MAP-01: время в книгах — по нему у звезды на карте размер
/// (решение владельца Э3 от 05.10.2026).
///
/// Часы подменены: минуты чтения проходят без ожидания.
void main() {
  const String key = 'sno.book_times';
  late MemorySettings settings;
  late int now;

  BookTimes times() {
    return BookTimes(settings: settings, key: key, nowMs: () => now);
  }

  Map<String, Object?> stored() {
    final String? raw = settings.values[key];
    return raw == null
        ? <String, Object?>{}
        : jsonDecode(raw) as Map<String, Object?>;
  }

  setUp(() {
    settings = MemorySettings();
    now = 1000;
  });

  group('SNO-F-MAP-01: счёт времени', () {
    test('SNO-F-MAP-01: время идёт, пока книга открыта', () async {
      final BookTimes counter = times();
      counter.opened('a');
      now += 60000;
      expect(counter.times, <String, int>{'a': 60000});
      expect(counter.open, 'a');
      now += 30000;
      counter.closed('a');
      await counter.settled();

      expect(counter.times, <String, int>{'a': 90000});
      expect(counter.open, isNull);
      expect(stored(), <String, Object?>{'a': 90000});
      // После закрытия время стоит.
      now += 500000;
      expect(counter.times, <String, int>{'a': 90000});
    });

    test('SNO-F-MAP-01: время копится по книгам и по заходам', () async {
      final BookTimes counter = times();
      counter.opened('a');
      now += 10000;
      counter.closed('a');
      now += 99000;
      counter.opened('b');
      now += 20000;
      counter.closed('b');
      counter.opened('a');
      now += 5000;
      counter.closed('a');
      await counter.settled();

      expect(counter.times, <String, int>{'a': 15000, 'b': 20000});
      expect(stored(), <String, Object?>{'a': 15000, 'b': 20000});
    });

    test('SNO-F-MAP-01: свёрнутое приложение не считается', () async {
      final BookTimes counter = times();
      counter.opened('a');
      now += 40000;
      counter.hidden();
      await counter.settled();
      // Свернули — насчитанное уже в настройках: система вправе убить
      // приложение сразу после этого.
      expect(stored(), <String, Object?>{'a': 40000});

      now += 600000;
      expect(counter.times, <String, int>{'a': 40000});
      counter.shown();
      now += 5000;
      counter.closed('a');
      await counter.settled();

      expect(counter.times, <String, int>{'a': 45000});
      expect(stored(), <String, Object?>{'a': 45000});
    });

    test('SNO-F-MAP-01: повторные «не видно» и «видно» счёт не портят', () {
      final BookTimes counter = times();
      counter.opened('a');
      now += 1000;
      counter
        ..hidden()
        ..hidden();
      now += 7000;
      counter
        ..shown()
        ..shown();
      now += 2000;
      expect(counter.times, <String, int>{'a': 3000});
    });

    test('SNO-F-MAP-01: «не видно» не переживает экран чтения', () {
      final BookTimes counter = times();
      counter.opened('a');
      counter.hidden();
      // Экран чтения сняли, пока приложения не было видно: «видно» ему
      // уже никто не скажет.
      counter.closed('a');
      now += 50000;
      counter.opened('b');
      now += 4000;
      expect(counter.times, <String, int>{'b': 4000});
    });

    test('SNO-F-MAP-01: экран чтения, снятый до открытия книги, «не '
        'видно» за собой не оставляет', () {
      final BookTimes counter = times();
      // Книга ещё открывалась, когда приложение свернули, а экран
      // чтения сняли: книга так и не открылась.
      counter.hidden();
      counter.closed('a');
      now += 50000;
      counter.opened('b');
      now += 4000;
      expect(counter.times, <String, int>{'b': 4000});
    });

    test('SNO-F-MAP-01: книга открылась, пока приложения не было видно, '
        '— время идёт с возвращения', () async {
      final BookTimes counter = times();
      // Читатель нажал на толстую книгу и ушёл в другое приложение.
      counter.hidden();
      now += 3000;
      counter.opened('a');
      now += 600000;
      expect(counter.times, isEmpty, reason: 'приложения не видно');

      counter.shown();
      now += 5000;
      counter.closed('a');
      await counter.settled();

      expect(counter.times, <String, int>{'a': 5000});
      expect(stored(), <String, Object?>{'a': 5000});
    });

    test('SNO-F-MAP-01: чужое закрытие ничего не меняет', () async {
      final BookTimes counter = times();
      counter.opened('a');
      now += 3000;
      counter.closed('b');
      now += 3000;
      expect(counter.open, 'a');
      expect(counter.times, <String, int>{'a': 6000});
      await counter.settled();
      expect(settings.values.containsKey(key), isFalse);
    });

    test('SNO-F-MAP-01: открыли другую, не закрыв прежнюю, — прежней '
        'засчитано её время', () {
      final BookTimes counter = times();
      counter.opened('a');
      now += 8000;
      counter.opened('b');
      now += 2000;
      expect(counter.times, <String, int>{'a': 8000, 'b': 2000});
    });

    test('SNO-F-MAP-01: пока читают, насчитанное изредка ложится в '
        'настройки', () async {
      final BookTimes counter = times();
      counter.opened('a');
      now += kBookTimeSaveEveryMs - 1;
      counter.tick();
      await counter.settled();
      expect(settings.values.containsKey(key), isFalse, reason: 'ещё рано');

      now += 1;
      counter.tick();
      await counter.settled();
      expect(stored(), <String, Object?>{'a': kBookTimeSaveEveryMs});

      // Следующая запись — снова не раньше срока.
      now += 5000;
      counter.tick();
      await counter.settled();
      expect(stored(), <String, Object?>{'a': kBookTimeSaveEveryMs});
      expect(counter.times, <String, int>{'a': kBookTimeSaveEveryMs + 5000});
    });

    test('SNO-F-MAP-01: без открытой книги напоминание пусто', () async {
      final BookTimes counter = times();
      now += 999999;
      counter.tick();
      await counter.settled();
      expect(settings.values, isEmpty);
      expect(counter.times, isEmpty);
    });
  });

  group('SNO-F-MAP-01: запись и чтение', () {
    test('SNO-F-MAP-01: записанное время поднимается при запуске', () async {
      settings.values[key] = '{"a":120000,"b":30000}';
      final BookTimes counter = times();
      await counter.restore();

      expect(counter.times, <String, int>{'a': 120000, 'b': 30000});
      counter.opened('b');
      now += 10000;
      counter.closed('b');
      await counter.settled();
      expect(stored(), <String, Object?>{'a': 120000, 'b': 40000});
    });

    test('SNO-F-MAP-01: после сброса к эталону счёт пуст', () async {
      final BookTimes counter = times();
      counter.opened('a');
      now += 60000;
      counter.closed('a');
      await counter.settled();
      int told = 0;
      counter.addListener(() => told++);

      // Сброс стирает запись мимо счётчика.
      settings.values.remove(key);
      await counter.restore();

      expect(counter.times, isEmpty);
      expect(told, 1, reason: 'карта узнаёт, что размеры изменились');
    });

    test('SNO-F-MAP-01: настройки не пишутся — время цело и ляжет '
        'потом', () async {
      final BookTimes counter = times();
      settings.failWrites = true;
      counter.opened('a');
      now += 7000;
      counter.closed('a');
      await counter.settled();
      expect(settings.values, isEmpty);
      expect(counter.times, <String, int>{'a': 7000});

      settings.failWrites = false;
      counter.opened('a');
      now += 1000;
      counter.closed('a');
      await counter.settled();
      expect(stored(), <String, Object?>{'a': 8000});
    });

    test('SNO-F-MAP-01: настройки не читаются — счёт остаётся как '
        'был', () async {
      final BookTimes counter = times();
      counter.opened('a');
      now += 7000;
      counter.closed('a');
      await counter.settled();
      settings.failReads = true;

      await counter.restore();

      expect(counter.times, <String, int>{'a': 7000});
    });

    test('SNO-F-MAP-01: запись одного счёта — одна и та же строка', () {
      expect(
        encodeBookTimes(<String, int>{'b': 2, 'a': 1, 'c': 0, 'd': -4}),
        '{"a":1,"b":2}',
      );
      expect(encodeBookTimes(<String, int>{}), '{}');
    });

    test('SNO-F-MAP-01: негодная запись — пустой счёт, а не отказ', () {
      expect(decodeBookTimes(null), isEmpty);
      expect(decodeBookTimes(''), isEmpty);
      expect(decodeBookTimes('не JSON'), isEmpty);
      expect(decodeBookTimes('[1,2]'), isEmpty);
      expect(decodeBookTimes('"строка"'), isEmpty);
      // Негодная строка пропускается, годные остаются.
      expect(
        decodeBookTimes('{"a":5,"b":"много","c":-3,"d":2.6,"e":null}'),
        <String, int>{'a': 5, 'd': 3},
      );
    });
  });
}
