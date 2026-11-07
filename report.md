# Прогон CI №460

- коммит: `b17d527524dd127fe4abd607c2b2199c35cc6f7a`
- ветка: `main`
- анализ и тесты: **success**
- сборка APK: **success**
- сборка Windows: **success**
- спутник взгляда: тесты **success**, сборка **success**
- страница прогона:
  https://github.com/Owner102007/MemoriaLLM/actions/runs/42365291807

## analyze
```
Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 108.0.0 (111.0.0 available)
  analyzer 14.4.0 (14.7.0 available)
  archive 4.2.0 (4.6.0 available)
  build 4.0.11 (5.0.0 available)
  build_config 1.3.3 (1.4.0 available)
  build_daemon 4.1.6 (4.1.7 available)
  build_runner 2.16.1 (2.17.1 available)
  built_collection 5.1.1 (6.0.0 available)
  cli_util 0.5.2 (0.6.0 available)
  code_assets 2.0.0 (2.2.0 available)
  cross_file 0.3.5+5 (0.4.0 available)
  crypto 3.0.7 (3.0.8 available)
  cupertino_ui 1.0.2 (1.1.6 available)
  dart_style 3.1.13 (3.1.14 available)
  drift 2.35.0 (2.35.3 available)
  drift_dev 2.35.0 (2.35.2 available)
  fast_file_picker 1.0.2 (2.0.1 available)
  file_selector_ios 0.5.3+6 (0.5.3+7 available)
  file_selector_macos 0.9.5+1 (0.9.5+2 available)
  flutter_lints 5.0.0 (6.0.0 available)
  get_it 9.2.1 (9.3.0 available)
  http_multi_server 3.2.2 (3.2.3 available)
  image 4.9.2 (4.12.0 available)
  ios_document_picker 1.0.0 (2.0.2 available)
  jni 1.0.3 (1.1.2 available)
  jni_flutter 1.0.3 (1.0.4+1 available)
  lints 5.1.1 (6.1.0 available)
  macos_file_picker 0.7.3 (2.0.0 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  material_ui 1.2.0 (1.10.0 available)
  native_toolchain_c 0.19.4 (0.19.6 available)
  objective_c 9.6.0 (9.6.3 available)
  pdfium_dart 0.3.0 (0.4.1 available)
  pdfium_flutter 0.3.0 (0.4.1 available)
  pdfrx 2.6.1 (2.12.0 available)
  pdfrx_engine 0.6.0 (0.9.1 available)
  posix 6.5.2 (6.5.4 available)
  pubspec_parse 1.6.0 (1.7.0 available)
  saf_util 3.1.0 (3.1.1 available)
  shelf 1.4.2 (1.4.3 available)
  source_gen 4.3.0 (4.3.1 available)
  sqlite3 3.5.2 (3.9.0 available)
  sqlite3_flutter_libs 0.5.42 (0.6.0+eol available)
  sqlparser 0.45.0 (0.45.1 available)
  synchronized 3.4.2 (3.6.1 available)
  test_api 0.7.12 (0.7.15 available)
  url_launcher 6.3.2 (6.3.3 available)
  vector_math 2.4.2 (2.4.4 available)
  vm_service 15.3.0 (15.4.0 available)
  web 1.1.1 (1.1.2 available)
Got dependencies!
50 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing MemoriaLLM...                                         
No issues found! (ran in 21.4s)
```

## codegen
```
  compiling builders/aot
  36s compiling builders/aot
  0s drift_dev on 1704 inputs; integration_test/app_test.dart
  14s drift_dev on 1704 inputs: 1 output; spent 10s analyzing, 2s resolving, 1s sdk; integration_test/fixture_pdf.dart
  15s drift_dev on 1704 inputs: 375 output; spent 11s analyzing, 2s resolving, 1s sdk; test/sno/flags_test.dart
  17s drift_dev on 1704 inputs: 490 output, 28 no-op; spent 13s analyzing, 2s resolving, 1s sdk; lib/infrastructure/database/connection.dart
  19s drift_dev on 1704 inputs: 493 output, 29 no-op; spent 15s analyzing, 2s resolving, 1s sdk; lib/infrastructure/files/android_book_storage.dart
  20s drift_dev on 1704 inputs: 91 skipped, 808 output, 136 no-op; spent 15s analyzing, 2s resolving, 1s sdk, 1s building; lib/infrastructure/database/app_database.dart.types.temp.dart
  21s drift_dev on 1704 inputs: 426 skipped, 808 output, 470 no-op; spent 15s analyzing, 2s resolving, 2s building, 1s sdk
  0s source_gen:combining_builder on 852 inputs; integration_test/app_test.dart
  0s source_gen:combining_builder on 852 inputs: 426 skipped, 1 output, 425 no-op
  Built with build_runner/aot in 58s; wrote 809 outputs.
```

## measures
```
Shell: ЗАМЕР ALG-MAP-03 | веса BM25 | расхождение с эталоном | 0.0
Shell: ЗАМЕР ALG-MAP-06 | координаты | расхождение с эталоном | 0.0
Shell: ЗАМЕР ALG-MAP-08 | досадка | расхождение с эталоном | 0.0
Shell: ЗАМЕР F-MAP-17 | эталон | книг пересажено | 7
Shell: ЗАМЕР ALG-MAP-12 | кадр карты на 300 книг | бюджет 16 мс | 2.97 мс на кадр
Shell: ЗАМЕР ALG-MAP-06 | раскладка 1000 книг | бюджет 2 с | 640 мс
Shell: ЗАМЕР ALG-MAP-19 | свой текст | слов 123 | доля 0.984
Shell: ЗАМЕР ALG-MAP-19 | шум, зерно 1 | 5 % — 0.772 | 30 % — 0.174
Shell: ЗАМЕР ALG-MAP-19 | шум, зерно 2 | 5 % — 0.734 | 30 % — 0.236
Shell: ЗАМЕР ALG-MAP-19 | шум, зерно 3 | 5 % — 0.706 | 30 % — 0.225
Shell: ЗАМЕР ALG-MAP-19 | шум, зерно 4 | 5 % — 0.774 | 30 % — 0.222
Shell: ЗАМЕР ALG-MAP-19 | шум, зерно 5 | 5 % — 0.772 | 30 % — 0.185
Shell: ЗАМЕР ALG-MAP-19 | сломанный слой | доля 0.008
Shell: ЗАМЕР ALG-MAP-12 | отбор подписей из 300 | бюджет 4 мс | встало 24 | 0.219 мс на кадр
Shell: ЗАМЕР F-MAP-16 | составная библиотека 240 книг, 24 темы | созвездий 24, ARI 1.0 | 645 мс
Shell: ЗАМЕР ALG-MAP-06 | раскладка 10000 книг | бюджет 20 с | 5829 мс
02:13 +2693 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_frames_test.dart: SNO-F-REC-03: сборщик потока кадров SNO-F-REC-03: ЗАМЕР — сколько весит поток за сорок минут чтения
ЗАМЕР SNO-F-REC-03: кадр чтения 753 байт; за 40 минут ~480 кадров, ~352 КБ
02:13 +2700 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_frames_test.dart: SNO-ALG-REC-02: экраны без листа — по эталону (шаг 31) SNO-F-REC-03: ЗАМЕР — сколько весит кадр полки и кадр карты
ЗАМЕР SNO-F-REC-03: кадр полки (48 книг) 10284 байт, минута прокрутки ~3012 КБ; кадр карты (60 звёзд) 6427 байт
ЗАМЕР: поток ввода за 40 минут — 1117 КБ, строк 5381, касаний 3000
Shell: ЗАМЕР ALG-MAP-18 | 1200 страниц | паспорт | 22 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | открытие книги | было 13.8 мс | стало 2.0 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | открытие и рамка страницы 600 | было 12.7 мс | стало 4.9 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | переход на соседнюю страницу | было 0.2 мс | стало 0.2 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | открытие книги | было 17.9 мс | стало 1.5 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | открытие и рамка страницы 60 | было 20.5 мс | стало 7.2 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | переход на соседнюю страницу | было 2.8 мс | стало 0.2 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | открытие книги | было 0.9 мс | стало 0.9 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | открытие и рамка страницы 1 | было 6.7 мс | стало 7.6 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | переход на соседнюю страницу | было 5.5 мс | стало 0.2 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | переход на непосчитанную страницу | было 5.6 мс | стало 6.3 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | измерить все страницы | 13.2 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | измерить все страницы | 16.6 мс
Shell: ЗАМЕР F-READ-15 | book_120_pages.pdf | разных ширин рамки | было 10 | стало 1 | страниц с расширенной рамкой 2 из 120
Shell: ЗАМЕР F-READ-15 | book_120_pages.pdf | рамка: вся книга постранично против выборки из 16 страниц | было 365.7 мс | стало 61.4 мс
Shell: ЗАМЕР F-TEXT-04 | book_120_pages.pdf | страниц 120 | текста 337988 знаков | проход 166.5 мс | первый поиск 203.2 мс | второй поиск 19.8 мс
Shell: ЗАМЕР F-TEXT-04 | huge_1200_pages.pdf | страниц 1200 | текста 16800 знаков | проход 166.2 мс | первый поиск 205.5 мс | второй поиск 15.3 мс
Shell: ЗАМЕР F-TEXT-04 | scan_no_text.pdf | страниц 2 | текста 0 знаков | проход 0.5 мс | первый поиск 1.4 мс | второй поиск 0.0 мс
```

