import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../sno/flags.dart';

/// Папка данных приложения: база, обложки, копии книг.
///
/// Единственное место, где приложение спрашивает у системы, куда ему
/// писать. У основного приложения это папка от системы, как и прежде.
/// У сборки ветви СНО2026 — своя подпапка в ней (SNO-F-CFG-01): на
/// Windows три программы из одного кода получают от системы одну и ту
/// же папку, и без подпапки ветвь открыла бы базу основного приложения.
Future<Directory> appDataDirectory() async {
  final Directory support = await getApplicationSupportDirectory();
  final Directory data = dataDirectoryIn(support, Sno.branch);
  if (!await data.exists()) {
    await data.create(recursive: true);
  }
  return data;
}

/// Папка данных ветви [branch] внутри [support].
///
/// Правило вынесено из [appDataDirectory], чтобы проверяться без
/// платформенного канала и для всех ветвей одним прогоном тестов.
Directory dataDirectoryIn(Directory support, String branch) {
  final String folder = dataFolderFor(branch);
  return folder.isEmpty ? support : Directory(p.join(support.path, folder));
}
