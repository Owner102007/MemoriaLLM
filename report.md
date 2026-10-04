# Прогон CI №160

- коммит: `f1bcf552d447223819b14202b0c74ba90573c948`
- ветка: `main`
- анализ и тесты: **success**
- сборка APK: **success**
- сборка Windows: **success**
- страница прогона:
  https://github.com/Owner102007/MemoriaLLM/actions/runs/37178528494

## analyze
```
Resolving dependencies...
Downloading packages...
  archive 4.2.0 (4.3.0 available)
  built_collection 5.1.1 (5.1.2 available)
  cli_util 0.5.2 (0.6.0 available)
  code_assets 2.0.0 (2.1.0 available)
  cross_file 0.3.5+5 (0.4.0 available)
  cupertino_ui 1.0.2 (1.1.1 available)
  drift 2.35.0 (2.35.1 available)
  drift_dev 2.35.0 (2.35.1 available)
  fast_file_picker 1.0.2 (2.0.1 available)
  flutter_lints 5.0.0 (6.0.0 available)
  get_it 9.2.1 (9.3.0 available)
  image 4.9.2 (4.10.1 available)
  ios_document_picker 1.0.0 (2.0.2 available)
  jni 1.0.3 (1.1.0 available)
  lints 5.1.1 (6.1.0 available)
  macos_file_picker 0.7.3 (2.0.0 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  material_ui 1.2.0 (1.5.0 available)
  native_toolchain_c 0.19.4 (0.19.5 available)
  objective_c 9.6.0 (9.6.2 available)
  pdfium_dart 0.3.0 (0.3.1 available)
  pdfium_flutter 0.3.0 (0.3.1 available)
  pdfrx 2.6.1 (2.6.5 available)
  pdfrx_engine 0.6.0 (0.6.1 available)
  saf_util 3.1.0 (3.1.1 available)
  sqlite3 3.5.2 (3.7.0 available)
  sqlite3_flutter_libs 0.5.42 (0.6.0+eol available)
  test_api 0.7.12 (0.7.14 available)
  url_launcher 6.3.2 (6.3.3 available)
  vector_math 2.4.2 (2.4.3 available)
Got dependencies!
30 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing MemoriaLLM...                                         
No issues found! (ran in 17.7s)
```

## codegen
```
  compiling builders/aot
  38s compiling builders/aot
  0s drift_dev on 904 inputs; lib/application/app_services.dart
  12s drift_dev on 904 inputs: 1 output; spent 9s analyzing, 2s resolving, 1s sdk; lib/application/build_info.dart
  13s drift_dev on 904 inputs: 155 output; spent 10s analyzing, 2s resolving, 1s sdk; test/library/device_books_screen_test.dart
  15s drift_dev on 904 inputs: 264 output, 24 no-op; spent 11s analyzing, 2s resolving, 1s sdk; lib/infrastructure/database/connection.dart
  17s drift_dev on 904 inputs: 267 output, 25 no-op; spent 13s analyzing, 2s resolving, 1s sdk; lib/infrastructure/files/android_book_storage.dart
  17s drift_dev on 904 inputs: 226 skipped, 425 output, 253 no-op; spent 13s analyzing, 2s resolving, 1s sdk
  0s source_gen:combining_builder on 452 inputs; lib/application/app_services.dart
  0s source_gen:combining_builder on 452 inputs: 226 skipped, 1 output, 225 no-op
  Built with build_runner/aot in 56s; wrote 426 outputs.
```

