# Прогон CI №374

- коммит: `36a150984f916da3d602f0ceef40e5dd6a5b9f21`
- ветка: `main`
- анализ и тесты: **success**
- сборка APK: **success**
- сборка Windows: **success**
- спутник взгляда: тесты **success**, сборка **success**
- страница прогона:
  https://github.com/Owner102007/MemoriaLLM/actions/runs/38093643720

## analyze
```
Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 108.0.0 (109.0.0 available)
  analyzer 14.4.0 (14.5.0 available)
  archive 4.2.0 (4.4.0 available)
  build_runner 2.16.1 (2.16.2 available)
  built_collection 5.1.1 (5.1.2 available)
  cli_util 0.5.2 (0.6.0 available)
  code_assets 2.0.0 (2.1.0 available)
  cross_file 0.3.5+5 (0.4.0 available)
  cupertino_ui 1.0.2 (1.1.2 available)
  drift 2.35.0 (2.35.2 available)
  drift_dev 2.35.0 (2.35.1 available)
  fast_file_picker 1.0.2 (2.0.1 available)
  flutter_lints 5.0.0 (6.0.0 available)
  get_it 9.2.1 (9.3.0 available)
  image 4.9.2 (4.11.1 available)
  ios_document_picker 1.0.0 (2.0.2 available)
  jni 1.0.3 (1.1.0 available)
  jni_flutter 1.0.3 (1.0.4+1 available)
  lints 5.1.1 (6.1.0 available)
  macos_file_picker 0.7.3 (2.0.0 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  material_ui 1.2.0 (1.6.0 available)
  native_toolchain_c 0.19.4 (0.19.5 available)
  objective_c 9.6.0 (9.6.2 available)
  pdfium_dart 0.3.0 (0.3.1 available)
  pdfium_flutter 0.3.0 (0.3.1 available)
  pdfrx 2.6.1 (2.6.5 available)
  pdfrx_engine 0.6.0 (0.6.1 available)
  saf_util 3.1.0 (3.1.1 available)
  sqlite3 3.5.2 (3.7.0 available)
  sqlite3_flutter_libs 0.5.42 (0.6.0+eol available)
  test_api 0.7.12 (0.7.15 available)
  url_launcher 6.3.2 (6.3.3 available)
  vector_math 2.4.2 (2.4.3 available)
Got dependencies!
34 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing MemoriaLLM...                                         
No issues found! (ran in 19.7s)
```

## codegen
```
  compiling builders/aot
  33s compiling builders/aot
  0s drift_dev on 1612 inputs; lib/application/app_services.dart
  13s drift_dev on 1612 inputs: 1 output; spent 9s analyzing, 2s resolving, 1s sdk; lib/application/build_info.dart
  14s drift_dev on 1612 inputs: 222 output; spent 10s analyzing, 2s resolving, 1s sdk; test/annotations/markdown_export_test.dart
  16s drift_dev on 1612 inputs: 459 output, 25 no-op; spent 12s analyzing, 2s resolving, 1s sdk; lib/infrastructure/database/connection.dart
  18s drift_dev on 1612 inputs: 462 output, 26 no-op; spent 13s analyzing, 2s resolving, 1s sdk; lib/infrastructure/files/android_book_storage.dart
  19s drift_dev on 1612 inputs: 170 skipped, 764 output, 213 no-op; spent 14s analyzing, 2s resolving, 1s sdk, 1s building; lib/sno/recording/session.dart.types.temp.dart
  19s drift_dev on 1612 inputs: 403 skipped, 764 output, 445 no-op; spent 14s analyzing, 2s resolving, 1s sdk, 1s building
  0s source_gen:combining_builder on 806 inputs; lib/application/app_services.dart
  0s source_gen:combining_builder on 806 inputs: 403 skipped, 1 output, 402 no-op
  Built with build_runner/aot in 53s; wrote 765 outputs.
```

## measures
```
Shell: ЗАМЕР ALG-MAP-12 | кадр карты на 300 книг | бюджет 16 мс | 2.24 мс на кадр
Shell: ЗАМЕР ALG-MAP-12 | отбор подписей из 300 | бюджет 4 мс | встало 24 | 0.192 мс на кадр
Shell: ЗАМЕР ALG-MAP-03 | веса BM25 | расхождение с эталоном | 0.0
Shell: ЗАМЕР ALG-MAP-06 | координаты | расхождение с эталоном | 0.0
Shell: ЗАМЕР ALG-MAP-06 | раскладка 1000 книг | бюджет 2 с | 697 мс
Shell: ЗАМЕР ALG-MAP-06 | раскладка 10000 книг | бюджет 20 с | 5509 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | открытие книги | было 19.2 мс | стало 2.1 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | открытие и рамка страницы 600 | было 14.4 мс | стало 7.5 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | переход на соседнюю страницу | было 0.2 мс | стало 0.3 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | открытие книги | было 17.1 мс | стало 1.5 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | открытие и рамка страницы 60 | было 19.9 мс | стало 8.4 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | переход на соседнюю страницу | было 3.4 мс | стало 0.3 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | открытие книги | было 1.0 мс | стало 1.0 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | открытие и рамка страницы 1 | было 9.3 мс | стало 7.6 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | переход на соседнюю страницу | было 6.4 мс | стало 0.2 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | переход на непосчитанную страницу | было 5.7 мс | стало 8.2 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | измерить все страницы | 18.0 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | измерить все страницы | 21.9 мс
Shell: ЗАМЕР F-READ-15 | book_120_pages.pdf | разных ширин рамки | было 10 | стало 1 | страниц с расширенной рамкой 2 из 120
Shell: ЗАМЕР F-READ-15 | book_120_pages.pdf | рамка: вся книга постранично против выборки из 16 страниц | было 459.6 мс | стало 68.1 мс
Shell: ЗАМЕР F-TEXT-04 | book_120_pages.pdf | страниц 120 | текста 337988 знаков | проход 171.9 мс | первый поиск 210.0 мс | второй поиск 19.2 мс
Shell: ЗАМЕР F-TEXT-04 | huge_1200_pages.pdf | страниц 1200 | текста 16800 знаков | проход 193.8 мс | первый поиск 220.5 мс | второй поиск 17.2 мс
Shell: ЗАМЕР F-TEXT-04 | scan_no_text.pdf | страниц 2 | текста 0 знаков | проход 0.4 мс | первый поиск 1.4 мс | второй поиск 0.1 мс
01:24 +1318 ~18: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_frames_test.dart: SNO-F-REC-03: сборщик потока кадров SNO-F-REC-03: ЗАМЕР — сколько весит поток за сорок минут чтения
ЗАМЕР SNO-F-REC-03: кадр чтения 753 байт; за 40 минут ~480 кадров, ~352 КБ
01:24 +1325 ~18: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_frames_test.dart: SNO-ALG-REC-02: экраны без листа — по эталону (шаг 31) SNO-F-REC-03: ЗАМЕР — сколько весит кадр полки и кадр карты
ЗАМЕР SNO-F-REC-03: кадр полки (48 книг) 10284 байт, минута прокрутки ~3012 КБ; кадр карты (60 звёзд) 6427 байт
ЗАМЕР: поток ввода за 40 минут — 1117 КБ, строк 5381, касаний 3000
```

