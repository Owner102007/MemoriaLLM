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
  runApp(
    MemoriaApp(
      themeController: themeController,
      services: AppServices.production(data),
    ),
  );
}
