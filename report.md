# Прогон CI №418

- коммит: `f9cb7810bb9ff6f5f5da617b9f4deba949c9a60f`
- ветка: `main`
- анализ и тесты: **success**
- сборка APK: **success**
- сборка Windows: **success**
- спутник взгляда: тесты **success**, сборка **success**
- страница прогона:
  https://github.com/Owner102007/MemoriaLLM/actions/runs/38470304820

## analyze
```
Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 108.0.0 (109.0.0 available)
  analyzer 14.4.0 (14.5.0 available)
  archive 4.2.0 (4.5.2 available)
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
  image 4.9.2 (4.12.0 available)
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
  sqlite3 3.5.2 (3.7.1 available)
  sqlite3_flutter_libs 0.5.42 (0.6.0+eol available)
  synchronized 3.4.2 (3.5.0 available)
  test_api 0.7.12 (0.7.15 available)
  url_launcher 6.3.2 (6.3.3 available)
  vector_math 2.4.2 (2.4.3 available)
Got dependencies!
35 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing MemoriaLLM...                                         
No issues found! (ran in 17.9s)
```

## codegen
```
  compiling builders/aot
  27s compiling builders/aot
  0s drift_dev on 1612 inputs; lib/application/app_services.dart
  10s drift_dev on 1612 inputs: 1 output; spent 8s analyzing, 1s resolving, 1s sdk; lib/application/build_info.dart
  11s drift_dev on 1612 inputs: 225 output; spent 8s analyzing, 2s resolving, 1s sdk; test/app_smoke_test.dart
  13s drift_dev on 1612 inputs: 459 output, 25 no-op; spent 10s analyzing, 2s resolving, 1s sdk; lib/infrastructure/database/connection.dart
  14s drift_dev on 1612 inputs: 462 output, 26 no-op; spent 11s analyzing, 2s resolving, 1s sdk; lib/infrastructure/files/android_book_storage.dart
  15s drift_dev on 1612 inputs: 169 skipped, 764 output, 212 no-op; spent 11s analyzing, 2s resolving, 1s sdk; lib/sno/recording/records_screen.dart.types.temp.dart
  16s drift_dev on 1612 inputs: 403 skipped, 764 output, 445 no-op; spent 11s analyzing, 2s resolving, 1s sdk, 1s building
  0s source_gen:combining_builder on 806 inputs; lib/application/app_services.dart
  0s source_gen:combining_builder on 806 inputs: 403 skipped, 1 output, 402 no-op
  Built with build_runner/aot in 44s; wrote 765 outputs.
```

## measures
```
Shell: ЗАМЕР ALG-MAP-12 | кадр карты на 300 книг | бюджет 16 мс | 1.03 мс на кадр
Shell: ЗАМЕР ALG-MAP-12 | отбор подписей из 300 | бюджет 4 мс | встало 24 | 0.105 мс на кадр
Shell: ЗАМЕР ALG-MAP-03 | веса BM25 | расхождение с эталоном | 0.0
Shell: ЗАМЕР ALG-MAP-06 | координаты | расхождение с эталоном | 0.0
Shell: ЗАМЕР ALG-MAP-06 | раскладка 1000 книг | бюджет 2 с | 369 мс
Shell: ЗАМЕР ALG-MAP-06 | раскладка 10000 книг | бюджет 20 с | 3523 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | открытие книги | было 9.5 мс | стало 1.8 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | открытие и рамка страницы 600 | было 8.6 мс | стало 3.8 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | переход на соседнюю страницу | было 0.1 мс | стало 0.3 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | открытие книги | было 14.0 мс | стало 1.0 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | открытие и рамка страницы 60 | было 14.1 мс | стало 5.2 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | переход на соседнюю страницу | было 2.1 мс | стало 0.2 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | открытие книги | было 0.9 мс | стало 0.8 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | открытие и рамка страницы 1 | было 5.3 мс | стало 6.5 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | переход на соседнюю страницу | было 4.7 мс | стало 0.2 мс
Shell: ЗАМЕР F-READ-02 | scan_no_text.pdf | переход на непосчитанную страницу | было 3.5 мс | стало 4.3 мс
Shell: ЗАМЕР F-READ-02 | huge_1200_pages.pdf | измерить все страницы | 8.2 мс
Shell: ЗАМЕР F-READ-02 | book_120_pages.pdf | измерить все страницы | 10.9 мс
Shell: ЗАМЕР F-READ-15 | book_120_pages.pdf | разных ширин рамки | было 10 | стало 1 | страниц с расширенной рамкой 2 из 120
Shell: ЗАМЕР F-READ-15 | book_120_pages.pdf | рамка: вся книга постранично против выборки из 16 страниц | было 219.2 мс | стало 38.7 мс
Shell: ЗАМЕР F-TEXT-04 | book_120_pages.pdf | страниц 120 | текста 337988 знаков | проход 135.5 мс | первый поиск 152.0 мс | второй поиск 12.4 мс
Shell: ЗАМЕР F-TEXT-04 | huge_1200_pages.pdf | страниц 1200 | текста 16800 знаков | проход 122.2 мс | первый поиск 196.4 мс | второй поиск 9.8 мс
Shell: ЗАМЕР F-TEXT-04 | scan_no_text.pdf | страниц 2 | текста 0 знаков | проход 0.2 мс | первый поиск 0.4 мс | второй поиск 0.0 мс
01:04 +1321 ~18: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_frames_test.dart: SNO-F-REC-03: сборщик потока кадров SNO-F-REC-03: ЗАМЕР — сколько весит поток за сорок минут чтения
ЗАМЕР SNO-F-REC-03: кадр чтения 753 байт; за 40 минут ~480 кадров, ~352 КБ
01:04 +1328 ~18: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_frames_test.dart: SNO-ALG-REC-02: экраны без листа — по эталону (шаг 31) SNO-F-REC-03: ЗАМЕР — сколько весит кадр полки и кадр карты
ЗАМЕР SNO-F-REC-03: кадр полки (48 книг) 10284 байт, минута прокрутки ~3012 КБ; кадр карты (60 звёзд) 6427 байт
ЗАМЕР: поток ввода за 40 минут — 1117 КБ, строк 5381, касаний 3000
```