## tests
```
рганизатору не предлагается
02:42 +2972 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-01: после второй неудачи спутник перезапустился — модели нет, и писать взгляд организатору не предлагается
02:42 +2973 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-01: после второй неудачи спутник перезапустился — модели нет, и писать взгляд организатору не предлагается
02:42 +2974 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-01: после второй неудачи спутник перезапустился — модели нет, и писать взгляд организатору не предлагается
02:42 +2975 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-01: после второй неудачи спутник перезапустился — модели нет, и писать взгляд организатору не предлагается
02:42 +2976 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-01: после второй неудачи спутник перезапустился — модели нет, и писать взгляд организатору не предлагается
02:42 +2977 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-01: после второй неудачи спутник перезапустился — модели нет, и писать взгляд организатору не предлагается
02:42 +2978 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-01: после второй неудачи спутник перезапустился — модели нет, и писать взгляд организатору не предлагается
02:42 +2979 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-01: после второй неудачи спутник перезапустился — модели нет, и писать взгляд организатору не предлагается
02:42 +2980 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-01: после второй неудачи спутник перезапустился — модели нет, и писать взгляд организатору не предлагается
02:42 +2981 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-01: после второй неудачи спутник перезапустился — модели нет, и писать взгляд организатору не предлагается
02:42 +2982 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-01: после второй неудачи спутник перезапустился — модели нет, и писать взгляд организатору не предлагается
02:42 +2983 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-01: после второй неудачи спутник перезапустился — модели нет, и писать взгляд организатору не предлагается
02:42 +2984 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-01: после второй неудачи спутник перезапустился — модели нет, и писать взгляд организатору не предлагается
02:42 +2985 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-01: после второй неудачи спутник перезапустился — модели нет, и писать взгляд организатору не предлагается
02:42 +2986 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-02: камера пропала во время изучения — спутник поднят заново и пишет в следующий сегмент той же моделью
02:43 +2987 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-02, SNO-F-EYE-06: изучение — лицо потерялось и вернулось, спутник поднят заново той же моделью; остановка — проверка в конце над экраном завершения, итог, спутник закрыт
02:43 +2988 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-06: организатор пропускает проверку в конце удержанием
02:43 +2988 ~27: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_satellite_test.dart: SNO-ALG-EYE-03: hello, камеры, общие часы и выход за две секунды
  Skip: нужна папка eye/ Windows (SNO_EYE_DIR) — идёт в CI на Windows
02:43 +2988 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-06: организатор пропускает проверку в конце удержанием
02:43 +2988 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_satellite_test.dart: SNO-F-EYE-05: самопроверка с кадрами камеры — на синтетике
  Skip: нужна папка eye/ Windows (SNO_EYE_DIR) — идёт в CI на Windows
02:43 +2988 ~29: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-06: организатор пропускает проверку в конце удержанием
02:43 +2988 ~29: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_satellite_test.dart: SNO-ALG-EYE-02, BUG-60: быстрая калибровка на синтетическом участнике — точки по QPC приложения, фаза движения головы, модель, проверка, проверка точности без новой калибровки, живая точка, файлы
  Skip: нужна папка eye/ Windows (SNO_EYE_DIR) — идёт в CI на Windows
02:43 +2988 ~30: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-06: организатор пропускает проверку в конце удержанием
02:43 +2988 ~30: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_satellite_test.dart: SNO-F-REC-04, SNO-F-EYE-02: поток взгляда на синтетическом участнике — строки по часам записи, перезапуск той же моделью в следующий сегмент, итоги сегментов
  Skip: нужна папка eye/ Windows (SNO_EYE_DIR) — идёт в CI на Windows
02:43 +2988 ~31: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-06: организатор пропускает проверку в конце удержанием
02:43 +2988 ~31: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_satellite_test.dart: SNO-F-EYE-01, SNO-F-EYE-02, SNO-F-EYE-06: запись с настоящим спутником на синтетическом участнике — калибровка внутри записи, изучение со взглядом, проверка в конце, файлы eye/ в архиве
  Skip: нужна папка eye/ Windows (SNO_EYE_DIR) — идёт в CI на Windows
02:43 +2988 ~32: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-06: организатор пропускает проверку в конце удержанием
02:43 +2988 ~32: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_satellite_test.dart: SNO-F-EYE-04: второй экземпляр отказывается словами
  Skip: нужна папка eye/ Windows (SNO_EYE_DIR) — идёт в CI на Windows
02:43 +2988 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-06: организатор пропускает проверку в конце удержанием
02:43 +2989 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-06: строка «Взгляд: …» экрана завершения
02:43 +2990 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: SNO-F-EYE-02: доля годного времени — по строкам потока
02:43 +2991 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: BUG-66: камера даёт 10 кадров — открыта заново, снова 10: до первой точки калибровки предупреждение; «Повторить» — 30, калибровка идёт
02:43 +2992 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: BUG-66: второй заход сам дал 30 кадров — предупреждения нет
02:43 +2993 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_recording_test.dart: BUG-66: камера так и не дала кадров — организатор удержанием выбирает «Без взгляда»
02:44 +2994 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_screens_test.dart: SNO-F-EYE-05: экран «Место записи» SNO-F-EYE-05: камера, монитор, карта, расстояние, самопроверка — и место сохранено само
02:44 +2995 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_screens_test.dart: SNO-F-EYE-05: экран «Место записи» SNO-F-EYE-05: камера, монитор, карта, расстояние, самопроверка — и место сохранено само
02:44 +2996 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_screens_test.dart: SNO-F-EYE-05: экран «Место записи» SNO-F-EYE-05: камера, монитор, карта, расстояние, самопроверка — и место сохранено само
02:44 +2997 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_screens_test.dart: SNO-F-EYE-05: экран «Место записи» SNO-F-EYE-05: камера, монитор, карта, расстояние, самопроверка — и место сохранено само
02:44 +2998 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_screens_test.dart: SNO-F-EYE-05: экран «Место записи» SNO-F-EYE-05: камера, монитор, карта, расстояние, самопроверка — и место сохранено само
02:44 +2999 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_screens_test.dart: SNO-F-EYE-05: экран «Место записи» SNO-F-EYE-05: камера, монитор, карта, расстояние, самопроверка — и место сохранено само
02:44 +3000 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_screens_test.dart: SNO-F-EYE-05: экран «Место записи» SNO-F-EYE-05: камера, монитор, карта, расстояние, самопроверка — и место сохранено само
02:44 +3001 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_screens_test.dart: SNO-F-EYE-05: экран «Место записи» SNO-F-EYE-05: камера, монитор, карта, расстояние, самопроверка — и место сохранено само
02:44 +3002 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_screens_test.dart: SNO-F-EYE-05: экран «Место записи» SNO-F-EYE-05: камера, монитор, карта, расстояние, самопроверка — и место сохранено само
02:44 +3003 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_screens_test.dart: SNO-F-EYE-05: экран «Место записи» SNO-F-EYE-05: камера, монитор, карта, расстояние, самопроверка — и место сохранено само
02:44 +3004 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_screens_test.dart: SNO-F-EYE-05: экран «Место записи» SNO-F-EYE-05: камера, монитор, карта, расстояние, самопроверка — и место сохранено само
02:45 +3005 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: быстро — 9 точек, живой взгляд поверх приложения, закрыть — спутник и окно отпущены
02:46 +3006 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: быстро — 9 точек, живой взгляд поверх приложения, закрыть — спутник и окно отпущены
02:46 +3007 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: быстро — 9 точек, живой взгляд поверх приложения, закрыть — спутник и окно отпущены
02:46 +3008 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: быстро — 9 точек, живой взгляд поверх приложения, закрыть — спутник и окно отпущены
02:46 +3009 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_screens_test.dart: SNO-F-EYE-05: экран «Место записи» SNO-F-EYE-05: камера запрещена — словами и кнопкой параметров
02:47 +3010 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: «Ещё раз» из живого взгляда — новая быстрая калибровка
02:47 +3011 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: «Ещё раз» из живого взгляда — новая быстрая калибровка
02:47 +3012 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_screens_test.dart: SNO-F-EYE-05: экран «Место записи» SNO-F-EYE-05: спутник не запустился — сказано, можно ещё раз
02:47 +3013 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-01: пробная полная калибровка — 13 точек, слежение, 9 точек проверки, итог, две минуты просмотра, файлы стенда
02:47 +3014 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-01: пробная полная калибровка — 13 точек, слежение, 9 точек проверки, итог, две минуты просмотра, файлы стенда
02:48 +3015 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-01: пробная полная калибровка — 13 точек, слежение, 9 точек проверки, итог, две минуты просмотра, файлы стенда
02:48 +3016 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-01: пробная полная калибровка — 13 точек, слежение, 9 точек проверки, итог, две минуты просмотра, файлы стенда
02:48 +3017 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-01: пробная полная калибровка — 13 точек, слежение, 9 точек проверки, итог, две минуты просмотра, файлы стенда
02:48 +3018 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_screens_test.dart: SNO-F-EYE-05: строка в «Тестировании» и старт записи SNO-F-EYE-05: место задано — его строка, без предупреждения
02:48 +3019 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-01: не принято — повтор до трёх попыток, потом «не принято» и живой взгляд по желанию
02:49 +3020 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-ALG-EYE-02: точка без кадров повторяется в конце; лица нет — словами и без отсчёта попытки
02:49 +3021 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-01: окно сменилось посреди калибровки — камера заново и та же попытка; Esc закрывает проверку
02:49 +3022 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: самопроверка «не годится» — сказано, калибровки нет
02:49 +3023 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: самопроверка «не годится» — сказано, калибровки нет
02:49 +3024 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: самопроверка «не годится» — сказано, калибровки нет
02:49 +3025 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: самопроверка «не годится» — сказано, калибровки нет
02:49 +3026 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: самопроверка «не годится» — сказано, калибровки нет
02:49 +3027 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: самопроверка «не годится» — сказано, калибровки нет
02:49 +3028 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: самопроверка «не годится» — сказано, калибровки нет
02:49 +3029 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: самопроверка «не годится» — сказано, калибровки нет
02:49 +3030 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: самопроверка «не годится» — сказано, калибровки нет
02:49 +3031 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: самопроверка «не годится» — сказано, калибровки нет
02:49 +3032 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: самопроверка «не годится» — сказано, калибровки нет
02:49 +3033 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: самопроверка «не годится» — сказано, калибровки нет
02:49 +3034 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: SNO-F-EYE-03: самопроверка «не годится» — сказано, калибровки нет
02:49 +3035 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: BUG-60: «Проверить точность» из живого взгляда — экран проверки, девять точек, итог и способы в панели, снова живой взгляд
02:49 +3036 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: BUG-60: лица мало в фазе движения головы — фаза повторяется один раз, потом калибровка идёт без неё
02:49 +3037 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: BUG-61: подсказка под точкой; голова не пошла — крупнее через 5 с, через 10 с фаза кончается без движения головы
02:50 +3038 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: BUG-61: голова дальше пределов — «Не так сильно», кольцо стоит; вернулась — набирается, вторая ось — вверх-вниз
02:50 +3039 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: BUG-61: голова дальше пределов — «Не так сильно», кольцо стоит; вернулась — набирается, вторая ось — вверх-вниз
02:50 +3040 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: BUG-61: голова дальше пределов — «Не так сильно», кольцо стоит; вернулась — набирается, вторая ось — вверх-вниз
02:50 +3041 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: BUG-61: голова дальше пределов — «Не так сильно», кольцо стоит; вернулась — набирается, вторая ось — вверх-вниз
02:50 +3042 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_trial_test.dart: BUG-61: голова дальше пределов — «Не так сильно», кольцо стоит; вернулась — набирается, вторая ось — вверх-вниз
02:50 +3043 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: второй экземпляр — already_running
02:50 +3044 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: второй экземпляр — already_running
02:50 +3045 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-ALG-EYE-03: спутник вышел — ожидающие узнают сразу
02:50 +3046 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-ALG-EYE-03: ответа нет — timeout, а запоздавший не чужой
02:50 +3047 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-ALG-EYE-03: сердцебиение, ход и мусор — своим слушателям
02:50 +3048 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-ALG-EYE-04: самопроверка — камера, кадры и итог
02:50 +3049 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-ALG-EYE-03: рукопожатие находит сдвиг часов спутника
02:50 +3050 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: не запустился — EyeError от запуска
02:50 +3051 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:51 +3052 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:51 +3053 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:51 +3054 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:51 +3055 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:51 +3056 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:51 +3057 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:51 +3058 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:51 +3059 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:51 +3060 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3061 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3062 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3063 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3064 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3065 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3066 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
Shell: ЗАМЕР ALG-MAP-18 | 1200 страниц | паспорт | 22 мс
02:52 +3067 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3068 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3068 ~33: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf/pdfium_passport_test.dart: ALG-MAP-18: 18 книг литературы СНО2026 — электронные оригиналы
  Skip: нет литературы СНО2026 рядом с репозиторием (_данные) — тест идёт только на ПК владельца
02:52 +3068 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3069 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3070 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3071 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3072 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3073 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3074 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3075 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3076 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:52 +3077 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/eye/eye_link_test.dart: SNO-F-EYE-04: спутник не закрылся сам — снят
02:53 +3078 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: Hlc строка разбирается обратно без потерь
02:53 +3079 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: Hlc счётчик записан четырьмя hex-знаками
02:53 +3080 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: Hlc время пишется в UTC
02:53 +3081 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: Hlc мусор не принимается за метку
02:53 +3082 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: Hlc порядок: сначала время, потом счётчик, потом узел
02:53 +3083 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: Hlc часы стоят — растёт счётчик
02:53 +3084 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: Hlc часы ушли назад — метка всё равно растёт
02:53 +3085 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: Hlc часы ушли вперёд — счётчик обнуляется
02:53 +3086 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: Hlc приём метки из будущего подтягивает часы
02:53 +3087 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: Hlc приём метки той же миллисекунды берёт больший счётчик
02:53 +3088 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: Hlc переполнение счётчика — ошибка, а не тихая порча меток
02:53 +3089 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: HlcClock метки строго растут при стоящих часах
02:53 +3090 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: HlcClock часы продолжают прошлый запуск, а не начинают заново
02:53 +3091 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: HlcClock о каждой выданной метке сообщается наружу
02:53 +3092 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: generateNodeId 32 шестнадцатеричных знака без разделителей
02:53 +3093 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/domain/hlc_test.dart: generateNodeId идентификатор попадает в метку и читается обратно
02:53 +3094 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/pdfium_version_test.dart: версия PDFium у нас и в хуке pdfium_dart совпадает
02:53 +3095 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/build_lock_test.dart: замок зависимостей pubspec.lock отслеживается git
02:53 +3096 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/build_lock_test.dart: замок зависимостей в замке есть движок с точной версией
02:53 +3097 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/build_lock_test.dart: версия Flutter записана в одном месте у композитного действия версия точная
02:53 +3098 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/build_lock_test.dart: версия Flutter записана в одном месте напрямую ставит Flutter только канарейка
02:54 +3099 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/build_lock_test.dart: версия Flutter записана в одном месте версия в действии — не канал
02:54 +3100 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/build_lock_test.dart: CI не обновляет замок молча каждый pub get идёт с --enforce-lockfile
02:54 +3101 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3102 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3103 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3104 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3105 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3106 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3107 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3108 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3109 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3110 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3111 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3112 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3113 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3114 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3115 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3116 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3117 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3118 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3119 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3120 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3121 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3122 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3123 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3124 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3125 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3126 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3127 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3128 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3129 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3130 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3131 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3132 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3133 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3134 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3135 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3136 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3137 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3138 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3139 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3140 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3141 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3142 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3143 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3144 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3145 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3146 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3147 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3148 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3149 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3150 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3151 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:55 +3152 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: читательская рамка на корпусе broken_xref.pdf: рамка не пустая и не вывернутая
02:55 +3153 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: по умолчанию включена тёмно-красная тема
02:55 +3154 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: по умолчанию включена тёмно-красная тема
02:55 +3155 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: по умолчанию включена тёмно-красная тема
02:55 +3156 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: по умолчанию включена тёмно-красная тема
02:55 +3157 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: по умолчанию включена тёмно-красная тема
02:55 +3158 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: по умолчанию включена тёмно-красная тема
02:55 +3159 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: по умолчанию включена тёмно-красная тема
02:55 +3160 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: по умолчанию включена тёмно-красная тема
02:55 +3161 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: по умолчанию включена тёмно-красная тема
02:55 +3162 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: по умолчанию включена тёмно-красная тема
02:55 +3163 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: читательская рамка на корпусе mixed_page_sizes.pdf: включённое деление не делает текст мельче
02:55 +3164 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:55 +3165 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:55 +3166 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:55 +3167 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:55 +3168 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:55 +3169 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:55 +3170 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:55 +3171 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:55 +3172 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:55 +3173 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:55 +3174 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3175 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3176 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3177 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3178 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3179 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3180 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3181 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3182 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3183 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3184 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3185 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3186 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3187 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3188 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3189 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3190 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3191 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3192 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3193 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3194 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3195 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3196 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3197 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3198 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3199 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3200 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3201 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3202 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:56 +3203 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: чтение по файловому дескриптору huge_1200_pages.pdf читается так же, как по пути
02:56 +3204 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: на пустой полке предложено добавить книги
02:56 +3205 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: на пустой полке предложено добавить книги
02:56 +3206 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: на пустой полке предложено добавить книги
02:56 +3207 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: на пустой полке предложено добавить книги
02:56 +3208 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: на пустой полке предложено добавить книги
02:56 +3209 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: на пустой полке предложено добавить книги
02:56 +3210 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: на пустой полке предложено добавить книги
02:56 +3211 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: на пустой полке предложено добавить книги
02:56 +3212 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: на пустой полке предложено добавить книги
02:56 +3213 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-02: книга открывается, не измеряя все страницы F-READ-02: поиск по всей книге видит все страницы
02:57 +3214 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-02: книга открывается, не измеряя все страницы F-READ-02: измерить всё при открытии по-прежнему можно
02:57 +3215 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-02: замеры скорости F-READ-02: huge_1200_pages.pdf — открытие и первая рамка
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | открытие книги | было 13.8 мс | стало 2.0 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | открытие и рамка страницы 600 | было 12.7 мс | стало 4.9 мс
02:57 +3216 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-02: замеры скорости F-READ-02: huge_1200_pages.pdf — переход на соседнюю страницу
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | переход на соседнюю страницу | было 0.2 мс | стало 0.2 мс
02:58 +3217 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-02: замеры скорости F-READ-02: book_120_pages.pdf — открытие и первая рамка
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | открытие книги | было 17.9 мс | стало 1.5 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | открытие и рамка страницы 60 | было 20.5 мс | стало 7.2 мс
02:58 +3218 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-02: замеры скорости F-READ-02: book_120_pages.pdf — переход на соседнюю страницу
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | переход на соседнюю страницу | было 2.8 мс | стало 0.2 мс
02:59 +3219 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-02: замеры скорости F-READ-02: scan_no_text.pdf — открытие и первая рамка
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | открытие книги | было 0.9 мс | стало 0.9 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | открытие и рамка страницы 1 | было 6.7 мс | стало 7.6 мс
02:59 +3220 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-02: замеры скорости F-READ-02: scan_no_text.pdf — переход на соседнюю страницу
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | переход на соседнюю страницу | было 5.5 мс | стало 0.2 мс
02:59 +3221 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-02: замеры скорости F-READ-02: дальний переход не ждёт рамку дольше срока
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | переход на непосчитанную страницу | было 5.6 мс | стало 6.3 мс
02:59 +3222 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-02: замеры скорости F-READ-02: сколько стоит измерить всю книгу
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | измерить все страницы | 13.2 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | измерить все страницы | 16.6 мс
02:59 +3223 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-15: рамка обрезки на книгу F-READ-15: basic_text.pdf — ни один символ не срезан
02:59 +3224 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-15: рамка обрезки на книгу F-READ-15: outline_nested.pdf — ни один символ не срезан
02:59 +3225 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-15: рамка обрезки на книгу F-READ-15: two_columns.pdf — ни один символ не срезан
02:59 +3226 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-15: рамка обрезки на книгу F-READ-15: cjk.pdf — ни один символ не срезан
02:59 +3227 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-15: рамка обрезки на книгу F-READ-15: rtl.pdf — ни один символ не срезан
02:59 +3228 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-15: рамка обрезки на книгу F-READ-15: rotated_pages.pdf — ни один символ не срезан
02:59 +3229 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-15: рамка обрезки на книгу F-READ-15: mixed_page_sizes.pdf — ни один символ не срезан
02:59 +3230 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-15: рамка обрезки на книгу F-READ-15: broken_xref.pdf — ни один символ не срезан
02:59 +3231 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-15: рамка обрезки на книгу F-READ-15: book_120_pages.pdf — ни один символ не срезан
03:00 +3232 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-15: рамка обрезки на книгу F-READ-15: у книги из переплёта ширина текста одна
Shell: ЗАМЕР F-READ-15 | book_120_pages.pdf | разных ширин рамки | было 10 | стало 1 | страниц с расширенной рамкой 2 из 120
03:00 +3233 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-15: рамка обрезки на книгу F-READ-15: выборка дешевле постраничного расчёта
Shell: ЗАМЕР F-READ-15 | book_120_pages.pdf | рамка: вся книга постранично против выборки из 16 страниц | было 365.7 мс | стало 61.4 мс
03:01 +3234 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-READ-15: рамка обрезки на книгу F-READ-15: скан — рамка книги считается по пикселям
03:01 +3235 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-TEXT-04: текст книги в кэше F-TEXT-04: поиск по кэшу совпадает с поиском по документу
03:04 +3236 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-TEXT-04: текст книги в кэше F-TEXT-04: текст из кэша — тот же, что отдаёт движок
03:05 +3237 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-TEXT-04: текст книги в кэше F-TEXT-04: второй поиск по книге идёт без движка
03:05 +3238 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-TEXT-04: текст книги в кэше F-TEXT-04: скан — кэш пустой, и это не ошибка
03:05 +3239 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-TEXT-04: текст книги в кэше F-TEXT-04: закрытая книга в кэш пустотой не ложится
03:05 +3240 ~34: /home/runner/work/MemoriaLLM/MemoriaLLM/test/pdf_corpus_test.dart: F-TEXT-04: текст книги в кэше F-TEXT-04: замеры — вес текста, проход, поиск
Shell: ЗАМЕР F-TEXT-04 | book_120_pages.pdf | страниц 120 | текста 337988 знаков | проход 166.5 мс | первый поиск 203.2 мс | второй поиск 19.8 мс
Shell: ЗАМЕР F-TEXT-04 | huge_1200_pages.pdf | страниц 1200 | текста 16800 знаков | проход 166.2 мс | первый поиск 205.5 мс | второй поиск 15.3 мс
Shell: ЗАМЕР F-TEXT-04 | scan_no_text.pdf | страниц 2 | текста 0 знаков | проход 0.5 мс | первый поиск 1.4 мс | второй поиск 0.0 мс
03:06 +3241 ~34: All tests passed!
```

