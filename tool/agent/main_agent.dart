/// Точка входа для Claude: отладочная сборка, которой управляет агент
/// (F-REL-11).
///
/// Что это. То же приложение, что `lib/main.dart`, только перед стартом
/// поднимается привязка Marionette (LeanCode, Apache-2.0). Через неё
/// Marionette MCP видит кнопки на экране, нажимает, вводит текст, листает и
/// снимает экран — агент проверяет свою работу вживую, без написания теста.
///
/// Зачем отдельный файл. Marionette — dev-зависимость: код в `lib/` её не
/// видит, и в выпуск она не попадает. Выпуск собирается из `lib/main.dart`.
///
/// Как запускать (полная команда — `tool/agent/README.md`):
/// `flutter run -d windows -t tool/agent/main_agent.dart
///  --dart-define=MEMORIA_DATA_DIR=<новая папка>`.
/// Без папки данных точка входа не стартует: агент не должен открыть
/// базу владельца (F-REL-10).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:memoria/infrastructure/files/app_directory.dart';
import 'package:memoria/main.dart' as app;

Future<void> main() async {
  // F-REL-11: без своей папки данных — отказ, а не тихий старт на
  // данных владельца.
  if (kDataDirOverride.isEmpty) {
    throw StateError(
      'Точке входа агента нужна своя папка данных: '
      '--dart-define=MEMORIA_DATA_DIR=<новая папка>',
    );
  }
  // Marionette работает только в отладочной и профильной сборке: в
  // выпуске VM service закрыт.
  if (kReleaseMode) {
    throw StateError('Точка входа агента — только debug/profile');
  }
  // Привязка Marionette — до привязки приложения: `startApp` вызовет
  // `WidgetsFlutterBinding.ensureInitialized()` и получит эту же.
  MarionetteBinding.ensureInitialized();
  await app.startApp();
  // Только на ПК: на телефоне сворачивание и возврат — настоящие события,
  // по ним, например, «Устройство» заново ищет книги. Глушить их нельзя.
  if (Platform.isWindows) {
    _alwaysVisible();
    _keepFramesComing();
  }
}

/// Приложение агента всегда считает себя на экране.
///
/// Агент работает, пока владелец занят своим: окно приложения закрыто
/// другими окнами, и Windows сообщает Flutter «скрыто». Тогда приложение
/// честно экономит силы — раздел «Устройство» ставит обход файлов на
/// паузу, кадры не рисуются, — и проверять нечего. Здесь сообщения о
/// скрытии заменяются на «на экране». Только точка входа агента.
void _alwaysVisible() {
  ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(
    SystemChannels.lifecycle.name,
    (ByteData? message) async {
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      return null;
    },
  );
  WidgetsBinding.instance.handleAppLifecycleStateChanged(
    AppLifecycleState.resumed,
  );
}

/// Рисовать кадры и в скрытом окне.
///
/// Окно, закрытое другими окнами, движок Windows может не перерисовывать:
/// нажатие агента меняет состояние, а экран и снимок остаются прежними.
/// Кадр заказывается принудительно пять раз в секунду.
void _keepFramesComing() {
  Timer.periodic(const Duration(milliseconds: 200), (_) {
    SchedulerBinding.instance.scheduleForcedFrame();
  });
}