## measures
```
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | открытие книги | было 22.9 мс | стало 4.8 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | открытие и рамка страницы 600 | было 26.6 мс | стало 10.0 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | переход на соседнюю страницу | было 0.5 мс | стало 0.2 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | открытие книги | было 19.5 мс | стало 2.8 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | открытие и рамка страницы 60 | было 29.6 мс | стало 9.0 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | переход на соседнюю страницу | было 2.9 мс | стало 0.3 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | открытие книги | было 2.5 мс | стало 2.0 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | открытие и рамка страницы 1 | было 9.6 мс | стало 17.9 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | переход на соседнюю страницу | было 5.7 мс | стало 0.2 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | переход на непосчитанную страницу | было 19.1 мс | стало 23.4 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | измерить все страницы | 20.1 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | измерить все страницы | 19.5 мс
Shell: ЗАМЕР F-READ-15 | book_120_pages.pdf | разных ширин рамки | было 10 | стало 1 | страниц с расширенной рамкой 2 из 120
Shell: ЗАМЕР F-READ-15 | book_120_pages.pdf | рамка: вся книга постранично против выборки из 16 страниц | было 438.2 мс | стало 70.3 мс
Shell: ЗАМЕР F-TEXT-04 | book_120_pages.pdf | страниц 120 | текста 337988 знаков | проход 231.7 мс | первый поиск 278.6 мс | второй поиск 28.2 мс
Shell: ЗАМЕР F-TEXT-04 | huge_1200_pages.pdf | страниц 1200 | текста 16800 знаков | проход 386.7 мс | первый поиск 554.8 мс | второй поиск 38.2 мс
Shell: ЗАМЕР F-TEXT-04 | scan_no_text.pdf | страниц 2 | текста 0 знаков | проход 0.9 мс | первый поиск 1.8 мс | второй поиск 0.1 мс
```