## tests
```
_test.dart: навигация BUG-39: протяжка ползунка открывает одну страницу
02:56 +2841 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация BUG-39: бегунок остановили, не отпуская, — страница открыта
02:56 +2842 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация F-READ-28: бегунок ждёт конца перехода и не отскакивает
02:56 +2843 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация книга из одной страницы обходится без ползунка
02:57 +2844 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление открывается и переводит на выбранный раздел
02:57 +2845 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_spread_test.dart: F-READ-06: листание разворота BUG-01: разворот листается парами, экран не повторяется
02:57 +2846 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_spread_test.dart: F-READ-06: листание разворота BUG-01: разворот листается парами, экран не повторяется
02:57 +2847 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:57 +2848 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:57 +2849 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:57 +2850 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:57 +2851 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:57 +2852 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:57 +2853 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:57 +2854 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:57 +2855 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:57 +2856 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:57 +2857 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:57 +2858 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:57 +2859 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:57 +2860 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:57 +2861 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_spread_test.dart: гонка переходов BUG-11: быстрый шаг через границу страницы помнит полосу
02:57 +2862 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск переход к найденному несёт само совпадение
02:58 +2863 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск переход к найденному несёт само совпадение
02:58 +2864 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск кнопка поиска стоит в верхней панели
02:58 +2865 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск пустой результат так и написан
02:58 +2866 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
02:58 +2867 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым второй результат выбирается без повторного открытия
02:58 +2868 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2869 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2870 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2871 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2872 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2873 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2874 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2875 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2876 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2877 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2878 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2879 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2880 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2881 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2882 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2883 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2884 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2885 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2886 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2887 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:58 +2888 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:59 +2889 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:59 +2890 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:59 +2891 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:59 +2892 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:59 +2893 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:59 +2894 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:59 +2895 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F3 при открытом поиске — тоже выбор результата
02:59 +2896 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:59 +2897 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым кнопка ✕ закрывает поиск
02:59 +2898 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
02:59 +2899 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
02:59 +2900 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
02:59 +2901 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
03:00 +2902 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
03:00 +2903 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
03:00 +2904 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
03:00 +2905 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
03:00 +2906 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
03:00 +2907 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
03:00 +2908 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
03:00 +2909 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
03:00 +2910 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
03:00 +2911 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
03:00 +2912 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
03:00 +2913 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
03:00 +2914 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: F-READ-13: третий уровень — назначенный кусок соседа F-READ-13: маска с соседями рисуется и нажатий не ловит
03:00 +2915 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: F-READ-13: третий уровень — назначенный кусок соседа F-READ-13: маска с соседями рисуется и нажатий не ловит
03:00 +2916 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: F-READ-13: третий уровень — назначенный кусок соседа F-READ-13: маска с соседями рисуется и нажатий не ловит
03:00 +2917 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
03:00 +2918 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
03:00 +2919 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
03:00 +2920 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: поле в полосе читается на своём фоне
03:00 +2921 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: телефон в альбоме — полоса тоже снизу
03:00 +2922 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
03:01 +2923 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: с клавиатурой полоса стоит над ней
03:01 +2924 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: в тесноте полоса сжимается, а не ломается
03:01 +2925 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: в тесноте полоса сжимается, а не ломается
03:01 +2926 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: в тесноте полоса сжимается, а не ломается
03:01 +2927 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: в тесноте полоса сжимается, а не ломается
03:01 +2928 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: в тесноте полоса сжимается, а не ломается
03:01 +2929 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/progress_slot_test.dart: указатель всегда внутри экрана
03:01 +2930 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: поиск, открытый кнопкой, прячет панели чтения
03:01 +2931 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: поиск, открытый кнопкой, прячет панели чтения
03:01 +2932 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: поиск, открытый кнопкой, прячет панели чтения
03:01 +2933 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: поиск, открытый кнопкой, прячет панели чтения
03:01 +2934 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: поиск, открытый кнопкой, прячет панели чтения
03:01 +2935 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: поиск, открытый кнопкой, прячет панели чтения
03:01 +2936 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: поиск, открытый кнопкой, прячет панели чтения
03:01 +2937 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: поиск, открытый кнопкой, прячет панели чтения
03:01 +2938 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: поиск, открытый кнопкой, прячет панели чтения
03:01 +2939 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
03:02 +2940 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: пока набирают запрос, клавиши — у поля
03:02 +2941 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
03:02 +2942 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
03:02 +2943 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
03:02 +2944 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
03:02 +2945 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
03:02 +2946 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
03:02 +2947 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
03:02 +2948 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
03:02 +2949 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
03:02 +2950 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
03:02 +2951 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
03:02 +2952 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
03:02 +2953 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
03:02 +2954 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
03:02 +2955 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
03:02 +2956 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
03:02 +2957 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: SNO-F-READ-01: другие написания запроса SNO-F-READ-01: предел считается по общему списку
03:02 +2958 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура стрелки и пробел листают книгу
03:02 +2959 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура стрелки и пробел листают книгу
03:02 +2960 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура стрелки и пробел листают книгу
03:02 +2961 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура стрелки и пробел листают книгу
03:02 +2962 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура стрелки и пробел листают книгу
03:02 +2963 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура стрелки и пробел листают книгу
03:02 +2964 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура стрелки и пробел листают книгу
03:02 +2965 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура стрелки и пробел листают книгу
03:02 +2966 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: F-TEXT-04: поиск по кэшу текста книга, которая не прочиталась, — не скан
03:02 +2967 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-25: листают клавиши из таблицы читателя
03:02 +2968 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-25: листают клавиши из таблицы читателя
03:02 +2969 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-25: листают клавиши из таблицы читателя
03:02 +2970 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-25: листают клавиши из таблицы читателя
03:02 +2971 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-25: листают клавиши из таблицы читателя
03:02 +2972 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-25: листают клавиши из таблицы читателя
03:02 +2973 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-25: листают клавиши из таблицы читателя
03:02 +2974 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-25: листают клавиши из таблицы читателя
03:02 +2975 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура Ctrl+F открывает поиск, Esc его закрывает
03:02 +2976 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура Esc без открытых панелей снимает выделение
03:02 +2977 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 ведёт по совпадениям по кругу
03:02 +2978 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
03:02 +2979 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: при двух совпадениях первое Shift+F3 — на второе
03:03 +2980 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура новый запрос начинает счёт совпадений заново
03:03 +2981 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура пробел и Backspace в поле поиска принадлежат полю
03:03 +2982 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 работает и из поля: его поле не ждёт
03:03 +2983 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: F11 разворачивает чтение и возвращает окно
03:03 +2984 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: без окна F11 уходит мимо экрана чтения
03:03 +2985 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc возвращает окно, когда закрывать нечего
03:03 +2986 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc сначала прячет панели и снимает выделение
03:03 +2987 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
03:03 +2988 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура без найденного F3 молчит
03:03 +2989 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: листание вперёд листают стрелки, пробел и PageDown
03:03 +2990 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: листание назад листают стрелки, PageUp и Shift+пробел
03:03 +2991 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: листание клавиши листают и при выделенном тексте
03:03 +2992 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск Ctrl+F открывает поиск
03:03 +2993 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск Ctrl с чем угодно другим ничего не значит
03:03 +2994 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск F3 ведёт по совпадениям, а Shift+F3 — назад
03:03 +2995 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск F3 без найденного молчит
03:03 +2996 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск Enter — следующее совпадение, только пока ищут
03:03 +2997 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: Esc закрывает то, что открыто
03:03 +2998 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: обычная буква не значит ничего
03:03 +2999 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст пробел и Backspace принадлежат полю, а не книге
03:03 +3000 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст и стрелки с Page тоже: ими двигают курсор
03:03 +3001 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст Enter в поле разбирает само поле
03:03 +3002 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст Esc оставлен панели поиска: ей ближе
03:03 +3003 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст F3 и Ctrl+F поле не ждёт никогда — они работают
03:03 +3004 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-35: чтение во весь экран F-READ-35: F11 разворачивает чтение там, где есть окно
03:03 +3005 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-35: чтение во весь экран F-READ-35: без окна F11 не значит ничего
03:03 +3006 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-35: чтение во весь экран F-READ-35: F11 работает и из поля поиска — поле его не ждёт
03:03 +3007 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-35: чтение во весь экран F-READ-35: Esc выводит из полного экрана последним
03:03 +3008 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-35: чтение во весь экран F-READ-35: в обычном окне Esc делает то же, что раньше
03:03 +3009 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: BUG-08: шаг по совпадениям с «ни на каком» шаг назад ведёт на последнее совпадение
03:03 +3010 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: BUG-08: шаг по совпадениям с «ни на каком» шаг вперёд ведёт на первое совпадение
03:03 +3011 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: BUG-08: шаг по совпадениям дальше шаг идёт по кругу в обе стороны
03:03 +3012 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: BUG-08: шаг по совпадениям совпадений нет — идти некуда
03:03 +3013 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: BUG-08: шаг по совпадениям устаревший номер считается «ни на каком»
03:03 +3014 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-25: клавиши листания по таблице переназначенная клавиша действует, прежняя — нет
03:03 +3015 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-25: клавиши листания по таблице клавиша, отданная другому действию, листает в другую сторону
03:03 +3016 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-25: клавиши листания по таблице служебные клавиши таблица не перекрывает
03:03 +3017 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-25: клавиши листания по таблице с Ctrl назначенная клавиша не листает
03:03 +3018 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-25: клавиши листания по таблице пока набирают текст, назначенная буква принадлежит полю
03:04 +3019 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: матрица просмотрщика масштаб берётся из раскладки листа
03:04 +3020 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: матрица просмотрщика вторая страница разворота сдвигает начало документа
03:04 +3021 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: матрица просмотрщика щипок читателя накладывается сверху
03:04 +3022 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: обратный ход: что читатель добавил сам нетронутая страница даёт единичное преобразование
03:04 +3023 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: обратный ход: что читатель добавил сам щипок возвращается тем же, каким его положили
03:04 +3024 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: обратный ход: что читатель добавил сам вырожденная матрица преобразования не даёт
03:04 +3025 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик F-READ-12: лист ниже по документу сдвигает матрицу вверх
03:04 +3026 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик F-READ-12: верх листа встаёт туда, куда велит раскладка
03:04 +3027 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик F-READ-12: обратный ход в столбике возвращает тот же щипок
03:04 +3028 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик F-READ-12: нетронутый лист в столбике не даёт преобразования
03:04 +3029 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик F-READ-12: точка экрана переводится в точку листа в столбике
03:04 +3030 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик BUG-40: возврат просмотрщика в столбике отклоняется так же
03:04 +3031 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: точка экрана в координатах документа перевод обратим
03:04 +3032 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: точка экрана в координатах документа перевод обратим и после щипка
03:04 +3033 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: точка экрана в координатах документа вырожденная раскладка точки не даёт
03:04 +3034 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий над выделением, если сверху есть место
03:04 +3035 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий под выделением, если сверху места нет
03:04 +3036 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий панель не вылезает за края экрана
03:04 +3037 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий выделение во весь экран не выталкивает панель наружу
03:04 +3038 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий BUG-03: панель стоит по середине выделения
03:04 +3039 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий BUG-03: настоящая высота панели ставит её вплотную к слову
03:04 +3040 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий BUG-03: панель шире экрана начинается у левого поля
03:04 +3041 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий BUG-25: привязка — прямоугольник всего выделения
03:04 +3042 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий BUG-25: прямоугольников нет — панель посередине области
03:04 +3043 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: вид листа переводит страницу в экран нетронутая страница ложится ровно по раскладке
03:04 +3044 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: вид листа переводит страницу в экран после щипка едет вместе со страницей
03:04 +3045 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: маска ложится туда же, где лист без щипка лист и полоса совпадают с раскладкой
03:04 +3046 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: маска ложится туда же, где лист щипок двигает и лист, и полосу одинаково
03:04 +3047 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: маска ложится туда же, где лист пустая раскладка даёт пустые прямоугольники
03:04 +3048 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: предел свободы при отпертом замке нетронутое преобразование не трогается
03:04 +3049 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: предел свободы при отпертом замке масштаб держится в границах
03:04 +3050 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: предел свободы при отпертом замке страницу нельзя увести с экрана
03:04 +3051 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: предел свободы при отпертом замке упёршись в предел масштаба, страница не прыгает вбок
03:04 +3052 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: предел свободы при отпертом замке мусор на входе даёт нетронутый лист
03:04 +3053 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-40: движение читателя — только пока раскладка стоит BUG-40: возврат просмотрщика похож на сдвиг через полкниги
03:04 +3054 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-40: движение читателя — только пока раскладка стоит BUG-40: пока страницы перекладываются, возврат не принимается
03:04 +3055 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-40: движение читателя — только пока раскладка стоит BUG-40: то, что читатель выставил сам, перекладка не трогает
03:04 +3056 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-40: движение читателя — только пока раскладка стоит BUG-40: раскладка встала — жест читателя принимается
03:04 +3057 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-40: движение читателя — только пока раскладка стоит BUG-40: при запертом замке страницу не двигает никто
03:04 +3058 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-26: замок возвращает сдвинутую страницу BUG-26: сдвинутая без масштаба страница встаёт на место
03:04 +3059 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-26: замок возвращает сдвинутую страницу BUG-26: страница, уехавшая к краю экрана, тоже возвращается
03:04 +3060 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-26: замок возвращает сдвинутую страницу BUG-26: осознанный масштаб замок сохраняет вместе со сдвигом
03:04 +3061 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-26: замок возвращает сдвинутую страницу BUG-26: нетронутая страница остаётся нетронутой
03:04 +3062 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-26: замок возвращает сдвинутую страницу BUG-26: мусор на входе даёт нетронутый лист
03:05 +3063 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: какие рамки считать заранее вперёд по ходу чтения — два листа, назад — один
03:05 +3064 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: какие рамки считать заранее читатель листает назад — готовится то, что позади
03:05 +3065 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: какие рамки считать заранее у края книги готовить за краем нечего
03:05 +3066 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: какие рамки считать заранее в развороте лист — две страницы, и готовятся обе
03:05 +3067 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика запас 1 — ровно по листу с каждой стороны
03:05 +3068 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика запас 2 — по два листа, третий не захвачен
03:05 +3069 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика перекос полей не теряет соседа и не цепляет лишнего
03:05 +3070 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика в развороте запас достаёт до дальней страницы соседа
03:05 +3071 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика запас 0 и широкое окно запаса не просят
03:05 +3072 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика вырожденные размеры — ноль, а не бесконечность
03:05 +3073 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-12: запас соседних листов в столбике F-READ-12: с любой полосы запас 1 — по листу сверху и снизу
03:05 +3074 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-12: запас соседних листов в столбике F-READ-12: запас 2 — по два листа, третий не захвачен
03:05 +3075 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-12: запас соседних листов в столбике F-READ-12: запас 0 запаса не просит
03:05 +3076 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-12: запас соседних листов в столбике F-READ-12: вырожденные размеры — ноль, а не бесконечность
03:05 +3077 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки предел пикселей: страница A4 — около двух с половиной
03:05 +3078 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки у страницы без размеров предела нет
03:05 +3079 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки первая картинка чуть мельче нужного экрану
03:05 +3080 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки рамки страниц гуляют — картинки не перерисовываются
03:05 +3081 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки удерживаемый масштаб крупнее нужного не остаётся
03:05 +3082 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки страница стала намного крупнее — картинки догоняют
03:05 +3083 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки бессмысленный запрос масштаба ничего не меняет
03:05 +3084 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: настройки показа страницы без сохранённого — сразу, запас по платформе
03:05 +3085 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: настройки показа страницы сохранённое главнее умолчания
03:05 +3086 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: настройки показа страницы мусор в базе не ломает чтение
03:05 +3087 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: настройки показа страницы выключенная ступенька запаса не держит
03:05 +3088 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране книга и подпись нарисованы
03:06 +3089 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране в узком поле рисунок остаётся
03:06 +3090 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: «Устройство» — раздел, а не экран поверх полки
03:06 +3091 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: «Устройство» — раздел, а не экран поверх полки
03:06 +3092 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: «Устройство» — раздел, а не экран поверх полки
03:06 +3093 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: «Устройство» — раздел, а не экран поверх полки
03:06 +3094 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: «Устройство» — раздел, а не экран поверх полки
03:06 +3095 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: «Устройство» — раздел, а не экран поверх полки
03:06 +3096 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: «Устройство» — раздел, а не экран поверх полки
03:06 +3097 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: «Устройство» — раздел, а не экран поверх полки
03:07 +3098 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
03:07 +3099 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
03:08 +3100 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: поиск и отмеченное переживают уход из раздела
03:08 +3101 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: поиск и отмеченное переживают уход из раздела
03:08 +3102 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
03:09 +3103 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: полка помнит место прокрутки
03:09 +3104 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: полка помнит место прокрутки
03:09 +3105 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: «+» категории ведёт в раздел и называет её
03:10 +3106 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: категорию можно снять; кнопка шапки её не зовёт
03:10 +3107 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: «назад» из раздела ведёт на полку
03:10 +3108 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: навигация на широком окне F-APP-02: от 900 точек разделы стоят наверху
03:11 +3109 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: навигация на широком окне F-APP-02: окно сузили — навигация внизу, раздел тот же
03:11 +3110 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: обход и открытая книга F-APP-02: пока книгу читают, обход устройства стоит
03:11 +3111 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: обход и открытая книга SNO-F-IDX-04: пока книгу читают, проход по полке стоит
03:12 +3112 ~28: All tests passed!
```