## tests
```
 ползунка
02:12 +2853 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление открывается и переводит на выбранный раздел
02:12 +2854 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление книга без оглавления объясняет, почему его нет
02:12 +2855 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:13 +2856 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:13 +2857 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:13 +2858 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:13 +2859 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:13 +2860 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:13 +2861 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:13 +2862 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:13 +2863 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
02:13 +2864 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_spread_test.dart: F-READ-06: рамка разворота BUG-02: ручная рамка разворота — поля страницы, не листа
02:13 +2865 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск переход к найденному несёт само совпадение
02:13 +2866 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск переход к найденному несёт само совпадение
02:13 +2867 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск переход к найденному несёт само совпадение
02:13 +2868 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск переход к найденному несёт само совпадение
02:13 +2869 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск переход к найденному несёт само совпадение
02:13 +2870 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск переход к найденному несёт само совпадение
02:13 +2871 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_spread_test.dart: гонка переходов BUG-11: быстрый шаг через границу страницы помнит полосу
02:13 +2872 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск кнопка поиска стоит в верхней панели
02:13 +2873 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_spread_test.dart: гонка переходов BUG-11: шаг назад во время перехода считается от цели
02:13 +2874 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск пустой результат так и написан
02:13 +2875 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым выбор результата не закрывает панель
02:13 +2876 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым второй результат выбирается без повторного открытия
02:13 +2877 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ‹ и › ведут по совпадениям по кругу
02:14 +2878 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F3 при открытом поиске — тоже выбор результата
02:14 +2879 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2880 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2881 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2882 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2883 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2884 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2885 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2886 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2887 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2888 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2889 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2890 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2891 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2892 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2893 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2894 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2895 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2896 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2897 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2898 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2899 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2900 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2901 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2902 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2903 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2904 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2905 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc закрывает поиск и после выбора результата
02:14 +2906 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым кнопка ✕ закрывает поиск
02:14 +2907 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым системное «назад» закрывает поиск, а не книгу
02:14 +2908 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым при повторном открытии запрос и место в списке на месте
02:14 +2909 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым нажатие по запросу возвращает ко вводу
02:15 +2910 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2911 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2912 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2913 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2914 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2915 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2916 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2917 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2918 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2919 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2920 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2921 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2922 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2923 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2924 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2925 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: при вводе страница не закрыта
02:15 +2926 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: F-READ-13: третий уровень — назначенный кусок соседа F-READ-13: маска с соседями рисуется и нажатий не ловит
02:15 +2927 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: F-READ-13: третий уровень — назначенный кусок соседа F-READ-13: маска с соседями рисуется и нажатий не ловит
02:15 +2928 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: F-READ-13: третий уровень — назначенный кусок соседа F-READ-13: маска с соседями рисуется и нажатий не ловит
02:15 +2929 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
02:15 +2930 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
02:15 +2931 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: полоса не переезжает при шаге по совпадениям
02:15 +2932 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: с клавиатурой полоса стоит над ней
02:15 +2933 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: в тесноте полоса сжимается, а не ломается
02:15 +2934 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым F-TEXT-12: поиск, открытый кнопкой, прячет панели чтения
02:15 +2935 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: панель рядом со страницей, страница живая
02:16 +2936 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым широкое окно: пока набирают запрос, клавиши — у поля
02:16 +2937 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
02:16 +2938 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
02:16 +2939 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
02:16 +2940 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
02:16 +2941 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
02:16 +2942 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
02:16 +2943 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
02:16 +2944 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
02:16 +2945 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
02:16 +2946 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
02:16 +2947 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
02:16 +2948 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
02:16 +2949 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
02:16 +2950 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым ПК: поле отдало указатель ввода — клавиши чтения живы (variant: TargetPlatform.windows)
02:16 +2951 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: F-TEXT-11: поиск остаётся открытым Esc рядом с панелью сначала снимает выделение
02:16 +2952 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура стрелки и пробел листают книгу
02:16 +2953 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-25: листают клавиши из таблицы читателя
02:16 +2954 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура Ctrl+F открывает поиск, Esc его закрывает
02:16 +2955 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура Esc без открытых панелей снимает выделение
02:16 +2956 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 ведёт по совпадениям по кругу
02:16 +2957 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: первое Shift+F3 ведёт на последнее совпадение
02:16 +2958 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура BUG-08: при двух совпадениях первое Shift+F3 — на второе
02:16 +2959 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура новый запрос начинает счёт совпадений заново
02:17 +2960 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура пробел и Backspace в поле поиска принадлежат полю
02:17 +2961 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 работает и из поля: его поле не ждёт
02:17 +2962 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: F11 разворачивает чтение и возвращает окно
02:17 +2963 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: без окна F11 уходит мимо экрана чтения
02:17 +2964 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc возвращает окно, когда закрывать нечего
02:17 +2965 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc сначала прячет панели и снимает выделение
02:17 +2966 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: находит слово и указывает страницу
02:17 +2967 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
02:17 +2968 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
02:17 +2969 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
02:17 +2970 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
02:17 +2971 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
02:17 +2972 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
02:17 +2973 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
02:17 +2974 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
02:17 +2975 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
02:17 +2976 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
02:17 +2977 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
02:17 +2978 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
02:17 +2979 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
02:17 +2980 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
02:17 +2981 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F-READ-35: Esc при открытом поиске закрывает поиск
02:17 +2982 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: F-TEXT-04: поиск по кэшу текста второй поиск идёт без обращения к движку
02:17 +2983 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура без найденного F3 молчит
02:17 +2984 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура без найденного F3 молчит
02:17 +2985 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура без найденного F3 молчит
02:17 +2986 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: F-TEXT-04: поиск по кэшу текста неполный поиск называет остаток, и он убывает
02:17 +2987 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: F-TEXT-04: поиск по кэшу текста скан без текста: искать не в чем — так и сказано
02:17 +2988 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: F-TEXT-04: поиск по кэшу текста книга с текстом, но без находок — не скан
02:17 +2989 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: F-TEXT-04: поиск по кэшу текста нечитаемая страница не обрывает поиск и с кэшем
02:17 +2990 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: F-TEXT-04: поиск по кэшу текста книга, которая не прочиталась, — не скан
02:17 +2991 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: F-TEXT-04: поиск по кэшу текста нечитаемая страница не прячет текст книги
02:17 +2992 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: F-TEXT-04: поиск по кэшу текста F-DEV-13: книга, которая не прочиталась, — «не знаю»
02:17 +2993 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: F-TEXT-04: поиск по кэшу текста F-DEV-13: прочитанная книга без текста — скан
02:17 +2994 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: F-TEXT-04: поиск по кэшу текста F-DEV-13: текст после первых страниц находится
02:17 +2995 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: F-TEXT-04: поиск по кэшу текста F-DEV-13: дальше двадцатой страницы проверка не ходит
02:17 +2996 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: F-TEXT-04: поиск по кэшу текста F-DEV-13: три ответа проверки
02:17 +2997 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: F-TEXT-04: поиск по кэшу текста база отказала — поиск идёт движком, как раньше
02:17 +2998 ~28: loading /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart
02:18 +2998 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: листание вперёд листают стрелки, пробел и PageDown
02:18 +2999 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: листание назад листают стрелки, PageUp и Shift+пробел
02:18 +3000 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: листание клавиши листают и при выделенном тексте
02:18 +3001 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск Ctrl+F открывает поиск
02:18 +3002 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск Ctrl с чем угодно другим ничего не значит
02:18 +3003 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск F3 ведёт по совпадениям, а Shift+F3 — назад
02:18 +3004 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск F3 без найденного молчит
02:18 +3005 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск Enter — следующее совпадение, только пока ищут
02:18 +3006 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: Esc закрывает то, что открыто
02:18 +3007 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: обычная буква не значит ничего
02:18 +3008 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст пробел и Backspace принадлежат полю, а не книге
02:18 +3009 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст и стрелки с Page тоже: ими двигают курсор
02:18 +3010 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст Enter в поле разбирает само поле
02:18 +3011 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст Esc оставлен панели поиска: ей ближе
02:18 +3012 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст F3 и Ctrl+F поле не ждёт никогда — они работают
02:18 +3013 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-35: чтение во весь экран F-READ-35: F11 разворачивает чтение там, где есть окно
02:18 +3014 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-35: чтение во весь экран F-READ-35: без окна F11 не значит ничего
02:18 +3015 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-35: чтение во весь экран F-READ-35: F11 работает и из поля поиска — поле его не ждёт
02:18 +3016 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-35: чтение во весь экран F-READ-35: Esc выводит из полного экрана последним
02:18 +3017 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-35: чтение во весь экран F-READ-35: в обычном окне Esc делает то же, что раньше
02:18 +3018 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: BUG-08: шаг по совпадениям с «ни на каком» шаг назад ведёт на последнее совпадение
02:18 +3019 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: BUG-08: шаг по совпадениям с «ни на каком» шаг вперёд ведёт на первое совпадение
02:18 +3020 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: BUG-08: шаг по совпадениям дальше шаг идёт по кругу в обе стороны
02:18 +3021 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: BUG-08: шаг по совпадениям совпадений нет — идти некуда
02:18 +3022 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: BUG-08: шаг по совпадениям устаревший номер считается «ни на каком»
02:18 +3023 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-25: клавиши листания по таблице переназначенная клавиша действует, прежняя — нет
02:18 +3024 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-25: клавиши листания по таблице клавиша, отданная другому действию, листает в другую сторону
02:18 +3025 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-25: клавиши листания по таблице служебные клавиши таблица не перекрывает
02:18 +3026 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-25: клавиши листания по таблице с Ctrl назначенная клавиша не листает
02:18 +3027 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: F-READ-25: клавиши листания по таблице пока набирают текст, назначенная буква принадлежит полю
02:18 +3028 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: матрица просмотрщика масштаб берётся из раскладки листа
02:18 +3029 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: матрица просмотрщика вторая страница разворота сдвигает начало документа
02:18 +3030 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: матрица просмотрщика щипок читателя накладывается сверху
02:18 +3031 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: обратный ход: что читатель добавил сам нетронутая страница даёт единичное преобразование
02:18 +3032 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: обратный ход: что читатель добавил сам щипок возвращается тем же, каким его положили
02:18 +3033 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: обратный ход: что читатель добавил сам вырожденная матрица преобразования не даёт
02:18 +3034 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик F-READ-12: лист ниже по документу сдвигает матрицу вверх
02:18 +3035 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик F-READ-12: верх листа встаёт туда, куда велит раскладка
02:18 +3036 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик F-READ-12: обратный ход в столбике возвращает тот же щипок
02:18 +3037 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик F-READ-12: нетронутый лист в столбике не даёт преобразования
02:18 +3038 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик F-READ-12: точка экрана переводится в точку листа в столбике
02:18 +3039 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: F-READ-12: листы в столбик BUG-40: возврат просмотрщика в столбике отклоняется так же
02:18 +3040 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: точка экрана в координатах документа перевод обратим
02:18 +3041 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: точка экрана в координатах документа перевод обратим и после щипка
02:18 +3042 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: точка экрана в координатах документа вырожденная раскладка точки не даёт
02:18 +3043 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий над выделением, если сверху есть место
02:18 +3044 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий под выделением, если сверху места нет
02:18 +3045 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий панель не вылезает за края экрана
02:18 +3046 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий выделение во весь экран не выталкивает панель наружу
02:18 +3047 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий BUG-03: панель стоит по середине выделения
02:18 +3048 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий BUG-03: настоящая высота панели ставит её вплотную к слову
02:18 +3049 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий BUG-03: панель шире экрана начинается у левого поля
02:18 +3050 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий BUG-25: привязка — прямоугольник всего выделения
02:18 +3051 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: место панели действий BUG-25: прямоугольников нет — панель посередине области
02:18 +3052 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: вид листа переводит страницу в экран нетронутая страница ложится ровно по раскладке
02:18 +3053 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: вид листа переводит страницу в экран после щипка едет вместе со страницей
02:18 +3054 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: маска ложится туда же, где лист без щипка лист и полоса совпадают с раскладкой
02:18 +3055 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: маска ложится туда же, где лист щипок двигает и лист, и полосу одинаково
02:18 +3056 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: маска ложится туда же, где лист пустая раскладка даёт пустые прямоугольники
02:18 +3057 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: предел свободы при отпертом замке нетронутое преобразование не трогается
02:18 +3058 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: предел свободы при отпертом замке масштаб держится в границах
02:18 +3059 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: предел свободы при отпертом замке страницу нельзя увести с экрана
02:18 +3060 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: предел свободы при отпертом замке упёршись в предел масштаба, страница не прыгает вбок
02:18 +3061 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: предел свободы при отпертом замке мусор на входе даёт нетронутый лист
02:18 +3062 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-40: движение читателя — только пока раскладка стоит BUG-40: возврат просмотрщика похож на сдвиг через полкниги
02:18 +3063 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-40: движение читателя — только пока раскладка стоит BUG-40: пока страницы перекладываются, возврат не принимается
02:18 +3064 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-40: движение читателя — только пока раскладка стоит BUG-40: то, что читатель выставил сам, перекладка не трогает
02:18 +3065 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-40: движение читателя — только пока раскладка стоит BUG-40: раскладка встала — жест читателя принимается
02:18 +3066 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-40: движение читателя — только пока раскладка стоит BUG-40: при запертом замке страницу не двигает никто
02:18 +3067 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-26: замок возвращает сдвинутую страницу BUG-26: сдвинутая без масштаба страница встаёт на место
02:18 +3068 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-26: замок возвращает сдвинутую страницу BUG-26: страница, уехавшая к краю экрана, тоже возвращается
02:18 +3069 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-26: замок возвращает сдвинутую страницу BUG-26: осознанный масштаб замок сохраняет вместе со сдвигом
02:18 +3070 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-26: замок возвращает сдвинутую страницу BUG-26: нетронутая страница остаётся нетронутой
02:18 +3071 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_geometry_test.dart: BUG-26: замок возвращает сдвинутую страницу BUG-26: мусор на входе даёт нетронутый лист
02:18 +3072 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: какие рамки считать заранее вперёд по ходу чтения — два листа, назад — один
02:18 +3073 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: какие рамки считать заранее читатель листает назад — готовится то, что позади
02:18 +3074 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: какие рамки считать заранее у края книги готовить за краем нечего
02:18 +3075 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: какие рамки считать заранее в развороте лист — две страницы, и готовятся обе
02:18 +3076 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика запас 1 — ровно по листу с каждой стороны
02:18 +3077 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика запас 2 — по два листа, третий не захвачен
02:18 +3078 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика перекос полей не теряет соседа и не цепляет лишнего
02:18 +3079 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика в развороте запас достаёт до дальней страницы соседа
02:18 +3080 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика запас 0 и широкое окно запаса не просят
02:18 +3081 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: запас кэша просмотрщика вырожденные размеры — ноль, а не бесконечность
02:18 +3082 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-12: запас соседних листов в столбике F-READ-12: с любой полосы запас 1 — по листу сверху и снизу
02:18 +3083 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-12: запас соседних листов в столбике F-READ-12: запас 2 — по два листа, третий не захвачен
02:18 +3084 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-12: запас соседних листов в столбике F-READ-12: запас 0 запаса не просит
02:18 +3085 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-12: запас соседних листов в столбике F-READ-12: вырожденные размеры — ноль, а не бесконечность
02:18 +3086 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки предел пикселей: страница A4 — около двух с половиной
02:18 +3087 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки у страницы без размеров предела нет
02:18 +3088 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки первая картинка чуть мельче нужного экрану
02:18 +3089 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки рамки страниц гуляют — картинки не перерисовываются
02:18 +3090 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки удерживаемый масштаб крупнее нужного не остаётся
02:18 +3091 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки страница стала намного крупнее — картинки догоняют
02:18 +3092 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: масштаб грубой картинки бессмысленный запрос масштаба ничего не меняет
02:18 +3093 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: настройки показа страницы без сохранённого — сразу, запас по платформе
02:18 +3094 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: настройки показа страницы сохранённое главнее умолчания
02:18 +3095 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: настройки показа страницы мусор в базе не ломает чтение
02:18 +3096 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_turning_test.dart: F-READ-02: настройки показа страницы выключенная ступенька запаса не держит
02:19 +3097 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране книга и подпись нарисованы
02:19 +3098 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране в узком поле рисунок остаётся
02:19 +3099 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране без места указателя нет вовсе
02:19 +3100 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране поверх страницы указатель получает подложку
02:19 +3101 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц в начале книги слева ничего, справа вся толщина
02:19 +3102 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц к концу книги стопки меняются местами
02:19 +3103 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц левая растёт, а правая тает — и сумма постоянна
02:19 +3104 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц брошюра и том выглядят по-разному
02:19 +3105 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: «Устройство» — раздел, а не экран поверх полки
02:19 +3106 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: «Устройство» — раздел, а не экран поверх полки
02:20 +3107 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:20 +3108 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
02:21 +3109 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: поиск и отмеченное переживают уход из раздела
02:21 +3110 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: поиск и отмеченное переживают уход из раздела
02:21 +3111 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
02:21 +3112 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: полка помнит место прокрутки
02:22 +3113 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: полка помнит место прокрутки
02:22 +3114 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: «+» категории ведёт в раздел и называет её
02:22 +3115 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: категорию можно снять; кнопка шапки её не зовёт
02:22 +3116 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: три раздела F-APP-02: «назад» из раздела ведёт на полку
02:22 +3117 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: навигация на широком окне F-APP-02: от 900 точек разделы стоят наверху
02:23 +3118 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: навигация на широком окне F-APP-02: окно сузили — навигация внизу, раздел тот же
02:23 +3119 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: обход и открытая книга F-APP-02: пока книгу читают, обход устройства стоит
02:23 +3120 ~28: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_sections_test.dart: F-APP-02: обход и открытая книга SNO-F-IDX-04: пока книгу читают, проход по полке стоит
02:23 +3121 ~28: All tests passed!
```

