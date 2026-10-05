import 'dart:async';

import 'package:flutter/widgets.dart';

import 'application/app_services.dart';
import 'application/data/app_data.dart';
import 'application/theme/theme_controller.dart';
import 'sno/recording/records.dart';
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
  final bool restored = await restoreRecording(services);
  await recoverRecords(services, restored: restored);
  runApp(MemoriaApp(themeController: themeController, services: services));
}

/// Поднимает сессию записи, если она есть в этой сборке.
///
/// Запуск приложения от неё не зависит: не поднялась — приложение
/// открывается без неё. Отвечает, известно ли теперь, есть ли
/// незавершённая сессия.
Future<bool> restoreRecording(AppServices services) async {
  try {
    await services.recording?.restore();
    return true;
  } on Object {
    // Состояние сессии не прочиталось: раздел «Тестирование» покажет
    // «Старт записи», папка записи останется на диске.
    return false;
  }
}

/// Подбирает записи, оставшиеся папками (SNO-F-REC-05, SNO-F-REC-08).
///
/// Папки без сессии переезжают к завершённым до первого кадра — пока
/// новая запись начаться не может; упаковка в архивы идёт следом и
/// запуска не задерживает: папок прежних сборок может быть много.
///
/// [restored] — поднялась ли сессия записи. Если нет, неизвестно,
/// чья папка лежит среди незавершённых, и подбирать её нельзя: это
/// может быть запись, которую ещё предстоит закрыть.
Future<void> recoverRecords(
  AppServices services, {
  required bool restored,
}) async {
  final DeviceRecords? records = services.records;
  if (records == null) {
    return;
  }
  if (restored) {
    try {
      await records.adoptOrphans();
    } on Object {
      // Папка записей не прочиталась: записи остаются как лежали.
    }
  }
  unawaited(_packPending(records));
}

Future<void> _packPending(DeviceRecords records) async {
  try {
    await records.packPending();
  } on Object {
    // Не упаковалось сейчас — упакуется при следующем запуске.
  }
}