## sno
```
�ов SNO-F-REC-15: строки «Блок №» нет ни до записи, ни во время; отлучка — на экране завершения
00:55 +694 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-15: «Тестирование» и завершение без блоков SNO-F-REC-15: строки «Блок №» нет ни до записи, ни во время; отлучка — на экране завершения
00:55 +695 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-15: «Тестирование» и завершение без блоков SNO-F-REC-15: строки «Блок №» нет ни до записи, ни во время; отлучка — на экране завершения
00:55 +696 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-15: «Тестирование» и завершение без блоков SNO-F-REC-15: строки «Блок №» нет ни до записи, ни во время; отлучка — на экране завершения
00:55 +697 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-15: «Тестирование» и завершение без блоков SNO-F-REC-15: строки «Блок №» нет ни до записи, ни во время; отлучка — на экране завершения
00:55 +698 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-15: «Тестирование» и завершение без блоков SNO-F-REC-15: строки «Блок №» нет ни до записи, ни во время; отлучка — на экране завершения
00:55 +699 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-15: «Тестирование» и завершение без блоков SNO-F-REC-15: строки «Блок №» нет ни до записи, ни во время; отлучка — на экране завершения
00:55 +700 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-15: «Тестирование» и завершение без блоков SNO-F-REC-15: строки «Блок №» нет ни до записи, ни во время; отлучка — на экране завершения
00:55 +701 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-15: «Тестирование» и завершение без блоков SNO-F-REC-15: строки «Блок №» нет ни до записи, ни во время; отлучка — на экране завершения
00:55 +702 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-15: «Тестирование» и завершение без блоков SNO-F-REC-15: строки «Блок №» нет ни до записи, ни во время; отлучка — на экране завершения
00:55 +703 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-15: «Тестирование» и завершение без блоков SNO-F-REC-15: строки «Блок №» нет ни до записи, ни во время; отлучка — на экране завершения
00:55 +704 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-15: «Тестирование» и завершение без блоков SNO-F-REC-15: строки «Блок №» нет ни до записи, ни во время; отлучка — на экране завершения
00:55 +705 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-15: «Тестирование» и завершение без блоков SNO-F-REC-10: участник не уходил — строки об отлучках на экране завершения нет
00:55 +706 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:56 +707 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-02: вне записи SNO-F-REC-02: записи нет — ни одна строка не пишется
00:56 +708 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: запись создана — часы, журнал, снимок
00:56 +709 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-LIB-02: запись началась — полка под замком
00:56 +710 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: сброс к эталону перед записью попадает в журнал
00:56 +711 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: вторая запись без сброса — видно в журнале
00:56 +712 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: старт — t = 0, сколько бы ни отвечала база
00:56 +713 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-LIB-02: выбранный до старта порядок полки записан
00:56 +714 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-LIB-02: порядок «Как расставил» замком не меняется
00:56 +715 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: вторая запись поверх идущей не начинается
00:56 +716 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: папка записи не завелась — записи нет
00:56 +717 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: настройки не пишутся — записи нет
00:56 +718 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: отметка сессии не записалась — призрака не остаётся
00:56 +719 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: два старта разом — запись одна
00:56 +720 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: две записи в одну минуту — две папки
00:56 +721 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-02: журнал записи SNO-ALG-REC-01: сердцебиение — раз в десять секунд
00:56 +722 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-02: журнал записи SNO-F-REC-02: номера событий сквозные, время не убывает
00:56 +723 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-02: журнал записи SNO-F-REC-02: в событии — экран, на котором участник
00:56 +724 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-02: журнал записи SNO-F-REC-02: на диск журнал уходит каждую секунду
00:56 +725 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: через 40:00 запись останавливается сама
00:56 +726 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: сорок минут — по настенным часам: сон устройства запись не растягивает
00:56 +727 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: часы перевели назад — запись всё равно кончается через сорок минут
00:56 +728 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: экспериментатор останавливает раньше
00:56 +729 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: часы перевели назад — длительность и показ времени не обнуляются
00:56 +730 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: короткий сон записи не останавливает
00:56 +731 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-02: данные, которые не пишутся в JSON, номера не сбивают
00:56 +732 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: остановка дважды — одна
00:56 +733 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: уход в фон и возврат — пара событий и сверка часов
00:56 +734 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: остановка дописывает своё на диск — её можно дождаться
00:56 +735 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: об отказе диска при остановке узнают слушатели
00:56 +736 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: завершение сессии SNO-F-CFG-05: сессия завершена — замок снят, код забыт
00:56 +737 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: завершение сессии SNO-F-CFG-05: пока запись идёт, сессию не завершить
00:56 +738 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: завершение сессии SNO-F-CFG-05: завершение дожидается остановки
00:56 +739 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: завершение сессии SNO-F-CFG-05: отметка сессии не удалилась — замок всё равно снят
00:56 +740 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: завершение сессии SNO-F-CFG-05: следующий старт выдаёт новый код
00:56 +741 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: завершение сессии SNO-F-CFG-05: введённый код записан как введённый
00:56 +742 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: есть ли незавершённая сессия, известно только после прочитанной отметки
00:56 +743 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: новая запись после непрочитанной отметки — отметка о сессии снова своя
00:56 +744 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-01: запись, которую застал перезапуск, закрыта как оборванная
00:56 +745 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: остановка легла в журнал, отметка — нет: вторая остановка не пишется
00:56 +746 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: отметка сессии отстала от журнала — номер продолжает журнал
00:56 +747 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: последняя строка журнала — мусор: счёт берётся у читаемой
00:56 +748 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: сон устройства входит в длительность оборванной записи
00:56 +749 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: часы перевели назад, потом сбой — длительность не обнуляется
00:56 +750 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: в журнале и остановка, и завершение, а отметка отстала на оба — второй остановки нет
00:56 +751 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-CFG-03: остановленная сессия переживает перезапуск
00:56 +752 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-01: сессии нет — поднимать нечего
00:56 +753 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-01: испорченная отметка замка не оставляет
00:56 +754 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-01: журнал оборванной записи пропал — сессия всё равно закрывается
00:56 +755 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-01: отказ диска помнится и после перезапуска
00:57 +756 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-01: отметка сессии помнит, лёг ли журнал на диск
00:57 +757 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-ALG-REC-03: снимок конца записи SNO-ALG-REC-03: остановка кладёт снимок конца в папку записи
00:57 +758 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-ALG-REC-03: снимок конца записи SNO-ALG-REC-03: снимок конца не назван — берётся тот же, что снимок начала
00:57 +759 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-ALG-REC-03: снимок конца записи SNO-ALG-REC-03: снимок не снялся — так в нём и сказано, запись останавливается
00:57 +760 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-ALG-REC-03: снимок конца записи SNO-ALG-REC-03: у оборванной записи снимок конца снят при следующем запуске и так помечен
00:57 +761 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-ALG-REC-03: снимок конца записи SNO-ALG-REC-03: снимок, снятый вовремя, следующий запуск не затирает
00:57 +762 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-ALG-REC-03: снимок конца записи SNO-ALG-REC-03: журнал не прочитался — снимок, снятый вовремя, всё равно остаётся
00:57 +763 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: готовность устройства SNO-F-REC-01: мало заряда и места — предупреждение
00:57 +764 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: готовность устройства SNO-F-REC-01: хватает — предупреждать не о чем
00:57 +765 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: готовность устройства SNO-F-REC-01: устройство молчит — это не «мало»
00:57 +766 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: имена и запись состояния SNO-F-REC-01: папка записи названа ветвью, кодом, устройством и временем
00:57 +767 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: имена и запись состояния SNO-F-REC-01: время записи словами
00:57 +768 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: имена и запись состояния SNO-F-REC-01: идентификатор записи растёт со временем
00:57 +769 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: имена и запись состояния SNO-F-REC-01: состояние сессии читается обратно
00:57 +770 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: сброс к эталону и запись SNO-ALG-CFG-03: сброс не трогает список выданных кодов
00:57 +771 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: сброс к эталону и запись SNO-F-REC-01: отметки записи — не след читателя: снимок с эталоном совпадает
00:57 +772 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: сброс к эталону и запись SNO-F-REC-01: снимок без эталона так и говорит
00:57 +773 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: экран завершения SNO-F-REC-13: под числом событий сказано, что запись цела
00:58 +774 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: экран завершения SNO-F-REC-11: рядом сказано, цел ли поток ввода
00:58 +775 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:58 +776 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:58 +777 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:58 +778 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:58 +779 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:58 +780 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:58 +781 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:58 +782 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:58 +783 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: список записей на телефоне SNO-F-REC-13: у записи две отметки — отправка и копия
00:59 +784 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: блок «Для экспериментатора» свёрнут
00:59 +785 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: блок «Для экспериментатора» свёрнут
00:59 +786 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: список записей на телефоне SNO-F-REC-13: запись с копией удаляется одним вопросом, без копии и без отправки — двумя
00:59 +787 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: список записей на телефоне SNO-F-REC-13: запись с копией удаляется одним вопросом, без копии и без отправки — двумя
00:59 +788 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: пунктов-заглушек в разделе нет
00:59 +789 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: список записей на телефоне SNO-F-REC-13: копию убрали из «Загрузок» — запись удаляется только вторым подтверждением
00:59 +790 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: список записей на телефоне SNO-F-REC-13: копию убрали из «Загрузок» — запись удаляется только вторым подтверждением
00:59 +791 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: найденные архивы стоят списком, новые сверху
00:59 +792 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: отметка о копии без сверки SNO-F-REC-13: телефон, которому сверить копию нечем, одним подтверждением запись не удаляет
00:59 +793 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: архив из списка уходит в ту же распаковку
00:59 +794 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: архив из списка уходит в ту же распаковку
00:59 +795 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: «Тестирование» и уведомления SNO-F-REC-13: у устройства без защиты записи раздел молчит
01:00 +796 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: архивов нет — сказано словами
01:00 +797 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: «Тестирование» и уведомления SNO-F-REC-13: разрешение спрашивается перед первой записью, отказ старту не мешает
01:00 +798 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: пока идёт обход, найденное уже в списке
01:00 +799 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: «Тестирование» и уведомления SNO-F-REC-13: разрешили — строки об уведомлениях больше нет
01:00 +800 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: нажатие достаётся архиву, а не месту в списке
01:00 +801 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: нажатие достаётся архиву, а не месту в списке
01:00 +802 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: нажатие достаётся архиву, а не месту в списке
01:00 +803 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: начатый раньше поиск новому не мешает
01:00 +804 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: «Искать заново» останавливает прежний обход
01:00 +805 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: раздел закрыли — обход остановлен
01:00 +806 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: «Искать заново» обходит устройство ещё раз
01:00 +807 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: оборванный обход назван, найденное остаётся
01:01 +808 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/participant_code_test.dart: SNO-ALG-CFG-03: код из входов SNO-ALG-CFG-03: эталонные значения
01:01 +809 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: на ПК доступ не нужен и не просится
01:01 +810 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: на ПК доступ не нужен и не просится
01:01 +811 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: на ПК доступ не нужен и не просится
01:01 +812 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: на ПК доступ не нужен и не просится
01:01 +813 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/participant_code_test.dart: SNO-ALG-CFG-03: код из входов SNO-ALG-CFG-03: первая цифра не ноль, цифр всегда семь
01:01 +814 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: без доступа обхода нет, запрос — по кнопке
01:01 +815 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/participant_code_test.dart: SNO-ALG-CFG-03: ошибки почерка SNO-ALG-CFG-03: одна неверная цифра и перестановка соседних ловятся на 10 000 кодов
01:01 +816 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: отказали — запрос сам не повторяется
01:01 +817 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: отказали — запрос сам не повторяется
01:01 +818 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: отказали — запрос сам не повторяется
01:01 +819 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: отказали — запрос сам не повторяется
01:01 +820 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: отказали — запрос сам не повторяется
01:01 +821 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: отказали — запрос сам не повторяется
01:01 +822 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: отказали — запрос сам не повторяется
01:01 +823 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: отказали — запрос сам не повторяется
01:01 +824 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: отказали — запрос сам не повторяется
01:01 +825 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: вернулись в приложение — обход не повторён
01:01 +826 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: PDF вместо архива на полку не встаёт
01:01 +827 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: PDF и архив вместе — встаёт только архив
01:01 +828 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: кнопка и подписи книг не обещают
01:02 +829 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: книга узнаётся по имени файла
01:02 +830 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: отказ называет книги и говорит, как надо
01:02 +831 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: поимённо названы три книги, остальные числом
01:02 +832 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: архив распаковывается, итог — окном
01:02 +833 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: диалог закрыли — ничего не случилось
01:02 +834 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
01:02 +835 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
01:02 +836 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
01:02 +837 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
01:02 +838 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
01:02 +839 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
01:02 +840 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
01:02 +841 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
01:02 +842 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
01:02 +843 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
01:02 +844 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
01:02 +845 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
01:02 +846 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
01:02 +846 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/flags_test.dart: SNO-ALG-CFG-01: флаги этой сборки SNO-F-CFG-01: в сборке без SNO_BRANCH флаги ветви выключены
  Skip: прогон ветви: проверяется основным
01:02 +846 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
01:02 +847 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: пока архив открывается, это и сказано
01:02 +848 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: второе нажатие второй диалог не открывает
01:02 +849 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: сбой распаковки итога не съедает
01:02 +850 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: не-архив получает отказ от распаковки
01:03 +851 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/record_report_test.dart: SNO-F-RES-03: поход на полку из архива приложения
01:03 +852 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/record_report_test.dart: SNO-F-RES-03: поход на полку из архива приложения
01:03 +853 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: эталона нет — сказано, кнопки сброса нет
01:03 +854 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: разложенный архив запоминается эталоном
01:03 +855 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: удержание сбрасывает к эталону
01:03 +856 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: отпустили раньше — ничего не произошло
01:03 +857 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: пока идёт распаковка, сброс выключен
01:03 +858 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: вернулись в раздел — сверка заново
01:03 +859 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: отказанный архив эталоном не становится
01:04 +860 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: книги и категории сосчитаны
01:04 +861 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: без папок категорий нет и в словах
01:04 +862 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: тот же архив ещё раз
01:04 +863 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: часть была, часть встала, часть не открылась
01:04 +864 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: отказ архива и остановка названы
01:04 +865 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: причина движка сказана своими словами
01:04 +866 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: код устройства SNO-F-CFG-03: первые шесть знаков идентификатора узла
01:04 +867 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: зона за краем прокрутки SNO-F-REC-03: строки запаса прокрутки в кадр не попадают, подрезанная краем — видимой частью и с пометкой
01:04 +868 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: зона за краем прокрутки SNO-F-REC-03: прокрутка — кадры «в движении» не чаще пяти в секунду и один устоявшийся; строка под шапкой подрезана сверху
01:05 +869 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/shelf_reading_log_test.dart: SNO-F-IDX-04: смена дела и каждая прочитанная книга — строкой, страницы — нет
01:05 +870 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: в кадре полка со сдвигом прокрутки, шапки и участки категорий с названием, книги с отпечатком и категорией
01:05 +871 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: в кадре полка со сдвигом прокрутки, шапки и участки категорий с названием, книги с отпечатком и категорией
01:05 +872 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: в кадре полка со сдвигом прокрутки, шапки и участки категорий с названием, книги с отпечатком и категорией
01:05 +873 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: в кадре полка со сдвигом прокрутки, шапки и участки категорий с названием, книги с отпечатком и категорией
01:05 +874 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: в кадре полка со сдвигом прокрутки, шапки и участки категорий с названием, книги с отпечатком и категорией
01:05 +875 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: полку прокрутили — сдвиг в кадре тот же, что у списка, книги уехали вместе с ним
01:05 +876 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: касание книги лежит по кадру в зоне этой книги — той, что её открыла
01:06 +877 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +878 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +879 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +880 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +881 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +882 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +883 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +884 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +885 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +886 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +887 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +888 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +889 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +890 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +891 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +892 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +893 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +894 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +895 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +896 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +897 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +898 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +899 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +900 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +901 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +902 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +903 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +904 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +905 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +906 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
01:06 +907 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/load_test_test.dart: SNO-F-CLT-03: тест в записи при завершении сессии SNO-F-CLT-03: строка теста, оборванная закрытием приложения, не делает запись целой
01:07 +908 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: карта «Галактика» SNO-F-REC-03: в кадре — раздел, полотно с камерой и всеми видимыми звёздами на их местах
01:07 +909 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: карта «Галактика» SNO-F-REC-03: в кадре — раздел, полотно с камерой и всеми видимыми звёздами на их местах
01:07 +910 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: карта «Галактика» SNO-F-REC-03: касание звезды — по кадру её отпечаток; открытая карточка — зона поверх карты
01:07 +911 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: карта «Галактика» SNO-F-REC-03: перенос приближенной карты — кадры «в движении» и один устоявшийся с новой камерой
01:08 +912 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: тег сборки исследования SNO-F-CFG-06: тег исследования — sno2026-N и sno2026-N.M
01:08 +913 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: тег сборки исследования SNO-F-CFG-06: остальное тегом исследования не считается
01:08 +914 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: тег сборки исследования SNO-F-CFG-06: строка «О ветви» называет сборку и день
01:08 +915 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: тег сборки исследования SNO-F-CFG-06: сборка без тега — проверочная
01:08 +916 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: «Тестирование» на сборке исследования SNO-F-CFG-06: проверочная сборка сказана над стартом
01:08 +917 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: «Тестирование» на сборке исследования SNO-F-CFG-06: проверочная сборка сказана над стартом
01:08 +918 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: «Тестирование» на сборке исследования SNO-F-CFG-06: проверочная сборка сказана над стартом
01:08 +919 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: «Тестирование» на сборке исследования SNO-F-CFG-06: проверочная сборка сказана над стартом
01:09 +920 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: «Тестирование» на сборке исследования SNO-F-CFG-06: на сборке исследования пометки нет
01:09 +921 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
01:13 +922 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: только ветвь II пишет события карты и подготовки книг — и больше никаких
01:13 +923 ~5: All tests passed!
```

