import 'dart:async';

import 'package:flutter/widgets.dart';

import 'application/app_services.dart';
import 'application/data/app_data.dart';
import 'application/theme/theme_controller.dart';
import 'sno/index/shelf_reading.dart';
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
  await prepareShelf(services);
  runApp(MemoriaApp(themeController: themeController, services: services));
}

/// Поднимает итог подготовки книг и продолжает её (SNO-F-IDX-04).
///
/// Только в сборке ветви II; в остальных подготовки нет, и вызов пуст.
/// Итог читается до первого кадра — это одна запись настроек, — а сам
/// проход по полке начинается чуть погодя: первые секунды движок PDF
/// занят обложками.
Future<void> prepareShelf(AppServices services) async {
  // SNO-F-MAP-01: время в книгах — одна запись настроек; отказ чтения
  // запуску не мешает.
  await services.bookTimes?.restore();
  final ShelfReading? reading = services.shelfReading;
  if (reading == null) {
    return;
  }
  await reading.restore();
  reading.start(delay: kShelfReadingDelay);
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
/// чья папка лежит среди записей, и ни подбирать, ни упаковывать
/// папки нельзя: это может быть запись, которую ещё предстоит
/// закрыть. Тем же правилом живут и сами записи
/// (`RecordingSession.known`).
Future<void> recoverRecords(
  AppServices services, {
  required bool restored,
}) async {
  final DeviceRecords? records = services.records;
  if (records == null || !restored) {
    return;
  }
  try {
    await records.adoptOrphans();
  } on Object {
    // Папка записей не прочиталась: записи остаются как лежали.
  }
  unawaited(_packPending(records));
}

Future<void> _packPending(DeviceRecords records) async {
  try {
    await records.packPending();
  } on Object {
    // Не упаковалось сейчас — упакуется при следующем запуске.
  }
  // SNO-F-REC-13: архивы, у которых ещё нет второй копии в общей папке
  // устройства, получают её сейчас — и записи прежних сборок тоже.
  try {
    await records.backupPending();
  } on Object {
    // Копия не легла сейчас — ляжет при следующем запуске.
  }
}
