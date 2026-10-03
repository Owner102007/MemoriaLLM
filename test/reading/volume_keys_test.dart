import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/volume_keys.dart';
import 'package:memoria/infrastructure/platform/android_volume_keys.dart';

/// F-READ-26, ALG-READ-06: листание кнопками громкости.
///
/// Правило «листать или менять громкость» написано в Dart, а не в
/// Kotlin, ровно ради этого файла: тестов Android в проекте нет.
void main() {
  const VolumeKeyEvent downPress = VolumeKeyEvent(
    key: VolumeKey.down,
    pressed: true,
  );
  const VolumeKeyEvent downRelease = VolumeKeyEvent(
    key: VolumeKey.down,
    pressed: false,
  );
  const VolumeKeyEvent upPress = VolumeKeyEvent(
    key: VolumeKey.up,
    pressed: true,
  );
  const VolumeKeyEvent upRelease = VolumeKeyEvent(
    key: VolumeKey.up,
    pressed: false,
  );

  VolumeKeyEvent repeat(VolumeKey key, int count) =>
      VolumeKeyEvent(key: key, pressed: true, repeat: count);

  group('F-READ-26: контроллер клавиш', () {
    test('F-READ-26: короткое нажатие — шаг, и только по отпусканию', () {
      final VolumeKeyTurner turner = VolumeKeyTurner();
      // В момент нажатия ещё неизвестно, удержат кнопку или нет.
      expect(turner.handle(downPress, active: true), VolumeKeyOutcome.none);
      expect(
        turner.handle(downRelease, active: true),
        VolumeKeyOutcome.forward,
      );
      expect(turner.handle(upPress, active: true), VolumeKeyOutcome.none);
      expect(turner.handle(upRelease, active: true), VolumeKeyOutcome.back);
    });

    test('F-READ-26: удержание — громкость и ни одного шага', () {
      final VolumeKeyTurner turner = VolumeKeyTurner();
      final List<VolumeKeyOutcome> seen = <VolumeKeyOutcome>[
        turner.handle(downPress, active: true),
        for (int count = 1; count <= 5; count++)
          turner.handle(repeat(VolumeKey.down, count), active: true),
        turner.handle(downRelease, active: true),
      ];
      expect(seen.first, VolumeKeyOutcome.none);
      // Каждый автоповтор меняет громкость, как у системы.
      expect(seen.sublist(1, 6), everyElement(VolumeKeyOutcome.lower));
      expect(seen.last, VolumeKeyOutcome.none);
      expect(seen, isNot(contains(VolumeKeyOutcome.forward)));
      expect(seen, isNot(contains(VolumeKeyOutcome.back)));
    });

    test('F-READ-26: удержание «громче» делает громче', () {
      final VolumeKeyTurner turner = VolumeKeyTurner();
      turner.handle(upPress, active: true);
      expect(
        turner.handle(repeat(VolumeKey.up, 1), active: true),
        VolumeKeyOutcome.raise,
      );
      expect(turner.handle(upRelease, active: true), VolumeKeyOutcome.none);
    });

    test('F-READ-26: после удержания следующее нажатие снова листает', () {
      final VolumeKeyTurner turner = VolumeKeyTurner();
      turner.handle(downPress, active: true);
      turner.handle(repeat(VolumeKey.down, 1), active: true);
      turner.handle(downRelease, active: true);

      turner.handle(downPress, active: true);
      expect(
        turner.handle(downRelease, active: true),
        VolumeKeyOutcome.forward,
      );
    });

    test('F-READ-26: перевёрнутое направление', () {
      final VolumeKeyTurner turner = VolumeKeyTurner();
      turner.handle(downPress, active: true, downIsForward: false);
      expect(
        turner.handle(downRelease, active: true, downIsForward: false),
        VolumeKeyOutcome.back,
      );
      turner.handle(upPress, active: true, downIsForward: false);
      expect(
        turner.handle(upRelease, active: true, downIsForward: false),
        VolumeKeyOutcome.forward,
      );
    });

    test('F-READ-26: перехват не действует — кнопка меняет громкость', () {
      // Событие дошло, когда листать уже нельзя: открыли шторку, а
      // выключение перехвата ещё в пути. Кнопка не должна пропасть.
      final VolumeKeyTurner turner = VolumeKeyTurner();
      expect(turner.handle(downPress, active: false), VolumeKeyOutcome.lower);
      expect(
        turner.handle(repeat(VolumeKey.down, 1), active: false),
        VolumeKeyOutcome.lower,
      );
      expect(turner.handle(downRelease, active: false), VolumeKeyOutcome.none);
      expect(turner.handle(upPress, active: false), VolumeKeyOutcome.raise);
      expect(turner.handle(upRelease, active: false), VolumeKeyOutcome.none);
    });

    test('F-READ-26: отпускание без своего нажатия не листает', () {
      // Кнопку нажали до перехвата — нажатие ушло системе, и громкость
      // она уже поменяла. Листать по одному отпусканию нельзя.
      final VolumeKeyTurner turner = VolumeKeyTurner();
      expect(turner.handle(downRelease, active: true), VolumeKeyOutcome.none);

      turner.handle(downPress, active: false);
      expect(turner.handle(downRelease, active: true), VolumeKeyOutcome.none);
    });

    test('F-READ-26: отпустили другую кнопку — шага нет', () {
      final VolumeKeyTurner turner = VolumeKeyTurner();
      turner.handle(downPress, active: true);
      expect(turner.handle(upRelease, active: true), VolumeKeyOutcome.none);
      // И начатое нажатие забыто.
      expect(turner.handle(downRelease, active: true), VolumeKeyOutcome.none);
    });

    test('F-READ-26: отменённое системой отпускание не листает', () {
      final VolumeKeyTurner turner = VolumeKeyTurner();
      turner.handle(downPress, active: true);
      expect(
        turner.handle(
          const VolumeKeyEvent(
            key: VolumeKey.down,
            pressed: false,
            canceled: true,
          ),
          active: true,
        ),
        VolumeKeyOutcome.none,
      );
    });

    test('F-READ-26: сброс забывает начатое нажатие', () {
      final VolumeKeyTurner turner = VolumeKeyTurner();
      turner.handle(downPress, active: true);
      turner.reset();
      expect(turner.handle(downRelease, active: true), VolumeKeyOutcome.none);
    });
  });

  group('F-READ-26: когда кнопки перехватываются', () {
    bool active({
      bool enabled = true,
      bool bookOpen = true,
      bool onTop = true,
      bool screenReader = false,
    }) {
      return volumeKeysActive(
        settings: VolumeKeySettings(enabled: enabled),
        bookOpen: bookOpen,
        onTop: onTop,
        screenReader: screenReader,
      );
    }

    test('F-READ-26: книга открыта и на экране — перехватываются', () {
      expect(active(), isTrue);
    });

    test('F-READ-26: выключено — ничего не перехватывается', () {
      expect(active(enabled: false), isFalse);
    });

    test('F-READ-26: диктор включён — ничего не перехватывается', () {
      expect(active(screenReader: true), isFalse);
    });

    test('F-READ-26: поверх книги шторка или диалог — громкость', () {
      expect(active(onTop: false), isFalse);
    });

    test('F-READ-26: книга не открыта — громкость', () {
      expect(active(bookOpen: false), isFalse);
    });
  });

  group('F-READ-26: настройки', () {
    test('F-READ-26: по умолчанию включено, «тише» листает вперёд', () {
      final VolumeKeySettings settings = VolumeKeySettings.parse(
        enabled: null,
        downIsForward: null,
      );
      expect(settings, const VolumeKeySettings());
      expect(settings.enabled, isTrue);
      expect(settings.downIsForward, isTrue);
    });

    test('F-READ-26: сохранённое читается как записано', () {
      final VolumeKeySettings settings = VolumeKeySettings.parse(
        enabled: 'false',
        downIsForward: 'false',
      );
      expect(settings.enabled, isFalse);
      expect(settings.downIsForward, isFalse);
      expect(
        settings.copyWith(enabled: true),
        const VolumeKeySettings(downIsForward: false),
      );
    });
  });

  group('F-READ-26: канал MainActivity', () {
    test('F-READ-26: событие кнопки разбирается', () {
      final VolumeKeyEvent? event = volumeKeyEventFrom(<Object?, Object?>{
        'key': 'down',
        'pressed': true,
        'repeat': 3,
        'canceled': false,
      });
      expect(event, isNotNull);
      expect(event!.key, VolumeKey.down);
      expect(event.pressed, isTrue);
      expect(event.repeat, 3);
      expect(event.canceled, isFalse);

      final VolumeKeyEvent? up = volumeKeyEventFrom(<Object?, Object?>{
        'key': 'up',
        'pressed': false,
        'canceled': true,
      });
      expect(up!.key, VolumeKey.up);
      expect(up.pressed, isFalse);
      expect(up.repeat, 0);
      expect(up.canceled, isTrue);
    });

    test('F-READ-26: непонятное событие не разбирается', () {
      // Тогда MainActivity не получает ответа и меняет громкость сама:
      // кнопка не должна замолчать ни при каком сбое.
      expect(volumeKeyEventFrom(null), isNull);
      expect(volumeKeyEventFrom('down'), isNull);
      expect(
        volumeKeyEventFrom(<Object?, Object?>{'key': 'mute', 'pressed': true}),
        isNull,
      );
      expect(volumeKeyEventFrom(<Object?, Object?>{'key': 'down'}), isNull);
    });

    test('F-READ-26: платформе уходит только громкость', () {
      // Листание уже случилось в Dart; MainActivity о нём знать незачем.
      expect(volumeKeyAnswer(VolumeKeyOutcome.raise), 'raise');
      expect(volumeKeyAnswer(VolumeKeyOutcome.lower), 'lower');
      expect(volumeKeyAnswer(VolumeKeyOutcome.none), 'none');
      expect(volumeKeyAnswer(VolumeKeyOutcome.forward), 'none');
      expect(volumeKeyAnswer(VolumeKeyOutcome.back), 'none');
    });
  });
}