## sessions
```
Running build hooks...Running build hooks...Проверен PROGRESS.md; плана нет (../docs/dev_plan_sessions.md) — пропущен.
Номера сессий в порядке.
```

## eye-tests
```
........................................................................ [ 15%]
........................................................................ [ 30%]
........................................................................ [ 45%]
........................................................................ [ 61%]
........................................................................ [ 76%]
........................................................................ [ 91%]
......................................                                   [100%]
470 passed in 541.76s (0:09:01)
```

## eye-windows
```
Collecting absl-py==2.5.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 4))
  Downloading absl_py-2.5.0-py3-none-any.whl (137 kB)
Collecting av==19.0.1 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 6))
  Downloading av-19.0.1-cp312-abi3-win_amd64.whl (28.1 MB)
     ---------------------------------------- 28.1/28.1 MB 57.7 MB/s  0:00:00
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
     ---------------------------------------- 2.5/2.5 MB 61.3 MB/s  0:00:00
Collecting kiwisolver==1.5.1 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 27))
  Downloading kiwisolver-1.5.1-cp313-cp313-win_amd64.whl (70 kB)
Collecting matplotlib==3.11.2 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 30))
  Downloading matplotlib-3.11.2-cp313-cp313-win_amd64.whl (9.3 MB)
     ---------------------------------------- 9.3/9.3 MB 119.9 MB/s  0:00:00
Collecting mediapipe==1.1.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 33))
  Downloading mediapipe-1.1.0-py3-none-win_amd64.whl (22.4 MB)
     ---------------------------------------- 22.4/22.4 MB 61.6 MB/s  0:00:00
Collecting numpy==2.5.3 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 36))
  Downloading numpy-2.5.3-cp313-cp313-win_amd64.whl (12.6 MB)
     ---------------------------------------- 12.6/12.6 MB 126.2 MB/s  0:00:00
Collecting opencv-contrib-python==5.0.0.93 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 39))
  Downloading opencv_contrib_python-5.0.0.93-cp37-abi3-win_amd64.whl (53.8 MB)
     ---------------------------------------- 53.8/53.8 MB 25.1 MB/s  0:00:02
Collecting packaging==26.3 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 42))
  Downloading packaging-26.3-py3-none-any.whl (129 kB)
Collecting pillow==12.3.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 44))
  Downloading pillow-12.3.0-cp313-cp313-win_amd64.whl (7.2 MB)
     ---------------------------------------- 7.2/7.2 MB 152.0 MB/s  0:00:00
Collecting psutil==7.2.2 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 47))
  Downloading psutil-7.2.2-cp37-abi3-win_amd64.whl (137 kB)
Collecting pycparser==3.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 50))
  Downloading pycparser-3.0-py3-none-any.whl (48 kB)
Collecting pyparsing==3.3.3 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 52))
  Downloading pyparsing-3.3.3-py3-none-any.whl (126 kB)
Collecting python-dateutil==2.9.0.post0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 54))
  Downloading python_dateutil-2.9.0.post0-py2.py3-none-any.whl (229 kB)
Collecting six==1.17.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 56))
  Downloading six-1.17.0-py2.py3-none-any.whl (11 kB)
Collecting sounddevice==0.5.6 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 58))
  Downloading sounddevice-0.5.6-py3-none-win_amd64.whl (1.0 MB)
     ---------------------------------------- 1.0/1.0 MB 36.5 MB/s  0:00:00
Installing collected packages: mediapipe, flatbuffers, sounddevice, six, python-dateutil, pyparsing, pycparser, psutil, pillow, packaging, opencv-contrib-python, numpy, matplotlib, kiwisolver, fonttools, cycler, cv2-enumerate-cameras, contourpy, cffi, certifi, av, absl-py

Successfully installed absl-py-2.5.0 av-19.0.1 certifi-2026.7.22 cffi-2.1.1 contourpy-1.4.0 cv2-enumerate-cameras-1.4.0 cycler-0.12.1 flatbuffers-25.12.19 fonttools-4.66.1 kiwisolver-1.5.1 matplotlib-3.11.2 mediapipe-1.1.0 numpy-2.5.3 opencv-contrib-python-5.0.0.93 packaging-26.3 pillow-12.3.0 psutil-7.2.2 pycparser-3.0 pyparsing-3.3.3 python-dateutil-2.9.0.post0 six-1.17.0 sounddevice-0.5.6
встраиваемый Python 3.13.16: sha256=97dae5274cc54867065e8d5a3226e48c35017ed332a0fdb0e27d5b5821961297
подпись python.exe: Valid; CN=Python Software Foundation, O=Python Software Foundation, L=Beaverton, S=Oregon, C=US
модель лица: sha256=64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff
папка eye/: 384 МБ (бюджет 400); крупнее всего: {'cv2': 113.9, 'av.libs': 67.2, 'mediapipe': 64.7, 'matplotlib': 25.7, 'numpy.libs': 21.2, 'numpy': 17.1, 'PIL': 16.0, 'fontTools': 11.7}
```