## sno
```
aLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-05: пока тест не пройден, сессию не завершить; пройден — кнопка появилась
00:40 +677 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/shelf_search_test.dart: SNO-F-LIB-01: поиск по названию на широком окне SNO-F-LIB-01: окно сузили — поле и найденное на месте
00:40 +678 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-03: начатый тест экран предлагает продолжить — без пароля, без вступления, с того же пункта
00:41 +679 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-03: начатый тест экран предлагает продолжить — без пароля, без вступления, с того же пункта
00:41 +680 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-03: начатый тест экран предлагает продолжить — без пароля, без вступления, с того же пункта
00:41 +681 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-03: начатый тест экран предлагает продолжить — без пароля, без вступления, с того же пункта
00:41 +682 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-03: начатый тест экран предлагает продолжить — без пароля, без вступления, с того же пункта
00:41 +683 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-03: начатый тест экран предлагает продолжить — без пароля, без вступления, с того же пункта
00:41 +684 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-03: начатый тест экран предлагает продолжить — без пароля, без вступления, с того же пункта
00:41 +685 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-03: начатый тест экран предлагает продолжить — без пароля, без вступления, с того же пункта
00:41 +686 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-03: начатый тест экран предлагает продолжить — без пароля, без вступления, с того же пункта
00:41 +687 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-03: начатый тест экран предлагает продолжить — без пароля, без вступления, с того же пункта
00:41 +688 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-03: начатый тест экран предлагает продолжить — без пароля, без вступления, с того же пункта
00:41 +689 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-03: начатый тест экран предлагает продолжить — без пароля, без вступления, с того же пункта
00:41 +690 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/shelf_search_test.dart: SNO-F-READ-02: полка передаёт чтению, есть ли лента SNO-F-READ-02: с лентой — как прежде
00:41 +691 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-05: тест пройти нельзя — выход организатора: пароль, удержание, подтверждение
00:41 +692 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-05: тест пройти нельзя — выход организатора: пароль, удержание, подтверждение
00:41 +693 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-05: тест пройти нельзя — выход организатора: пароль, удержание, подтверждение
00:42 +694 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-05: сценарий не принят — тест недоступен, остаётся выход организатора
00:42 +695 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-05: пароль сборки с экрана не набрать — выход организатора пароля не спрашивает
00:42 +696 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-05: тест на экране завершения сессии SNO-F-CLT-05: без теста в сборке сессия завершается сразу
00:42 +697 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-01: пункт теста в разделе «Тестирование» SNO-F-CLT-01: в сборке без пароля теста пункта нет вовсе
00:42 +698 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: «Галактика» стоит между «Полкой» и «Тестированием»
00:42 +699 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: «Галактика» стоит между «Полкой» и «Тестированием»
00:43 +700 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: «Галактика» стоит между «Полкой» и «Тестированием»
00:43 +701 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/clt_screens_test.dart: SNO-F-CLT-03: ответ не лёг на диск SNO-F-CLT-03: экран говорит об этом, а последний ответ не даёт «Спасибо», пока не записан
00:44 +702 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: на широком окне раздел — в верхней полосе
00:44 +703 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: раздел показывает книги полки картой
00:44 +704 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: книга, открытая с карты, останавливает подготовку книг и считает своё время
00:44 +705 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: книга, открытая с карты, останавливает подготовку книг и считает своё время
00:44 +706 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: книга, открытая с карты, останавливает подготовку книг и считает своё время
00:44 +707 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: книга, открытая с карты, останавливает подготовку книг и считает своё время
00:44 +708 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: книга, открытая с карты, останавливает подготовку книг и считает своё время
00:44 +709 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: книга, открытая с карты, останавливает подготовку книг и считает своё время
00:44 +710 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: книга, открытая с карты, останавливает подготовку книг и считает своё время
00:44 +711 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: книга, открытая с карты, останавливает подготовку книг и считает своё время
00:44 +712 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: книга, открытая с карты, останавливает подготовку книг и считает своё время
00:44 +713 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: книга, открытая с карты, останавливает подготовку книг и считает своё время
00:44 +714 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: книга, открытая с карты, останавливает подготовку книг и считает своё время
00:45 +715 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь II SNO-F-MAP-01: «назад» из раздела ведёт на «Полку»
00:45 +716 ~1: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/galaxy_section_test.dart: SNO-F-MAP-01: ветвь I SNO-F-MAP-01: раздела «Галактика» в ней нет
  Skip: прогон ветви II: проверяется прогоном ветви I (--dart-define=SNO_BRANCH=I)
00:45 +716 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_layer_test.dart: SNO-F-REC-03: слой есть только во время записи SNO-F-REC-03: записи нет — слой не слушает кадры, и кадров нет
00:46 +717 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_layer_test.dart: SNO-F-REC-03: слой есть только во время записи SNO-F-REC-03: слой заводит старт записи и снимает её остановка
00:46 +718 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/hold_button_test.dart: SNO-F-CFG-04: додержали — сработала, и ровно один раз
00:46 +719 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/hold_button_test.dart: SNO-F-CFG-04: додержали — сработала, и ровно один раз
00:46 +720 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/hold_button_test.dart: SNO-F-CFG-04: додержали — сработала, и ровно один раз
00:46 +721 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/hold_button_test.dart: SNO-F-CFG-04: додержали — сработала, и ровно один раз
00:46 +722 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/hold_button_test.dart: SNO-F-CFG-04: додержали — сработала, и ровно один раз
00:47 +723 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/hold_button_test.dart: SNO-F-CFG-04: додержали — сработала, и ровно один раз
00:47 +724 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/hold_button_test.dart: SNO-F-CFG-04: додержали — сработала, и ровно один раз
00:47 +725 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/hold_button_test.dart: SNO-F-CFG-04: додержали — сработала, и ровно один раз
00:47 +726 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/hold_button_test.dart: SNO-F-CFG-04: додержали — сработала, и ровно один раз
00:47 +727 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/hold_button_test.dart: SNO-F-CFG-04: короткое нажатие ничего не делает
00:47 +728 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/hold_button_test.dart: SNO-F-CFG-04: отпустили раньше — счёт начинается заново
00:47 +729 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/hold_button_test.dart: SNO-F-CFG-04: палец повёл список — это не удержание
00:47 +730 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/hold_button_test.dart: SNO-F-CFG-04: пока держат, кнопка заполняется
00:47 +731 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/hold_button_test.dart: SNO-F-CFG-04: выключенная кнопка не заполняется
00:48 +732 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: нашёл книгу поиском, открыл, полистал, закрыл — всё в журнале по порядку
00:48 +733 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: нашёл книгу поиском, открыл, полистал, закрыл — всё в журнале по порядку
00:48 +734 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: нашёл книгу поиском, открыл, полистал, закрыл — всё в журнале по порядку
00:48 +735 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: нашёл книгу поиском, открыл, полистал, закрыл — всё в журнале по порядку
00:48 +736 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: нашёл книгу поиском, открыл, полистал, закрыл — всё в журнале по порядку
00:48 +737 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: нашёл книгу поиском, открыл, полистал, закрыл — всё в журнале по порядку
00:48 +738 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: нашёл книгу поиском, открыл, полистал, закрыл — всё в журнале по порядку
00:48 +739 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: нашёл книгу поиском, открыл, полистал, закрыл — всё в журнале по порядку
00:48 +740 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: нашёл книгу поиском, открыл, полистал, закрыл — всё в журнале по порядку
00:48 +741 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: нашёл книгу поиском, открыл, полистал, закрыл — всё в журнале по порядку
00:49 +742 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: нашёл книгу поиском, открыл, полистал, закрыл — всё в журнале по порядку
00:49 +743 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: нашёл книгу поиском, открыл, полистал, закрыл — всё в журнале по порядку
00:49 +744 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: нашёл книгу поиском, открыл, полистал, закрыл — всё в журнале по порядку
00:50 +745 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/shelf_reading_view_test.dart: SNO-F-IDX-04: экраны SNO-F-IDX-04: непрочитанные книги — и кнопка «Прочитать книги»
00:50 +746 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: книга с полки напрямую — путь `shelf`, второе обращение — номером
00:50 +747 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: книга с полки напрямую — путь `shelf`, второе обращение — номером
00:50 +748 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: запись не идёт — полка и книга работают, журнал пуст
00:50 +749 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: ушёл, не дождавшись книги, — открытой после своего закрытия она в журнале не станет
00:50 +750 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: полка и книга SNO-F-REC-02: запрос, набранный по буквам с паузами в треть секунды, — одно событие
00:51 +751 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:51 +752 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:51 +753 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:51 +754 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:52 +755 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:52 +756 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:52 +757 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:52 +758 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:52 +759 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:53 +760 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:54 +761 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:54 +762 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:54 +763 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:54 +764 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:54 +765 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:54 +766 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:54 +767 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:54 +768 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:54 +769 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:54 +770 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:55 +771 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:55 +772 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:55 +773 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:55 +774 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:55 +775 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:55 +776 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:55 +777 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:55 +778 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:55 +779 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:55 +780 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:55 +781 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:55 +782 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:55 +783 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-05: архив уже лежит, а папка — другая SNO-F-REC-05: сведения о записи в папке новее, чем в архиве, — папка упаковывается заново
00:55 +784 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-05: архив уже лежит, а папка — другая SNO-F-REC-05: сведения о записи в папке новее, чем в архиве, — папка упаковывается заново
00:55 +785 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-05: архив уже лежит, а папка — другая SNO-F-REC-05: архив без сведений не даёт убрать папку, в которой сведения есть
00:55 +786 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-05: запись не теряется при упаковке SNO-F-REC-05: архив не сошёлся с записью — папка цела, обрывка нет
00:55 +787 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-05: запись не теряется при упаковке SNO-F-REC-05: в архиве подменён один байт журнала — сверка ловит
00:55 +788 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-05: запись не теряется при упаковке SNO-F-REC-05: после неудачи упаковка повторяется и удаётся
00:55 +789 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-05: запись не теряется при упаковке SNO-F-REC-05: приложение закрыли между архивом и уборкой папки — следующая упаковка убирает папку
00:55 +790 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-05: запись не теряется при упаковке SNO-F-REC-05: обрывок прежней упаковки не мешает новой
00:56 +791 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-05: запись не теряется при упаковке SNO-F-REC-05: папка изменилась, пока её упаковывали, — она остаётся, архива нет
00:56 +792 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-05: запись не теряется при упаковке SNO-F-REC-05: в папке появился новый файл, пока её упаковывали, — она остаётся
00:56 +793 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-05: запись не теряется при упаковке SNO-F-REC-05: упакованная папка убирается целиком, скрытых остатков нет
00:56 +794 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-05: запись не теряется при упаковке SNO-ALG-REC-03: в папке нет файлов — отказ, а не пустой архив
00:56 +795 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-07: сверка архива на диске SNO-F-REC-07: целый архив — манифест и суммы сходятся
00:56 +796 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-07: сверка архива на диске SNO-F-REC-07: не архив — манифеста нет
00:56 +797 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-07: сверка архива на диске SNO-F-REC-07: архива нет — ответ, а не ошибка
00:56 +798 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-07: сверка архива на диске SNO-F-REC-07: сумма не сходится — манифест читается, архив помечен
00:56 +799 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-07: сверка архива на диске SNO-F-REC-07: файла из перечня в архиве нет — архив помечен
00:56 +800 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-07: сверка архива на диске SNO-F-REC-07: заголовок записи расходится с оглавлением — архив помечен
00:56 +801 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-07: сверка архива на диске SNO-F-REC-07: архив с пустым перечнем файлов целым не считается
00:56 +802 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_archive_test.dart: SNO-F-REC-07: сверка архива на диске SNO-F-REC-07: архив без манифеста — повреждён
00:56 +803 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: вид касания SNO-ALG-REC-07: коротко и на месте — tap, одна строка на касание
00:56 +804 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: вид касания SNO-ALG-REC-07: держали на месте дольше порога — long
00:56 +805 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: вид касания SNO-ALG-REC-07: ушло дальше порога — drag, и порог у мыши меньше, чем у пальца
00:56 +806 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: вид касания SNO-ALG-REC-07: вернулся к месту касания — всё равно drag: считается наибольшее удаление
00:56 +807 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: вид касания SNO-ALG-REC-07: два пальца — у каждого своя строка, вид multi и общая группа
00:56 +808 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: вид касания SNO-ALG-REC-07: жест забрала система — cancel
00:56 +809 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: вид касания SNO-ALG-REC-07: запись остановилась при опущенном пальце — строка с пометкой cut
00:56 +810 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: вид касания SNO-ALG-REC-07: чужое отпускание и движение без касания строк не дают
00:56 +811 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: вид касания SNO-ALG-REC-07: касание точки записи помечено — в карты участника оно не идёт
00:56 +812 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: след касания SNO-ALG-REC-07: точка следа — не чаще раза в 50 мс, и последняя обязательно
00:56 +813 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: след касания SNO-ALG-REC-07: у нажатия на месте следа нет
00:56 +814 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: след касания SNO-ALG-REC-07: след длиннее предела не растёт, а последняя точка — настоящая
00:56 +815 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: колесо, клавиши, путь мыши SNO-ALG-REC-07: щелчки колеса подряд — одна строка с суммой, после тишины — новая
00:56 +816 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: колесо, клавиши, путь мыши SNO-ALG-REC-07: клавиша пишется, когда отпущена; автоповтор — счётом, а не строками
00:56 +817 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: колесо, клавиши, путь мыши SNO-ALG-REC-07: две клавиши внахлёст — две строки, каждая со своим номером
00:56 +818 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: колесо, клавиши, путь мыши SNO-ALG-REC-07: клавишу держат, а запись остановили — строка с пометкой cut
00:56 +819 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: колесо, клавиши, путь мыши SNO-ALG-REC-07: путь мыши без нажатия — не чаще десяти точек в секунду, пачкой раз в секунду
00:56 +820 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: колесо, клавиши, путь мыши SNO-ALG-REC-07: мышь, которая стоит, пути не даёт
00:56 +821 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: связь с действием SNO-ALG-REC-07: пока палец на экране — ссылка на его касание
00:56 +822 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: связь с действием SNO-ALG-REC-07: после отпускания — в окне 400 мс; событие снаружи ссылки не получает
00:56 +823 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: связь с действием SNO-ALG-REC-07: новое касание перекрывает прежнее
00:56 +824 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: связь с действием SNO-ALG-REC-07: клавиша и колесо тоже дают ссылку — от нажатия и от последнего щелчка
00:56 +825 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-ALG-REC-07: связь с действием SNO-ALG-REC-07: после остановки ссылок нет
00:56 +826 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/input_tap_test.dart: SNO-F-REC-11: размер потока SNO-F-REC-11: три тысячи касаний и путь мыши за сорок минут — не больше трёх мегабайт
ЗАМЕР: поток ввода за 40 минут — 1117 КБ, строк 5381, касаний 3000
00:57 +827 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/shelf_reading_log_test.dart: SNO-F-IDX-04: смена дела и каждая прочитанная книга — строкой, страницы — нет
00:57 +828 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/shelf_reading_log_test.dart: SNO-F-IDX-04: расчёт карты и итог — с отпечатком карты
00:57 +829 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/shelf_reading_log_test.dart: SNO-F-IDX-04: подготовке нечего было делать — журнал молчит
00:57 +830 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/shelf_reading_log_test.dart: SNO-F-IDX-04: запись не идёт — строк нет; началась посреди подготовки — первая же строка говорит, где та стоит
00:57 +831 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/shelf_reading_log_test.dart: SNO-F-IDX-04: перестали слушать — строк больше нет
00:57 +832 ~2: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01: основная сборка SNO-F-CFG-01: раздела «Тестирование» в ней нет
  Skip: прогон ветви: проверяется основным прогоном
00:57 +832 ~3: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01: основная сборка SNO-F-LIB-01: поиска по полке в ней нет, модель есть
  Skip: прогон ветви: проверяется основным прогоном
00:57 +832 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01: основная сборка SNO-F-CFG-01: строка сборки — без ветви и флагов
  Skip: прогон ветви: проверяется основным прогоном
00:57 +832 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01…03: сборка ветви SNO-F-CFG-03: разделы — «Полка · Тестирование · Настройки»
00:58 +833 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01…03: сборка ветви SNO-F-CFG-03: разделы — «Полка · Тестирование · Настройки»
00:58 +834 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01…03: сборка ветви SNO-F-CFG-03: разделы — «Полка · Тестирование · Настройки»
00:58 +835 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01…03: сборка ветви SNO-F-CFG-03: разделы — «Полка · Тестирование · Настройки»
00:58 +836 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01…03: сборка ветви SNO-F-CFG-03: разделы — «Полка · Тестирование · Настройки»
00:58 +837 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: «Тестирование» на сборке исследования SNO-F-CFG-06: проверочная сборка сказана над стартом
00:59 +838 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: «Тестирование» на сборке исследования SNO-F-CFG-06: проверочная сборка сказана над стартом
00:59 +839 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01…03: сборка ветви SNO-F-CFG-02: книг устройства не ищут, доступ не просят
00:59 +840 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01…03: сборка ветви SNO-F-CFG-02: книг устройства не ищут, доступ не просят
00:59 +841 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01…03: сборка ветви SNO-F-CFG-02: с полки на «Устройство» не уйти
00:59 +842 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01…03: сборка ветви SNO-F-LIT-02: свой PDF из «Тестирования» на полку не встаёт
01:00 +843 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01…03: сборка ветви SNO-F-LIT-03: архивы устройства видны в «Тестировании»
01:00 +844 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: зона за краем прокрутки SNO-F-REC-03: строки запаса прокрутки в кадр не попадают, подрезанная краем — видимой частью и с пометкой
01:00 +845 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: зона за краем прокрутки SNO-F-REC-03: строки запаса прокрутки в кадр не попадают, подрезанная краем — видимой частью и с пометкой
01:01 +846 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01…03: сборка ветви SNO-F-CFG-04: сброс возвращает тему и порядок полки
01:01 +847 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01…03: сборка ветви SNO-F-CFG-04: сброс возвращает тему и порядок полки
01:01 +848 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: в кадре полка со сдвигом прокрутки, шапки и участки категорий с названием, книги с отпечатком и категорией
01:01 +849 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01…03: сборка ветви SNO-F-CFG-03: «назад» из «Тестирования» ведёт на полку
01:02 +850 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: полку прокрутили — сдвиг в кадре тот же, что у списка, книги уехали вместе с ним
01:02 +851 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01…03: сборка ветви SNO-F-LIB-01: на полке ветви есть поиск по названию
01:02 +852 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: касание книги лежит по кадру в зоне этой книги — той, что её открыла
01:02 +853 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_app_test.dart: SNO-F-CFG-01…03: сборка ветви SNO-F-LIB-01: на широком окне поле — в шапке полки
01:02 +854 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:02 +855 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:03 +856 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: карта «Галактика» SNO-F-REC-03: в кадре — раздел, полотно с камерой и всеми видимыми звёздами на их местах
01:03 +857 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: карта «Галактика» SNO-F-REC-03: касание звезды — по кадру её отпечаток; открытая карточка — зона поверх карты
01:03 +858 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: карта «Галактика» SNO-F-REC-03: перенос приближенной карты — кадры «в движении» и один устоявшийся с новой камерой
01:03 +859 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
01:04 +860 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: блок «Для экспериментатора» свёрнут
01:04 +861 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-01: «О ветви» называет ветвь и её флаги
01:04 +862 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: пунктов-заглушек в разделе нет
01:04 +863 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: пока блок свёрнут, устройство не обходится
01:05 +864 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: найденные архивы стоят списком, новые сверху
01:05 +865 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: архив из списка уходит в ту же распаковку
01:05 +866 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: архивов нет — сказано словами
01:05 +867 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: пока идёт обход, найденное уже в списке
01:05 +868 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: нажатие достаётся архиву, а не месту в списке
01:05 +869 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: начатый раньше поиск новому не мешает
01:05 +870 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: «Искать заново» останавливает прежний обход
01:05 +871 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: раздел закрыли — обход остановлен
01:05 +872 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: «Искать заново» обходит устройство ещё раз
01:06 +873 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: оборванный обход назван, найденное остаётся
01:06 +874 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: на ПК доступ не нужен и не просится
01:06 +875 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: без доступа обхода нет, запрос — по кнопке
01:06 +876 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: отказали — запрос сам не повторяется
01:06 +877 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: вернулись в приложение — обход не повторён
01:06 +878 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: PDF вместо архива на полку не встаёт
01:06 +879 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: PDF и архив вместе — встаёт только архив
01:06 +880 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: кнопка и подписи книг не обещают
01:06 +881 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: книга узнаётся по имени файла
01:06 +882 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: отказ называет книги и говорит, как надо
01:06 +883 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: поимённо названы три книги, остальные числом
01:06 +884 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: архив распаковывается, итог — окном
01:06 +885 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: диалог закрыли — ничего не случилось
01:06 +886 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
01:07 +887 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: пока архив открывается, это и сказано
01:07 +888 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: второе нажатие второй диалог не открывает
01:07 +889 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: сбой распаковки итога не съедает
01:07 +890 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: не-архив получает отказ от распаковки
01:07 +891 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: два архива — итог у каждого свой
01:07 +892 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: эталона нет — сказано, кнопки сброса нет
01:07 +893 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: разложенный архив запоминается эталоном
01:07 +894 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: удержание сбрасывает к эталону
01:07 +895 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс BUG-67: «Забыть эталон» удержанием — эталона нет, архив запомнится новым
01:08 +896 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: отпустили раньше — ничего не произошло
01:08 +897 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: пока идёт распаковка, сброс выключен
01:08 +898 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: вернулись в раздел — сверка заново
01:08 +899 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: отказанный архив эталоном не становится
01:08 +900 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: книги и категории сосчитаны
01:08 +901 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: без папок категорий нет и в словах
01:08 +902 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: тот же архив ещё раз
01:08 +903 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: часть была, часть встала, часть не открылась
01:08 +904 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: отказ архива и остановка названы
01:08 +905 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: причина движка сказана своими словами
01:08 +906 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: код устройства SNO-F-CFG-03: первые шесть знаков идентификатора узла
01:08 +907 ~5: All tests passed!
```