## tests
```
релки в развороте шагают листами
01:13 +1286: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация BUG-01: стрелки в развороте шагают листами
01:13 +1287: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация BUG-01: стрелки в развороте шагают листами
01:13 +1288: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация BUG-01: стрелки в развороте шагают листами
01:13 +1289: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация BUG-01: стрелки в развороте шагают листами
01:13 +1290: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация BUG-01: стрелки в развороте шагают листами
01:13 +1291: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация BUG-01: стрелки в развороте шагают листами
01:13 +1292: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация BUG-01: стрелки в развороте шагают листами
01:13 +1293: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация BUG-01: стрелки в развороте шагают листами
01:13 +1294: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация BUG-01: стрелки в развороте шагают листами
01:13 +1295: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация BUG-01: стрелки в развороте шагают листами
01:13 +1296: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация BUG-01: стрелки в развороте шагают листами
01:13 +1297: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: смена режима не теряет место обратный переход возвращает примерно туда же
01:13 +1298: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1299: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1300: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1301: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1302: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1303: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1304: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1305: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1306: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1307: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1308: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1309: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1310: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1311: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1312: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1313: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1314: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1315: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1316: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1317: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1318: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1319: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1320: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1321: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1322: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1323: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1324: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1325: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1326: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1327: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1328: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1329: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
01:13 +1330: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация ползунок переводит на выбранную страницу
01:14 +1331: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация BUG-39: протяжка ползунка открывает одну страницу
01:14 +1332: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация BUG-39: бегунок остановили, не отпуская, — страница открыта
01:14 +1333: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация F-READ-28: бегунок ждёт конца перехода и не отскакивает
01:14 +1334: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_spread_test.dart: F-READ-06: листание разворота BUG-01: разворот листается парами, экран не повторяется
01:14 +1335: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_spread_test.dart: F-READ-06: листание разворота BUG-01: разворот листается парами, экран не повторяется
01:14 +1336: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление открывается и переводит на выбранный раздел
01:14 +1337: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление открывается и переводит на выбранный раздел
01:14 +1338: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление открывается и переводит на выбранный раздел
01:14 +1339: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление открывается и переводит на выбранный раздел
01:14 +1340: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление открывается и переводит на выбранный раздел
01:14 +1341: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление открывается и переводит на выбранный раздел
01:14 +1342: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление открывается и переводит на выбранный раздел
01:14 +1343: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление открывается и переводит на выбранный раздел
01:14 +1344: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление открывается и переводит на выбранный раздел
01:14 +1345: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление открывается и переводит на выбранный раздел
01:14 +1346: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление открывается и переводит на выбранный раздел
01:15 +1347: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_spread_test.dart: гонка переходов BUG-11: побеждает последний запрошенный переход
01:15 +1348: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление книга без оглавления объясняет, почему его нет
01:15 +1349: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление книга без оглавления объясняет, почему его нет
01:15 +1350: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_spread_test.dart: гонка переходов BUG-11: два быстрых шага вперёд — это два шага
01:15 +1351: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
01:15 +1352: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
01:15 +1353: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
01:15 +1354: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск переход к найденному несёт само совпадение
01:15 +1355: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск кнопка поиска стоит в верхней панели
01:15 +1356: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск пустой результат так и написан
01:15 +1357: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:15 +1358: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1359: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1360: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1361: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1362: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1363: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1364: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1365: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1366: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1367: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1368: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1369: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1370: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1371: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1372: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1373: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1374: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1375: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
01:16 +1376: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым второй результат выбирается без повторного открытия
01:16 +1377: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
01:16 +1378: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F3 при открытом поиске — тоже выбор результата
01:17 +1379: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1380: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1381: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1382: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1383: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1384: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1385: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1386: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1387: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1388: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1389: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1390: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1391: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1392: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1393: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1394: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
01:17 +1395: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: F-READ-13: третий уровень — назначенный кусок соседа F-READ-13: маска с соседями рисуется и нажатий не ловит
01:17 +1396: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: F-READ-13: третий уровень — назначенный кусок соседа F-READ-13: маска с соседями рисуется и нажатий не ловит
01:17 +1397: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: F-READ-13: третий уровень — назначенный кусок соседа F-READ-13: маска с соседями рисуется и нажатий не ловит
01:17 +1398: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым при повторном открытии запрос и место в списке на месте
01:17 +1399: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым при повторном открытии запрос и место в списке на месте
01:17 +1400: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым при повторном открытии запрос и место в списке на месте
01:17 +1401: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым нажатие по запросу возвращает ко вводу
01:18 +1402: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
01:18 +1403: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: поле в полосе читается на своём фоне
01:18 +1404: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: телефон в альбоме — полоса тоже снизу
01:18 +1405: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
01:18 +1406: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
01:18 +1407: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
01:18 +1408: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
01:18 +1409: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
01:18 +1410: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
01:18 +1411: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
01:18 +1412: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
01:18 +1413: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
01:18 +1414: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
01:18 +1415: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
01:18 +1416: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
01:18 +1417: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
01:18 +1418: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
01:18 +1419: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: с клавиатурой полоса стоит над ней
01:18 +1420: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: в тесноте полоса сжимается, а не ломается
01:19 +1421: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: поиск, открытый кнопкой, прячет панели чтения
01:19 +1422: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
01:19 +1423: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
01:19 +1424: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
01:19 +1425: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
01:19 +1426: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
01:19 +1427: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
01:19 +1428: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
01:19 +1429: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
01:19 +1430: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
01:19 +1431: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
01:19 +1432: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
01:19 +1433: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
01:19 +1434: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
01:19 +1435: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
01:19 +1436: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: F-TEXT-04: поиск по кэшу текста неполный поиск называет остаток, и он убывает
01:19 +1437: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: пока набирают запрос, клавиши — у поля
01:19 +1438: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: пока набирают запрос, клавиши — у поля
01:19 +1439: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: пока набирают запрос, клавиши — у поля
01:19 +1440: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: пока набирают запрос, клавиши — у поля
01:19 +1441: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: пока набирают запрос, клавиши — у поля
01:19 +1442: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: пока набирают запрос, клавиши — у поля
01:19 +1443: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: пока набирают запрос, клавиши — у поля
01:19 +1444: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
01:19 +1445: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
01:20 +1446: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура стрелки и пробел листают книгу
01:20 +1447: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-25: листают клавиши из таблицы читателя
01:20 +1448: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура Ctrl+F открывает поиск, Esc его закрывает
01:20 +1449: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура Esc без открытых панелей снимает выделение
01:20 +1450: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: листание вперёд листают стрелки, пробел и PageDown
01:20 +1451: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 ведёт по совпадениям по кругу
01:20 +1452: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 ведёт по совпадениям по кругу
01:20 +1453: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 ведёт по совпадениям по кругу
01:20 +1454: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 ведёт по совпадениям по кругу
01:20 +1455: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 ведёт по совпадениям по кругу
01:20 +1456: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 ведёт по совпадениям по кругу
01:20 +1457: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 ведёт по совпадениям по кругу
01:20 +1458: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 ведёт по совпадениям по кругу
01:20 +1459: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 ведёт по совпадениям по кругу
01:20 +1460: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 ведёт по совпадениям по кругу
01:20 +1461: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 ведёт по совпадениям по кругу
01:20 +1462: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст и стрелки с Page тоже: ими двигают курсор
01:20 +1463: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1464: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1465: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1466: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1467: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1468: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1469: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1470: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1471: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1472: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1473: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1474: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1475: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1476: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1477: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1478: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1479: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1480: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1481: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
01:20 +1482: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: при двух совпадениях первое Shift+F3 — на второе
01:20 +1483: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура новый запрос начинает счёт совпадений заново
01:20 +1484: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура пробел и Backspace в поле поиска принадлежат полю
01:20 +1485: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 работает и из поля: его поле не ждёт
01:20 +1486: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: F11 разворачивает чтение и возвращает окно
01:20 +1487: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: без окна F11 уходит мимо экрана чтения
01:20 +1488: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc возвращает окно, когда закрывать нечего
01:20 +1489: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc сначала прячет панели и снимает выделение
01:21 +1490: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
01:21 +1491: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура без найденного F3 молчит
01:21 +1492: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: матрица просмотрщика масштаб берётся из раскладки листа
01:21 +1493: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: матрица просмотрщика вторая страница разворота сдвигает начало документа
01:21 +1494: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: матрица просмотрщика щипок читателя накладывается сверху
01:21 +1495: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: обратный ход: что читатель добавил сам нетронутая страница даёт единичное преобразование
01:21 +1496: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: обратный ход: что читатель добавил сам щипок возвращается тем же, каким его положили
01:21 +1497: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: обратный ход: что читатель добавил сам вырожденная матрица преобразования не даёт
01:21 +1498: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик F-READ-12: лист ниже по документу сдвигает матрицу вверх
01:21 +1499: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик F-READ-12: верх листа встаёт туда, куда велит раскладка
01:21 +1500: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик F-READ-12: обратный ход в столбике возвращает тот же щипок
01:21 +1501: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик F-READ-12: нетронутый лист в столбике не даёт преобразования
01:21 +1502: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик F-READ-12: точка экрана переводится в точку листа в столбике
01:21 +1503: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик BUG-40: возврат просмотрщика в столбике отклоняется так же
01:21 +1504: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: точка экрана в координатах документа перевод обратим
01:21 +1505: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: точка экрана в координатах документа перевод обратим и после щипка
01:21 +1506: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: точка экрана в координатах документа вырожденная раскладка точки не даёт
01:21 +1507: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий над выделением, если сверху есть место
01:21 +1508: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий под выделением, если сверху места нет
01:21 +1509: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий панель не вылезает за края экрана
01:21 +1510: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий выделение во весь экран не выталкивает панель наружу
01:21 +1511: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: вид листа переводит страницу в экран нетронутая страница ложится ровно по раскладке
01:21 +1512: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: вид листа переводит страницу в экран после щипка едет вместе со страницей
01:21 +1513: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: маска ложится туда же, где лист без щипка лист и полоса совпадают с раскладкой
01:21 +1514: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: маска ложится туда же, где лист щипок двигает и лист, и полосу одинаково
01:21 +1515: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: маска ложится туда же, где лист пустая раскладка даёт пустые прямоугольники
01:21 +1516: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: предел свободы при отпертом замке нетронутое преобразование не трогается
01:21 +1517: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: предел свободы при отпертом замке масштаб держится в границах
01:21 +1518: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: предел свободы при отпертом замке страницу нельзя увести с экрана
01:21 +1519: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: предел свободы при отпертом замке упёршись в предел масштаба, страница не прыгает вбок
01:21 +1520: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: предел свободы при отпертом замке мусор на входе даёт нетронутый лист
01:21 +1521: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-40: движение читателя — только пока раскладка стоит BUG-40: возврат просмотрщика похож на сдвиг через полкниги
01:21 +1522: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-40: движение читателя — только пока раскладка стоит BUG-40: пока страницы перекладываются, возврат не принимается
01:21 +1523: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-40: движение читателя — только пока раскладка стоит BUG-40: то, что читатель выставил сам, перекладка не трогает
01:21 +1524: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-40: движение читателя — только пока раскладка стоит BUG-40: раскладка встала — жест читателя принимается
01:21 +1525: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-40: движение читателя — только пока раскладка стоит BUG-40: при запертом замке страницу не двигает никто
01:21 +1526: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-26: замок возвращает сдвинутую страницу BUG-26: сдвинутая без масштаба страница встаёт на место
01:21 +1527: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-26: замок возвращает сдвинутую страницу BUG-26: страница, уехавшая к краю экрана, тоже возвращается
01:21 +1528: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-26: замок возвращает сдвинутую страницу BUG-26: осознанный масштаб замок сохраняет вместе со сдвигом
01:21 +1529: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-26: замок возвращает сдвинутую страницу BUG-26: нетронутая страница остаётся нетронутой
01:21 +1530: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-26: замок возвращает сдвинутую страницу BUG-26: мусор на входе даёт нетронутый лист
01:21 +1531: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: какие рамки считать заранее вперёд по ходу чтения — два листа, назад — один
01:21 +1532: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: какие рамки считать заранее читатель листает назад — готовится то, что позади
01:21 +1533: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: какие рамки считать заранее у края книги готовить за краем нечего
01:21 +1534: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: какие рамки считать заранее в развороте лист — две страницы, и готовятся обе
01:21 +1535: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика запас 1 — ровно по листу с каждой стороны
01:21 +1536: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика запас 2 — по два листа, третий не захвачен
01:21 +1537: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика перекос полей не теряет соседа и не цепляет лишнего
01:21 +1538: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика в развороте запас достаёт до дальней страницы соседа
01:21 +1539: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика запас 0 и широкое окно запаса не просят
01:21 +1540: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика вырожденные размеры — ноль, а не бесконечность
01:21 +1541: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-12: запас соседних листов в столбике F-READ-12: с любой полосы запас 1 — по листу сверху и снизу
01:21 +1542: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-12: запас соседних листов в столбике F-READ-12: запас 2 — по два листа, третий не захвачен
01:21 +1543: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-12: запас соседних листов в столбике F-READ-12: запас 0 запаса не просит
01:21 +1544: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-12: запас соседних листов в столбике F-READ-12: вырожденные размеры — ноль, а не бесконечность
01:21 +1545: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки предел пикселей: страница A4 — около двух с половиной
01:21 +1546: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки у страницы без размеров предела нет
01:21 +1547: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки первая картинка чуть мельче нужного экрану
01:21 +1548: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки рамки страниц гуляют — картинки не перерисовываются
01:21 +1549: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки удерживаемый масштаб крупнее нужного не остаётся
01:21 +1550: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки страница стала намного крупнее — картинки догоняют
01:21 +1551: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки бессмысленный запрос масштаба ничего не меняет
01:21 +1552: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: настройки показа страницы без сохранённого — сразу, запас по платформе
01:21 +1553: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: настройки показа страницы сохранённое главнее умолчания
01:21 +1554: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: настройки показа страницы мусор в базе не ломает чтение
01:21 +1555: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: настройки показа страницы выключенная ступенька запаса не держит
01:22 +1556: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране книга и подпись нарисованы
01:22 +1557: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
01:22 +1558: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
01:22 +1559: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
01:22 +1560: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
01:22 +1561: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
01:22 +1562: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
01:22 +1563: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
01:22 +1564: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
01:22 +1565: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
01:23 +1566: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: по умолчанию включена тёмно-красная тема
01:23 +1567: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
01:24 +1568: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: на пустой полке предложено добавить книги
01:24 +1569: All tests passed!
```

## sessions
```
Running build hooks...Running build hooks...Проверен PROGRESS.md; плана нет (../docs/dev_plan_sessions.md) — пропущен.
Номера сессий в порядке.
```