## sno
```
�оды между разделами, показ полки и смена темы — в журнале
00:40 +695 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:40 +696 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:40 +697 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:40 +698 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:40 +699 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:40 +700 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:40 +701 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:40 +702 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:40 +703 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:40 +704 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:40 +705 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:40 +706 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:40 +707 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:40 +708 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:40 +709 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_wires_test.dart: SNO-F-REC-02: приложение в сборе SNO-F-REC-02: переходы между разделами, показ полки и смена темы — в журнале
00:41 +710 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-02: вне записи SNO-F-REC-02: записи нет — ни одна строка не пишется
00:41 +711 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: запись создана — часы, журнал, снимок
00:41 +712 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-LIB-02: запись началась — полка под замком
00:41 +713 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: сброс к эталону перед записью попадает в журнал
00:41 +714 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: вторая запись без сброса — видно в журнале
00:41 +715 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: старт — t = 0, сколько бы ни отвечала база
00:41 +716 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-LIB-02: выбранный до старта порядок полки записан
00:41 +717 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-LIB-02: порядок «Как расставил» замком не меняется
00:41 +718 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: вторая запись поверх идущей не начинается
00:41 +719 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: папка записи не завелась — записи нет
00:41 +720 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: настройки не пишутся — записи нет
00:41 +721 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: отметка сессии не записалась — призрака не остаётся
00:41 +722 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: два старта разом — запись одна
00:41 +723 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: старт записи SNO-F-REC-01: две записи в одну минуту — две папки
00:41 +724 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-02: журнал записи SNO-ALG-REC-01: сердцебиение — раз в десять секунд
00:41 +725 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-02: журнал записи SNO-F-REC-02: номера событий сквозные, время не убывает
00:41 +726 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-02: журнал записи SNO-F-REC-02: в событии — экран, на котором участник
00:41 +727 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-02: журнал записи SNO-F-REC-02: на диск журнал уходит каждую секунду
00:41 +728 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: через 40:00 запись останавливается сама
00:41 +729 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: сорок минут — по настенным часам: сон устройства запись не растягивает
00:41 +730 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: часы перевели назад — запись всё равно кончается через сорок минут
00:41 +731 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: экспериментатор останавливает раньше
00:41 +732 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: часы перевели назад — длительность и показ времени не обнуляются
00:41 +733 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: короткий сон записи не останавливает
00:41 +734 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-02: данные, которые не пишутся в JSON, номера не сбивают
00:41 +735 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: остановка дважды — одна
00:41 +736 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: уход в фон и возврат — пара событий и сверка часов
00:41 +737 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: остановка дописывает своё на диск — её можно дождаться
00:41 +738 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: сорок минут и остановка SNO-F-REC-01: об отказе диска при остановке узнают слушатели
00:41 +739 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: завершение сессии SNO-F-CFG-05: сессия завершена — замок снят, код забыт
00:41 +740 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: завершение сессии SNO-F-CFG-05: пока запись идёт, сессию не завершить
00:41 +741 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: завершение сессии SNO-F-CFG-05: завершение дожидается остановки
00:41 +742 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: завершение сессии SNO-F-CFG-05: отметка сессии не удалилась — замок всё равно снят
00:41 +743 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: завершение сессии SNO-F-CFG-05: следующий старт выдаёт новый код
00:41 +744 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: завершение сессии SNO-F-CFG-05: введённый код записан как введённый
00:41 +745 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: есть ли незавершённая сессия, известно только после прочитанной отметки
00:41 +746 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: новая запись после непрочитанной отметки — отметка о сессии снова своя
00:41 +747 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-01: запись, которую застал перезапуск, закрыта как оборванная
00:41 +748 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: остановка легла в журнал, отметка — нет: вторая остановка не пишется
00:41 +749 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: отметка сессии отстала от журнала — номер продолжает журнал
00:41 +750 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: последняя строка журнала — мусор: счёт берётся у читаемой
00:41 +751 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: сон устройства входит в длительность оборванной записи
00:41 +752 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: часы перевели назад, потом сбой — длительность не обнуляется
00:41 +753 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-08: в журнале и остановка, и завершение, а отметка отстала на оба — второй остановки нет
00:41 +754 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-CFG-03: остановленная сессия переживает перезапуск
00:41 +755 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-01: сессии нет — поднимать нечего
00:41 +756 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-01: испорченная отметка замка не оставляет
00:41 +757 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-01: журнал оборванной записи пропал — сессия всё равно закрывается
00:41 +758 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-01: отказ диска помнится и после перезапуска
00:41 +759 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: перезапуск приложения SNO-F-REC-01: отметка сессии помнит, лёг ли журнал на диск
00:41 +760 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-ALG-REC-03: снимок конца записи SNO-ALG-REC-03: остановка кладёт снимок конца в папку записи
00:41 +761 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-ALG-REC-03: снимок конца записи SNO-ALG-REC-03: снимок конца не назван — берётся тот же, что снимок начала
00:41 +762 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-ALG-REC-03: снимок конца записи SNO-ALG-REC-03: снимок не снялся — так в нём и сказано, запись останавливается
00:41 +763 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-ALG-REC-03: снимок конца записи SNO-ALG-REC-03: у оборванной записи снимок конца снят при следующем запуске и так помечен
00:41 +764 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-ALG-REC-03: снимок конца записи SNO-ALG-REC-03: снимок, снятый вовремя, следующий запуск не затирает
00:41 +765 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-ALG-REC-03: снимок конца записи SNO-ALG-REC-03: журнал не прочитался — снимок, снятый вовремя, всё равно остаётся
00:41 +766 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: готовность устройства SNO-F-REC-01: мало заряда и места — предупреждение
00:41 +767 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: готовность устройства SNO-F-REC-01: хватает — предупреждать не о чем
00:41 +768 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: готовность устройства SNO-F-REC-01: устройство молчит — это не «мало»
00:41 +769 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: имена и запись состояния SNO-F-REC-01: папка записи названа ветвью, кодом, устройством и временем
00:41 +770 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: имена и запись состояния SNO-F-REC-01: время записи словами
00:41 +771 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: имена и запись состояния SNO-F-REC-01: идентификатор записи растёт со временем
00:41 +772 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-REC-01: имена и запись состояния SNO-F-REC-01: состояние сессии читается обратно
00:41 +773 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: сброс к эталону и запись SNO-ALG-CFG-03: сброс не трогает список выданных кодов
00:42 +774 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: сброс к эталону и запись SNO-F-REC-01: отметки записи — не след читателя: снимок с эталоном совпадает
00:42 +775 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/recording_session_test.dart: SNO-F-CFG-05: сброс к эталону и запись SNO-F-REC-01: снимок без эталона так и говорит
00:42 +776 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: экран завершения SNO-F-REC-13: под числом событий сказано, что запись цела
00:42 +777 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: экран завершения SNO-F-REC-11: рядом сказано, цел ли поток ввода
00:42 +778 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: экран завершения SNO-F-REC-11: строки ввода не легли на диск — сказано, что ввод неполон
00:42 +779 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: экран завершения SNO-F-REC-13: неполная запись названа неполной, а сессия завершается
00:42 +780 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:42 +781 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:42 +782 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:43 +783 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:43 +784 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:43 +785 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:43 +786 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:43 +787 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: в разделе код устройства
00:43 +788 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: список записей на телефоне SNO-F-REC-13: запись с копией удаляется одним вопросом, без копии и без отправки — двумя
00:43 +789 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: блок «Для экспериментатора» свёрнут
00:43 +790 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: список записей на телефоне SNO-F-REC-13: копию убрали из «Загрузок» — запись удаляется только вторым подтверждением
00:43 +791 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: список записей на телефоне SNO-F-REC-13: копию убрали из «Загрузок» — запись удаляется только вторым подтверждением
00:43 +792 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: раздел «Тестирование» SNO-F-CFG-03: пунктов-заглушек в разделе нет
00:43 +793 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: отметка о копии без сверки SNO-F-REC-13: телефон, которому сверить копию нечем, одним подтверждением запись не удаляет
00:43 +794 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: пока блок свёрнут, устройство не обходится
00:43 +795 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: «Тестирование» и уведомления SNO-F-REC-13: уведомления разрешены — раздел молчит
00:43 +796 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: «Тестирование» и уведомления SNO-F-REC-13: уведомления разрешены — раздел молчит
00:43 +797 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: архив из списка уходит в ту же распаковку
00:43 +798 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: архив из списка уходит в ту же распаковку
00:44 +799 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: «Тестирование» и уведомления SNO-F-REC-13: разрешение спрашивается перед первой записью, отказ старту не мешает
00:44 +800 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: архивов нет — сказано словами
00:44 +801 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/survival_screens_test.dart: SNO-F-REC-13: «Тестирование» и уведомления SNO-F-REC-13: разрешили — строки об уведомлениях больше нет
00:44 +802 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: пока идёт обход, найденное уже в списке
00:44 +803 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: пока идёт обход, найденное уже в списке
00:44 +804 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: пока идёт обход, найденное уже в списке
00:44 +805 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: нажатие достаётся архиву, а не месту в списке
00:44 +806 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: начатый раньше поиск новому не мешает
00:44 +807 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: «Искать заново» останавливает прежний обход
00:44 +808 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: раздел закрыли — обход остановлен
00:44 +809 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: «Искать заново» обходит устройство ещё раз
00:44 +810 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: «Искать заново» обходит устройство ещё раз
00:44 +811 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: «Искать заново» обходит устройство ещё раз
00:44 +812 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: «Искать заново» обходит устройство ещё раз
00:44 +813 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: «Искать заново» обходит устройство ещё раз
00:44 +814 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/participant_code_test.dart: SNO-ALG-CFG-03: код из входов SNO-ALG-CFG-03: первая цифра не ноль, цифр всегда семь
00:44 +815 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: оборванный обход назван, найденное остаётся
00:44 +816 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/participant_code_test.dart: SNO-ALG-CFG-03: ошибки почерка SNO-ALG-CFG-03: одна неверная цифра и перестановка соседних ловятся на 10 000 кодов
00:44 +817 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: на ПК доступ не нужен и не просится
00:44 +818 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: на ПК доступ не нужен и не просится
00:44 +819 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: на ПК доступ не нужен и не просится
00:44 +820 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: на ПК доступ не нужен и не просится
00:44 +821 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: на ПК доступ не нужен и не просится
00:44 +822 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: архивы находятся на устройстве сами SNO-F-LIT-03: на ПК доступ не нужен и не просится
00:44 +823 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/participant_code_test.dart: SNO-F-CFG-05: запись кода SNO-F-CFG-05: испорченная запись кода не читается
00:44 +824 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: без доступа обхода нет, запрос — по кнопке
00:44 +825 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: без доступа обхода нет, запрос — по кнопке
00:44 +826 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: без доступа обхода нет, запрос — по кнопке
00:44 +827 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: отказали — запрос сам не повторяется
00:45 +828 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-03: доступ к файлам на телефоне SNO-F-LIT-03: вернулись в приложение — обход не повторён
00:45 +829 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: PDF вместо архива на полку не встаёт
00:45 +830 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: PDF и архив вместе — встаёт только архив
00:45 +831 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: кнопка и подписи книг не обещают
00:45 +832 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: книга узнаётся по имени файла
00:45 +833 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: отказ называет книги и говорит, как надо
00:45 +834 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-02: свои PDF не добавляются SNO-F-LIT-02: поимённо названы три книги, остальные числом
00:45 +835 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: архив распаковывается, итог — окном
00:45 +836 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: диалог закрыли — ничего не случилось
00:45 +837 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
00:45 +838 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
00:45 +839 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
00:45 +840 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
00:45 +841 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
00:45 +842 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
00:45 +843 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
00:45 +844 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
00:45 +845 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
00:45 +846 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
00:45 +847 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
00:45 +848 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
00:45 +849 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
00:45 +849 ~4: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/flags_test.dart: SNO-ALG-CFG-01: флаги этой сборки SNO-F-CFG-01: в сборке без SNO_BRANCH флаги ветви выключены
  Skip: прогон ветви: проверяется основным
00:45 +849 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: ход распаковки виден над списком
00:45 +850 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: пока архив открывается, это и сказано
00:45 +851 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: второе нажатие второй диалог не открывает
00:45 +852 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: сбой распаковки итога не съедает
00:45 +853 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: не-архив получает отказ от распаковки
00:45 +854 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: архив с книгами SNO-F-LIT-01: два архива — итог у каждого свой
00:46 +855 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/record_report_test.dart: SNO-F-RES-03: поход на полку из архива приложения
00:46 +856 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/record_report_test.dart: SNO-F-RES-03: поход на полку из архива приложения
00:46 +857 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: разложенный архив запоминается эталоном
00:46 +858 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: удержание сбрасывает к эталону
00:46 +859 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс BUG-67: «Забыть эталон» удержанием — эталона нет, архив запомнится новым
00:46 +860 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: отпустили раньше — ничего не произошло
00:46 +861 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: пока идёт распаковка, сброс выключен
00:46 +862 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: вернулись в раздел — сверка заново
00:46 +863 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-04: эталонное состояние и сброс SNO-F-CFG-04: отказанный архив эталоном не становится
00:46 +864 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: книги и категории сосчитаны
00:46 +865 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: без папок категорий нет и в словах
00:46 +866 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: тот же архив ещё раз
00:46 +867 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: часть была, часть встала, часть не открылась
00:46 +868 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: отказ архива и остановка названы
00:46 +869 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-LIT-01: что сказать после архива SNO-F-LIT-01: причина движка сказана своими словами
00:46 +870 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/testing_screen_test.dart: SNO-F-CFG-03: код устройства SNO-F-CFG-03: первые шесть знаков идентификатора узла
00:46 +871 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: зона за краем прокрутки SNO-F-REC-03: строки запаса прокрутки в кадр не попадают, подрезанная краем — видимой частью и с пометкой
00:47 +872 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: зона за краем прокрутки SNO-F-REC-03: прокрутка — кадры «в движении» не чаще пяти в секунду и один устоявшийся; строка под шапкой подрезана сверху
00:47 +873 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/shelf_reading_log_test.dart: SNO-F-IDX-04: смена дела и каждая прочитанная книга — строкой, страницы — нет
00:47 +874 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: в кадре полка со сдвигом прокрутки, шапки и участки категорий с названием, книги с отпечатком и категорией
00:47 +875 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: в кадре полка со сдвигом прокрутки, шапки и участки категорий с названием, книги с отпечатком и категорией
00:47 +876 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: в кадре полка со сдвигом прокрутки, шапки и участки категорий с названием, книги с отпечатком и категорией
00:47 +877 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: в кадре полка со сдвигом прокрутки, шапки и участки категорий с названием, книги с отпечатком и категорией
00:47 +878 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: в кадре полка со сдвигом прокрутки, шапки и участки категорий с названием, книги с отпечатком и категорией
00:47 +879 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: полку прокрутили — сдвиг в кадре тот же, что у списка, книги уехали вместе с ним
00:47 +880 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: касание книги лежит по кадру в зоне этой книги — той, что её открыла
00:48 +881 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +882 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +883 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +884 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +885 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +886 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +887 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +888 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +889 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +890 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +891 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +892 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +893 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +894 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +895 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +896 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +897 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +898 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +899 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +900 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +901 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +902 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +903 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +904 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +905 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +906 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +907 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: полка SNO-F-REC-03: поиск по названию на телефоне — поле и строки найденного с местом в списке; полки под списком в кадре нет
00:48 +908 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/load_test_test.dart: SNO-F-CLT-03: тест в записи при завершении сессии SNO-F-CLT-03: итоговая часть не окончена — так и записано, а данные ответы посчитаны
00:48 +909 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: карта «Галактика» SNO-F-REC-03: в кадре — раздел, полотно с камерой и всеми видимыми звёздами на их местах
00:48 +910 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: карта «Галактика» SNO-F-REC-03: в кадре — раздел, полотно с камерой и всеми видимыми звёздами на их местах
00:48 +911 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: карта «Галактика» SNO-F-REC-03: в кадре — раздел, полотно с камерой и всеми видимыми звёздами на их местах
00:48 +912 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: карта «Галактика» SNO-F-REC-03: в кадре — раздел, полотно с камерой и всеми видимыми звёздами на их местах
00:48 +913 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: карта «Галактика» SNO-F-REC-03: в кадре — раздел, полотно с камерой и всеми видимыми звёздами на их местах
00:48 +914 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: карта «Галактика» SNO-F-REC-03: касание звезды — по кадру её отпечаток; открытая карточка — зона поверх карты
00:49 +915 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/layout_screens_test.dart: SNO-F-REC-03: карта «Галактика» SNO-F-REC-03: перенос приближенной карты — кадры «в движении» и один устоявшийся с новой камерой
00:49 +916 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: тег сборки исследования SNO-F-CFG-06: тег исследования — sno2026-N и sno2026-N.M
00:49 +917 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: тег сборки исследования SNO-F-CFG-06: остальное тегом исследования не считается
00:49 +918 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: тег сборки исследования SNO-F-CFG-06: строка «О ветви» называет сборку и день
00:49 +919 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: тег сборки исследования SNO-F-CFG-06: сборка без тега — проверочная
00:49 +920 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: «Тестирование» на сборке исследования SNO-F-CFG-06: проверочная сборка сказана над стартом
00:50 +921 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: «Тестирование» на сборке исследования SNO-F-CFG-06: проверочная сборка сказана над стартом
00:50 +922 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: «Тестирование» на сборке исследования SNO-F-CFG-06: проверочная сборка сказана над стартом
00:50 +923 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: «Тестирование» на сборке исследования SNO-F-CFG-06: проверочная сборка сказана над стартом
00:50 +924 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/study_build_test.dart: SNO-F-CFG-06: «Тестирование» на сборке исследования SNO-F-CFG-06: на сборке исследования пометки нет
00:50 +925 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: один сценарий действий даёт в ветвях I и II одни события с одними полями и одни файлы записи
00:53 +926 ~5: /home/runner/work/MemoriaLLM/MemoriaLLM/test/sno/branch_parity_test.dart: SNO-F-REC-17: только ветвь II пишет события карты и подготовки книг — и больше никаких
00:53 +927 ~5: All tests passed!
```