## eye-tests
```
........................................................................ [  9%]
........................................................................ [ 19%]
........................................................................ [ 28%]
........................................................................ [ 38%]
........................................................................ [ 48%]
........................................................................ [ 57%]
........................................................................ [ 67%]
........................................................................ [ 77%]
........................................................................ [ 86%]
........................................................................ [ 96%]
..........................                                               [100%]
746 passed in 857.22s (0:14:17)
```

## eye-windows
```
Collecting absl-py==2.5.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 4))
  Downloading absl_py-2.5.0-py3-none-any.whl (137 kB)
Collecting av==19.0.1 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 6))
  Downloading av-19.0.1-cp312-abi3-win_amd64.whl (28.1 MB)
     ---------------------------------------- 28.1/28.1 MB 42.0 MB/s  0:00:00
Collecting certifi==2026.7.22 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 9))
  Downloading certifi-2026.7.22-py3-none-any.whl (136 kB)
Collecting cffi==2.1.1 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 11))
  Downloading cffi-2.1.1-cp313-cp313-win_amd64.whl (185 kB)
Collecting contourpy==1.4.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 14))
  Downloading contourpy-1.4.0-cp313-cp313-win_amd64.whl (234 kB)
Collecting cv2-enumerate-cameras==1.4.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 17))
  Downloading cv2_enumerate_cameras-1.4.0-cp310-abi3-win_amd64.whl (209 kB)
Collecting cycler==0.12.1 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 20))
  Downloading cycler-0.12.1-py3-none-any.whl (8.3 kB)
Collecting flatbuffers==25.12.19 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 22))
  Downloading flatbuffers-25.12.19-py2.py3-none-any.whl (26 kB)
Collecting fonttools==4.66.1 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 24))
  Downloading fonttools-4.66.1-cp313-cp313-win_amd64.whl (2.5 MB)
     ---------------------------------------- 2.5/2.5 MB 65.2 MB/s  0:00:00
Collecting kiwisolver==1.5.1 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 27))
  Downloading kiwisolver-1.5.1-cp313-cp313-win_amd64.whl (70 kB)
Collecting matplotlib==3.11.2 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 30))
  Downloading matplotlib-3.11.2-cp313-cp313-win_amd64.whl (9.3 MB)
     ---------------------------------------- 9.3/9.3 MB 101.6 MB/s  0:00:00
Collecting mediapipe==1.1.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 33))
  Downloading mediapipe-1.1.0-py3-none-win_amd64.whl (22.4 MB)
     ---------------------------------------- 22.4/22.4 MB 82.8 MB/s  0:00:00
Collecting numpy==2.5.3 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 36))
  Downloading numpy-2.5.3-cp313-cp313-win_amd64.whl (12.6 MB)
     ---------------------------------------- 12.6/12.6 MB 99.7 MB/s  0:00:00
Collecting opencv-contrib-python==5.0.0.93 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 39))
  Downloading opencv_contrib_python-5.0.0.93-cp37-abi3-win_amd64.whl (53.8 MB)
     ---------------------------------------- 53.8/53.8 MB 74.2 MB/s  0:00:00
Collecting packaging==26.3 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 42))
  Downloading packaging-26.3-py3-none-any.whl (129 kB)
Collecting pillow==12.3.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 44))
  Downloading pillow-12.3.0-cp313-cp313-win_amd64.whl (7.2 MB)
     ---------------------------------------- 7.2/7.2 MB 82.7 MB/s  0:00:00
Collecting psutil==7.2.2 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 47))
  Downloading psutil-7.2.2-cp37-abi3-win_amd64.whl (137 kB)
Collecting pycparser==3.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 50))
  Downloading pycparser-3.0-py3-none-any.whl (48 kB)
Collecting pyparsing==3.3.3 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 52))
  Downloading pyparsing-3.3.3-py3-none-any.whl (126 kB)
Collecting pypdfium2==5.13.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 54))
  Downloading pypdfium2-5.13.0-py3-none-win_amd64.whl (3.9 MB)
     ---------------------------------------- 3.9/3.9 MB 82.0 MB/s  0:00:00
Collecting python-dateutil==2.9.0.post0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 57))
  Downloading python_dateutil-2.9.0.post0-py2.py3-none-any.whl (229 kB)
Collecting six==1.17.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 59))
  Downloading six-1.17.0-py2.py3-none-any.whl (11 kB)
Collecting sounddevice==0.5.6 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 61))
  Downloading sounddevice-0.5.6-py3-none-win_amd64.whl (1.0 MB)
     ---------------------------------------- 1.0/1.0 MB 27.7 MB/s  0:00:00
Installing collected packages: mediapipe, flatbuffers, sounddevice, six, python-dateutil, pypdfium2, pyparsing, pycparser, psutil, pillow, packaging, opencv-contrib-python, numpy, matplotlib, kiwisolver, fonttools, cycler, cv2-enumerate-cameras, contourpy, cffi, certifi, av, absl-py

Successfully installed absl-py-2.5.0 av-19.0.1 certifi-2026.7.22 cffi-2.1.1 contourpy-1.4.0 cv2-enumerate-cameras-1.4.0 cycler-0.12.1 flatbuffers-25.12.19 fonttools-4.66.1 kiwisolver-1.5.1 matplotlib-3.11.2 mediapipe-1.1.0 numpy-2.5.3 opencv-contrib-python-5.0.0.93 packaging-26.3 pillow-12.3.0 psutil-7.2.2 pycparser-3.0 pyparsing-3.3.3 pypdfium2-5.13.0 python-dateutil-2.9.0.post0 six-1.17.0 sounddevice-0.5.6
встраиваемый Python 3.13.16: sha256=97dae5274cc54867065e8d5a3226e48c35017ed332a0fdb0e27d5b5821961297
подпись python.exe: Valid; CN=Python Software Foundation, O=Python Software Foundation, L=Beaverton, S=Oregon, C=US
модель лица: sha256=64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff
папка eye/: 394 МБ (бюджет 400); крупнее всего: {'cv2': 113.9, 'av.libs': 67.2, 'mediapipe': 64.7, 'matplotlib': 25.7, 'numpy.libs': 21.2, 'numpy': 17.1, 'PIL': 16.0, 'fontTools': 11.7}
```