## eye-selftest
```
# Пробный запуск

```
Спутник 0.4.0, Python 3.13.16, MediaPipe 1.1.0, OpenCV 5.0.0, PyAV 19.0.1
Модель лица сверена: 64184e229b26…
Пустой кадр: лица нет — как и должно быть
H.264 пишется и читается
Камера не найдена
{"satellite": "0.4.0", "protocol": 1, "python": "3.13.16", "platform": "Windows-2025Server-10.0.26100-SP0", "ok": true, "opencv": "5.0.0", "av": "19.0.1", "mediapipe": "1.1.0", "model_sha256": "64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff", "blank_frame": "no_face", "x264": true, "cameras": [], "camera": "no_camera"}
```

## stderr
```
2026-10-10 23:03:38,289 matplotlib.font_manager generated new fontManager
WARNING: Logging before InitGoogle() is written to STDERR
W0000 00:00:1791673418.700688    5476 face_landmarker_graph.cc:180] Sets FaceBlendshapesGraph acceleration to xnnpack by default.
INFO: Created TensorFlow Lite XNNPACK delegate for CPU.
W0000 00:00:1791673418.735891    8332 inference_feedback_manager.cc:121] Feedback manager requires a model with a single signature inference. Disabling support for feedback tensors.
W0000 00:00:1791673418.755214    8332 inference_feedback_manager.cc:121] Feedback manager requires a model with a single signature inference. Disabling support for feedback tensors.
```

## Сеть за пробу
dns c.pki.goog
dns ocsp.pki.goog
dns oneocsp.microsoft.com
dns play.googleapis.com

## Размер
{
 "size_mb": 384.4,
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
