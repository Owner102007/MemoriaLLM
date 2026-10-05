import 'package:flutter/widgets.dart';

import 'application/app_services.dart';
import 'application/data/app_data.dart';
import 'application/theme/theme_controller.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final AppData data = await AppData.open();
  final ThemeController themeController = await ThemeController.restore(
    data.settings,
  );
  final AppServices services = AppServices.production(data);
  // SNO-F-REC-01: сессия записи поднимается до первого кадра — полка
  // незавершённой сессии встаёт под замок сразу.
  await restoreRecording(services);
  runApp(MemoriaApp(themeController: themeController, services: services));
}

/// Поднимает сессию записи, если она есть в этой сборке.
///
/// Запуск приложения от неё не зависит: не поднялась — приложение
/// открывается без неё.
Future<void> restoreRecording(AppServices services) async {
  try {
    await services.recording?.restore();
  } on Object {
    // Состояние сессии не прочиталось: раздел «Тестирование» покажет
    // «Старт записи», папка записи останется на диске.
  }
}