## sessions
```
Running build hooks...Running build hooks...Проверен PROGRESS.md; плана нет (../docs/dev_plan_sessions.md) — пропущен.
Номера сессий в порядке.
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
746 passed in 1550.77s (0:25:50)
```

## eye-windows
```
Collecting absl-py==2.5.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 4))
  Downloading absl_py-2.5.0-py3-none-any.whl (137 kB)
Collecting av==19.0.1 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 6))
  Downloading av-19.0.1-cp312-abi3-win_amd64.whl (28.1 MB)
     ---------------------------------------- 28.1/28.1 MB 26.9 MB/s  0:00:01
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
     ---------------------------------------- 2.5/2.5 MB 76.3 MB/s  0:00:00
Collecting kiwisolver==1.5.1 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 27))
  Downloading kiwisolver-1.5.1-cp313-cp313-win_amd64.whl (70 kB)
Collecting matplotlib==3.11.2 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 30))
  Downloading matplotlib-3.11.2-cp313-cp313-win_amd64.whl (9.3 MB)
     ---------------------------------------- 9.3/9.3 MB 99.8 MB/s  0:00:00
Collecting mediapipe==1.1.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 33))
  Downloading mediapipe-1.1.0-py3-none-win_amd64.whl (22.4 MB)
     ---------------------------------------- 22.4/22.4 MB 75.5 MB/s  0:00:00
Collecting numpy==2.5.3 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 36))
  Downloading numpy-2.5.3-cp313-cp313-win_amd64.whl (12.6 MB)
     ---------------------------------------- 12.6/12.6 MB 101.8 MB/s  0:00:00
Collecting opencv-contrib-python==5.0.0.93 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 39))
  Downloading opencv_contrib_python-5.0.0.93-cp37-abi3-win_amd64.whl (53.8 MB)
     ---------------------------------------- 53.8/53.8 MB 53.9 MB/s  0:00:00
Collecting packaging==26.3 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 42))
  Downloading packaging-26.3-py3-none-any.whl (129 kB)
Collecting pillow==12.3.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 44))
  Downloading pillow-12.3.0-cp313-cp313-win_amd64.whl (7.2 MB)
     ---------------------------------------- 7.2/7.2 MB 52.5 MB/s  0:00:00
Collecting psutil==7.2.2 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 47))
  Downloading psutil-7.2.2-cp37-abi3-win_amd64.whl (137 kB)
Collecting pycparser==3.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 50))
  Downloading pycparser-3.0-py3-none-any.whl (48 kB)
Collecting pyparsing==3.3.3 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 52))
  Downloading pyparsing-3.3.3-py3-none-any.whl (126 kB)
Collecting pypdfium2==5.13.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 54))
  Downloading pypdfium2-5.13.0-py3-none-win_amd64.whl (3.9 MB)
     ---------------------------------------- 3.9/3.9 MB 109.2 MB/s  0:00:00
Collecting python-dateutil==2.9.0.post0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 57))
  Downloading python_dateutil-2.9.0.post0-py2.py3-none-any.whl (229 kB)
Collecting six==1.17.0 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 59))
  Downloading six-1.17.0-py2.py3-none-any.whl (11 kB)
Collecting sounddevice==0.5.6 (from -r D:\a\MemoriaLLM\MemoriaLLM\eye\requirements.lock (line 61))
  Downloading sounddevice-0.5.6-py3-none-win_amd64.whl (1.0 MB)
     ---------------------------------------- 1.0/1.0 MB 31.7 MB/s  0:00:00
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
2026-10-13 21:29:47,761 matplotlib.font_manager generated new fontManager
WARNING: Logging before InitGoogle() is written to STDERR
W0000 00:00:1791926988.192659    4912 face_landmarker_graph.cc:180] Sets FaceBlendshapesGraph acceleration to xnnpack by default.
INFO: Created TensorFlow Lite XNNPACK delegate for CPU.
W0000 00:00:1791926988.204192    6456 inference_feedback_manager.cc:121] Feedback manager requires a model with a single signature inference. Disabling support for feedback tensors.
W0000 00:00:1791926988.215754    9944 inference_feedback_manager.cc:121] Feedback manager requires a model with a single signature inference. Disabling support for feedback tensors.
```

## Сеть за пробу
tcp 0.0.0.0:0
tcp 172.217.117.4:443
dns c.pki.goog
dns ocsp.pki.goog
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
