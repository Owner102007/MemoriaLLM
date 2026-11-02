/// Папка данных приложения (F-REL-10).
///
/// Своя папка для автопрогона задаётся только при сборке. Этот тест
/// идёт в обычном прогоне (`flutter test`, CI) — без `MEMORIA_DATA_DIR`,
/// как и любой выпуск, — и проверяет, что подмены там нет.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/infrastructure/files/app_directory.dart';

void main() {
  test('F-REL-10: в обычной сборке своей папки данных нет', () {
    expect(kDataDirOverride, isEmpty);
  });
}