## eye-selftest
```
# Пробный запуск

```
Спутник 0.5.0, Python 3.13.16, MediaPipe 1.1.0, OpenCV 5.0.0, PyAV 19.0.1
Модель лица сверена: 64184e229b26…
Пустой кадр: лица нет — как и должно быть
H.264 пишется и читается
Камера не найдена
{"satellite": "0.5.0", "protocol": 1, "python": "3.13.16", "platform": "Windows-2025Server-10.0.26100-SP0", "ok": true, "opencv": "5.0.0", "av": "19.0.1", "mediapipe": "1.1.0", "model_sha256": "64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff", "blank_frame": "no_face", "x264": true, "cameras": [], "camera": "no_camera"}
```

## stderr
```
2026-11-07 10:46:07,353 matplotlib.font_manager generated new fontManager
WARNING: Logging before InitGoogle() is written to STDERR
W0000 00:00:1794048367.809788    2060 face_landmarker_graph.cc:180] Sets FaceBlendshapesGraph acceleration to xnnpack by default.
INFO: Created TensorFlow Lite XNNPACK delegate for CPU.
W0000 00:00:1794048367.821715    3516 inference_feedback_manager.cc:121] Feedback manager requires a model with a single signature inference. Disabling support for feedback tensors.
W0000 00:00:1794048367.833672    3516 inference_feedback_manager.cc:121] Feedback manager requires a model with a single signature inference. Disabling support for feedback tensors.
```

## Сеть за пробу
tcp 0.0.0.0:0
tcp 74.125.132.94:80
tcp 172.217.119.4:443
dns c.pki.goog
dns play.googleapis.com

## Размер
{
 "size_mb": 394.0,
 "budget_mb": 400,
 "python": "3.13.16",
 "largest_mb": {
  "cv2": 113.9,
  "av.libs": 67.2,
  "mediapipe": 64.7,
  "matplotlib": 25.7,
  "numpy.libs": 21.2,
  "numpy": 17.1,
  "PIL": 16.0,
  "fontTools": 11.7
 }
}
```
