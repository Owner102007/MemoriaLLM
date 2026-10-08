import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/eye/eye_protocol.dart';

/// SNO-ALG-EYE-03: что в строках обмена — со стороны приложения.
///
/// Строки ответов взяты такими, какими их пишет настоящий спутник
/// (`eye/sno_eye/protocol.py`); как на них отвечает настоящий спутник
/// на Windows, проверяет `eye_satellite_test.dart` в CI.
void main() {
  group('SNO-ALG-EYE-03: строки обмена', () {
    test('SNO-ALG-EYE-03: команда — одна строка JSON с версией обмена', () {
      final String line = encodeEyeCommand('selfcheck', <String, Object?>{
        'dir': r'C:\Users\Павел\Записи',
      });
      expect(line, isNot(contains('\n')));
      expect(jsonDecode(line), <String, Object?>{
        'cmd': 'selfcheck',
        'v': kEyeProtocol,
        'dir': r'C:\Users\Павел\Записи',
      });
    });

    test('SNO-ALG-EYE-03: не JSON и не объект — мусор', () {
      expect(decodeEyeLine('{"v":1,"hb":3}'), <String, Object?>{
        'v': 1,
        'hb': 3,
      });
      expect(decodeEyeLine('Traceback (most recent call last):'), isNull);
      expect(decodeEyeLine('[1, 2]'), isNull);
      expect(decodeEyeLine('   '), isNull);
    });

    test('SNO-ALG-EYE-03: ответ на close называется closed', () {
      expect(replyOf(<String, Object?>{'reply': 'closed'}), 'close');
      expect(replyOf(<String, Object?>{'reply': 'hello'}), 'hello');
      expect(replyOf(<String, Object?>{'hb': 1}), isNull);
    });

    test('SNO-ALG-EYE-03: ошибка спутника с именем команды', () {
      final EyeError error = EyeError.fromMessage(<String, Object?>{
        'v': 1,
        'error': 'camera_busy',
        'text': 'Камера занята',
        'cmd': 'selfcheck',
      });
      expect(error.code, 'camera_busy');
      expect(error.command, 'selfcheck');
      expect(describeEyeError(error), contains('Teams'));
      final EyeError bare = EyeError.fromMessage(<String, Object?>{
        'error': 42,
      });
      expect(bare.code, 'bad_command');
      expect(bare.command, isNull);
    });
  });

  group('SNO-F-EYE-04: hello', () {
    test('SNO-F-EYE-04: спутник своей версии — версии и модель', () {
      final EyeHello hello = EyeHello.fromMessage(<String, Object?>{
        'v': 1,
        'reply': 'hello',
        'version': '0.1.0',
        'mediapipe': '1.1.0',
        'model_sha256': '64184e22',
      });
      expect(hello.toJson(), <String, Object?>{
        'protocol': 1,
        'version': '0.1.0',
        'mediapipe': '1.1.0',
        'model_sha256': '64184e22',
      });
    });

    test('SNO-F-EYE-04: чужая версия обмена — отказ словами', () {
      expect(
        () => EyeHello.fromMessage(<String, Object?>{
          'v': 2,
          'reply': 'hello',
        }),
        throwsA(
          isA<EyeError>()
              .having((EyeError e) => e.code, 'code', 'version')
              .having(
                (EyeError e) => describeEyeError(e),
                'слова',
                'Айтрекер не запустился: спутник другой версии',
              ),
        ),
      );
    });

    test('SNO-F-EYE-04: почему айтрекера нет — словами', () {
      expect(
        describeEyeError(const EyeError('no_satellite', '')),
        'Айтрекер не запустился: рядом с приложением нет папки eye',
      );
      expect(
        describeEyeError(const EyeError('model_missing', 'нет файла')),
        'Айтрекер не запустился: модель лица не загрузилась (нет файла)',
      );
      expect(
        describeEyeError(const EyeError('camera_denied', '')),
        startsWith('Камера запрещена в параметрах Windows'),
      );
      expect(describeEyeError(const EyeError('странное', 'так')), 'так');
    });
  });

  group('SNO-F-EYE-05: камеры и самопроверка', () {
    test('SNO-F-EYE-05: камеры — с именами и путями; кривые пропущены', () {
      final List<EyeCamera> cameras = camerasOf(<String, Object?>{
        'reply': 'cameras',
        'cameras': <Object?>[
          <String, Object?>{
            'index': 0,
            'name': 'Integrated Camera',
            'path': r'\\?\usb#1',
          },
          <String, Object?>{'index': 1, 'name': ''},
          <String, Object?>{'name': 'без номера'},
          'мусор',
        ],
      });
      expect(cameras, const <EyeCamera>[
        EyeCamera(index: 0, name: 'Integrated Camera', path: r'\\?\usb#1'),
        EyeCamera(index: 1, name: 'Камера 2'),
      ]);
      expect(cameras.first.toJson(), <String, Object?>{
        'index': 0,
        'name': 'Integrated Camera',
        'path': r'\\?\usb#1',
      });
    });

    test('SNO-ALG-EYE-04: итог самопроверки — строки, режим и частота', () {
      final EyeCheck check = EyeCheck.fromMessage(<String, Object?>{
        'reply': 'selfcheck',
        'verdict': 'warn',
        'checks': <Object?>[
          <String, Object?>{
            'id': 'iris',
            'verdict': 'warn',
            'value': 16.0,
            'text': 'Мелко',
          },
        ],
        'measures': <String, Object?>{'width': 1280, 'height': 720, 'fps': 29.7},
      });
      expect(check.verdict, EyeVerdict.warn);
      expect(check.row('iris')!.text, 'Мелко');
      expect(check.mode, <int>[1280, 720]);
      expect(check.fps, 29.7);
    });

    test('SNO-ALG-EYE-04: строка «окно» — по тому же правилу итога', () {
      const EyeCheck good = EyeCheck(
        verdict: EyeVerdict.good,
        rows: <EyeCheckRow>[
          EyeCheckRow(id: 'camera', verdict: EyeVerdict.good, text: 'ok'),
        ],
      );
      // Окно не на мониторе — важная строка: итог «не годится».
      final EyeCheck bad = good.withRow(
        const EyeCheckRow(id: 'window', verdict: EyeVerdict.fail, text: 'нет'),
      );
      expect(bad.verdict, EyeVerdict.fail);
      expect(bad.rows.map((EyeCheckRow r) => r.id), <String>[
        'camera',
        'window',
      ]);
      // Строка заменяется, а не повторяется.
      final EyeCheck fixed = bad.withRow(
        const EyeCheckRow(id: 'window', verdict: EyeVerdict.good, text: 'да'),
      );
      expect(fixed.verdict, EyeVerdict.good);
      expect(fixed.rows, hasLength(2));
      // Блики — не важная строка: «не годится» в ней — оговорка.
      final EyeCheck glare = fixed.withRow(
        const EyeCheckRow(id: 'glare', verdict: EyeVerdict.fail, text: 'б'),
      );
      expect(glare.verdict, EyeVerdict.warn);
      expect(
        EyeCheck.unavailable('нет спутника').verdict,
        EyeVerdict.fail,
      );
      expect(EyeVerdict.named('нечто'), EyeVerdict.fail);
      expect(EyeVerdict.good.worse(EyeVerdict.warn), EyeVerdict.warn);
    });

    test('SNO-F-EYE-05: кадр камеры — JPEG и рамка лица в долях', () {
      final EyePreview? preview = EyePreview.fromMessage(<String, Object?>{
        'progress': 'preview',
        'jpeg': base64Encode(<int>[0xff, 0xd8, 0xff]),
        'w': 320,
        'h': 180,
        'face': <Object?>[0.3, 0.2, 0.6, 0.8],
      });
      expect(preview!.jpeg, <int>[0xff, 0xd8, 0xff]);
      expect(preview.face, <double>[0.3, 0.2, 0.6, 0.8]);
      expect(
        EyePreview.fromMessage(<String, Object?>{
          'progress': 'preview',
          'jpeg': 'не base64!',
          'w': 320,
          'h': 180,
        }),
        isNull,
      );
      expect(
        EyePreview.fromMessage(<String, Object?>{
          'progress': 'selfcheck',
          'stage': 'warmup',
        }),
        isNull,
      );
    });

    test('SNO-ALG-EYE-03: сердцебиение', () {
      final EyeHeartbeat beat = EyeHeartbeat.fromMessage(<String, Object?>{
        'hb': 7,
        'cpu': 12.5,
        'mem': 230,
      })!;
      expect(beat.n, 7);
      expect(beat.cpu, 12.5);
      expect(beat.memoryMb, 230);
      expect(EyeHeartbeat.fromMessage(<String, Object?>{'reply': 'x'}), isNull);
    });
  });
}
