# Прогон CI №111

- коммит: `0ed1a00082c18f361a6f92869be07b8ba5d6257a`
- ветка: `main`
- анализ и тесты: **success**
- сборка APK: **success**
- сборка Windows: **success**
- страница прогона:
  https://github.com/Owner102007/MemoriaLLM/actions/runs/34760972076

## analyze
```
Resolving dependencies...
Downloading packages...
  cli_util 0.5.2 (0.6.0 available)
  flutter_lints 5.0.0 (6.0.0 available)
  lints 5.1.1 (6.1.0 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  sqlite3_flutter_libs 0.5.42 (0.6.0+eol available)
  test_api 0.7.12 (0.7.14 available)
Got dependencies!
6 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing MemoriaLLM...                                         
No issues found! (ran in 15.2s)
```

## codegen
```
  compiling builders/aot
  30s compiling builders/aot
  0s drift_dev on 728 inputs; lib/application/app_services.dart
  12s drift_dev on 728 inputs: 1 output; spent 9s analyzing, 2s resolving, 1s sdk; lib/application/build_info.dart
  14s drift_dev on 728 inputs: 213 output, 21 no-op; spent 10s analyzing, 2s resolving, 1s sdk; lib/infrastructure/database/connection.dart
  15s drift_dev on 728 inputs: 51 skipped, 340 output, 76 no-op; spent 11s analyzing, 2s resolving, 1s sdk; lib/infrastructure/database/app_database.dart.types.temp.dart
  15s drift_dev on 728 inputs: 182 skipped, 340 output, 206 no-op; spent 11s analyzing, 2s resolving, 1s sdk
  0s source_gen:combining_builder on 364 inputs; lib/application/app_services.dart
  0s source_gen:combining_builder on 364 inputs: 182 skipped, 1 output, 181 no-op
  Built with build_runner/aot in 46s; wrote 341 outputs.
```

## tests
```
�оловина страницы половины стыкуются ровно и ничего не повторяют
00:38 +688: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: разворот две страницы рядом вписаны в горизонтальный экран
00:38 +689: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: разворот разворот на вертикальном экране мельче, чем на горизонтальном
00:38 +690: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: масштаб не зависит ни от чего, кроме листа и экрана одна и та же страница в одном режиме — один и тот же масштаб
00:38 +691: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: масштаб не зависит ни от чего, кроме листа и экрана страницы разного размера дают разный масштаб, но обе целиком
00:38 +692: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: запас по краям уменьшение отодвигает полосу от краёв экрана
00:38 +693: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: запас по краям вплотную окно совпадает с той стороной, которой не хватало
00:38 +694: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: запас по краям читаемая полоса не выходит за экран
00:38 +695: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: запас по краям затемнённая часть листа остаётся за краем экрана
00:38 +696: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: запас по краям мельче предела полоса не уменьшается
00:38 +697: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: запас по краям запас не меняет того, какая часть листа показана
00:38 +698: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: бессмыслица не ломает экран нулевой лист или экран — показывать нечего
00:38 +699: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: бессмыслица не ломает экран вывернутый фрагмент — показывать нечего
00:38 +700: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: бессмыслица не ломает экран у пустой раскладки нет и полосы
00:38 +701: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: замок и масштаб нетронутый масштаб узнаётся с поправкой на пальцы
00:38 +702: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: замок и масштаб осознанный масштаб замок обязан сохранить
00:39 +703: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели по умолчанию не видно ничего, кроме страницы
00:39 +704: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/document_search_test.dart: находит слово и указывает страницу
00:39 +705: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:39 +706: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:39 +707: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:39 +708: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:39 +709: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +710: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +711: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +712: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +713: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +714: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +715: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация счётчик страниц следует за просмотрщиком
00:40 +716: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация кнопки шага переводят на соседние страницы
00:40 +717: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
00:40 +718: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация ползунок переводит на выбранную страницу
00:40 +719: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация книга из одной страницы обходится без ползунка
00:40 +720: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление открывается и переводит на выбранный раздел
00:40 +721: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:41 +722: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:41 +723: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:41 +724: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:41 +725: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:41 +726: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:41 +727: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:41 +728: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура Ctrl+F открывает поиск, Esc его закрывает
00:41 +729: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: половина и треть из панели уехали в чтение
00:41 +730: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: половина и треть из панели уехали в чтение
00:41 +731: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 ведёт по совпадениям по кругу
00:41 +732: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: выбранный фильтр сразу получает заметную силу
00:41 +733: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: выбранный фильтр сразу получает заметную силу
00:42 +734: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура пробел и Backspace в поле поиска принадлежат полю
00:42 +735: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: ползунка силы нет, пока нет фильтра
00:42 +736: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: ползунка силы нет, пока нет фильтра
00:42 +737: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура без найденного F3 молчит
00:42 +738: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: автообрезка выключена по умолчанию и включается
00:42 +739: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: ручная правка рамки открывается кнопкой
00:42 +740: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: кнопка сброса рамки появляется только при ручной рамке
00:42 +741: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: про двухколоночную страницу сказано прямо
00:42 +742: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: способ листания переехал в настройки
00:42 +743: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: затемнение есть в панели и меняется ползунком
00:42 +744: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: сказано, зачем режимы поворачивают экран
00:42 +745: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: яркость, контраст и гамма меняются ползунками
00:42 +746: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: запас по краям есть в панели и меняется ползунком
00:43 +747: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране книга и подпись нарисованы
00:43 +748: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране в узком поле рисунок остаётся
00:43 +749: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране без места указателя нет вовсе
00:43 +750: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране поверх страницы указатель получает подложку
00:43 +751: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц в начале книги слева ничего, справа вся толщина
00:43 +752: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц к концу книги стопки меняются местами
00:43 +753: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц левая растёт, а правая тает — и сумма постоянна
00:43 +754: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц брошюра и том выглядят по-разному
00:43 +755: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц мусорный объём не ломает рисунок
00:44 +756: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:44 +757: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:44 +758: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:44 +759: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:44 +760: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:44 +761: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:44 +762: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:44 +763: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:44 +764: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:44 +765: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:44 +766: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:44 +767: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: маска целиком нулевое затемнение не гасит страницу, но соседей прячет
00:44 +768: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: маска целиком нулевое затемнение не гасит страницу, но соседей прячет
00:44 +769: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: маска целиком нулевое затемнение не гасит страницу, но соседей прячет
00:45 +770: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: маска целиком нулевое затемнение не гасит страницу, но соседей прячет
00:45 +771: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: сброс возвращает страницу целиком
00:45 +772: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: маска целиком маска не перехватывает нажатия по странице
00:45 +773: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: сказано, что рамка ляжет на всю книгу
00:46 +774: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: листание вперёд листают стрелки, пробел и PageDown
00:46 +775: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: листание назад листают стрелки, PageUp и Shift+пробел
00:46 +776: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: листание клавиши листают и при выделенном тексте
00:46 +777: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск Ctrl+F открывает поиск
00:46 +778: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск Ctrl с чем угодно другим ничего не значит
00:46 +779: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск F3 ведёт по совпадениям, а Shift+F3 — назад
00:46 +780: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск F3 без найденного молчит
00:46 +781: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск Enter — следующее совпадение, только пока ищут
00:46 +782: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: Esc закрывает то, что открыто
00:46 +783: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: обычная буква не значит ничего
00:46 +784: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст пробел и Backspace принадлежат полю, а не книге
00:46 +785: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст и стрелки с Page тоже: ими двигают курсор
00:46 +786: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст Enter в поле разбирает само поле
00:46 +787: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст Esc оставлен панели поиска: ей ближе
00:46 +788: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст F3 и Ctrl+F поле не ждёт никогда — они работают
00:46 +789: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: открытие книги книга без истории открывается с первой страницы
00:46 +790: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: открытие книги книга с историей открывается там, где её оставили
00:46 +791: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: открытие книги позиция за краем книги прижимается к последней странице
00:46 +792: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: открытие книги нечитаемый файл не открывается и не течёт
00:46 +793: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции место записывается в базу и переживает переоткрытие
00:46 +794: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:47 +795: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:47 +796: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:47 +797: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:47 +798: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:47 +799: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:47 +800: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:48 +801: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:48 +802: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:48 +803: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:48 +804: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:48 +805: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:48 +806: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:48 +807: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:48 +808: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:48 +809: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции flush записывает немедленно
00:48 +810: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции без изменений в базу не пишем
00:48 +811: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции страница за краем не попадает в базу как есть
00:48 +812: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: оглавление читается один раз и запоминается
00:48 +813: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: оглавление испорченное оглавление не мешает читать книгу
00:48 +814: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: закрытие документ закрывается вместе с контроллером
00:48 +815: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: закрытие повторное закрытие безвредно
00:48 +816: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: подписи счётчик страниц и прогресс
00:48 +817: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка по умолчанию показывается вся страница, с полями
00:48 +818: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка включённая обрезка срезает поля
00:48 +819: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка половина страницы вдвое ниже целой
00:48 +820: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка на двухколоночной странице половина — верх страницы
00:48 +821: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка смена режима не теряет место на странице
00:48 +822: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка режим отображения переживает переоткрытие книги
00:48 +823: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка настройки книги одни на все положения экрана
00:48 +824: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка половина просит альбом в одноколоночной книге
00:48 +825: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка половина просит альбом в двухколоночной книге
00:48 +826: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка режим без выигрыша не включается и не молчит
00:48 +827: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка пока область показа не измерена, не запрещается ничего
00:48 +828: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка разворот не гасится за отсутствие выигрыша в кегле
00:48 +829: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка разворот на обложке остаётся одной страницей
00:48 +830: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка половина разворота делит его по горизонтали
00:48 +831: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка фрагменты листаются вперёд и переходят на страницу
00:48 +832: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка назад читатель попадает в низ предыдущей страницы
00:48 +833: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка на краях книги листание упирается, а не ломается
00:48 +834: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка в базу пишется и страница, и фрагмент
00:48 +835: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка ручная рамка главнее автообрезки и снимается сбросом
00:48 +836: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка вывернутая ручная рамка не принимается
00:48 +837: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка колонтитулы можно вернуть в содержимое
00:48 +838: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка запас по краям запоминается и не выходит за предел
00:48 +839: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка затемнение запоминается и не доходит до черноты
00:48 +840: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка светофильтр собирается из настроек книги
00:49 +841: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по тексту поля обрезаются, содержимое остаётся внутри
00:49 +842: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по тексту ни один символ не остаётся за рамкой
00:49 +843: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по тексту без текста рамка — страница целиком
00:49 +844: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по тексту одно слово посреди листа не растягивается на весь экран
00:49 +845: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: колонтитулы оторванные строки сверху и снизу не считаются содержимым
00:49 +846: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: колонтитулы если колонтитулы считать содержимым, рамка растёт
00:49 +847: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: колонтитулы на короткой странице ничего не выбрасывается
00:49 +848: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по пикселям тёмный прямоугольник на белом листе находится
00:49 +849: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по пикселям одинокая пылинка на поле рамку не растягивает
00:49 +850: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по пикселям чистый лист — страница целиком, а не вывернутая рамка
00:49 +851: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по пикселям светлый текст на тёмном фоне обрезается так же
00:49 +852: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по пикселям несогласованный растр не роняет обрезку
00:49 +853: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: просветы скана найдены все просветы между строками, и только они
00:49 +854: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: просветы скана каждый просвет лежит между строками, а не на строке
00:49 +855: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: просветы скана у скана без строк просветов нет, и это не ошибка
00:49 +856: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: просветы скана несогласованный растр не даёт ни рамки, ни просветов
00:49 +857: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: просветы скана по этим просветам страница делится между строк
00:49 +858: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: нормализация вывернутая рамка превращается в страницу целиком
00:49 +859: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: нормализация рамка никогда не выходит за страницу
00:49 +860: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: нормализация бесконечности не проходят
00:49 +861: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: какая рамка в итоге показывается по умолчанию поля не режутся
00:49 +862: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: какая рамка в итоге показывается с включённой обрезкой показывается содержимое
00:49 +863: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: какая рамка в итоге показывается ручная рамка главнее автоматической
00:49 +864: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: какая рамка в итоге показывается испорченная автоматическая рамка не показывается
00:49 +865: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: строки символы разных кеглей в строке не разбегаются
00:49 +866: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: строки строки идут сверху вниз
00:49 +867: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: строки мусорные прямоугольники выбрасываются
00:49 +868: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица таблица не пустая
00:49 +869: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица none: сила 0.0, яркость 1.0, контраст 1.0, гамма 1.0
00:49 +870: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица nightRed: сила 0.9, яркость 1.0, контраст 1.0, гамма 1.0
00:49 +871: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица nightRed: сила 0.5, яркость 1.0, контраст 1.0, гамма 1.0
00:49 +872: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица warm: сила 0.6, яркость 1.0, контраст 1.0, гамма 1.0
00:49 +873: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица sepia: сила 0.8, яркость 1.0, контраст 1.0, гамма 1.0
00:49 +874: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица invert: сила 1.0, яркость 1.0, контраст 1.0, гамма 1.0
00:49 +875: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица none: сила 0.0, яркость 1.0, контраст 1.0, гамма 1.4
00:49 +876: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица none: сила 0.0, яркость 1.0, контраст 1.5, гамма 1.0
00:49 +877: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица none: сила 0.0, яркость 0.4, контраст 1.0, гамма 1.0
00:49 +878: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица nightRed: сила 0.9, яркость 0.5, контраст 1.2, гамма 1.3
00:49 +879: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица invert: сила 1.0, яркость 0.8, контраст 1.4, гамма 0.8
00:49 +880: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров ночной красный оставляет только красную составляющую
00:49 +881: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров тёплый гасит синее сильнее зелёного
00:49 +882: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров инверсия переворачивает текст и бумагу
00:49 +883: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров цветная картинка при инверсии остаётся собой
00:49 +884: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров гамма темнит середину, не трогая края
00:49 +885: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров яркость ниже системного минимума, но не в ноль
00:49 +886: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров ничего не настроено — фильтр ничего и не делает
00:49 +887: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров выбранный фильтр сразу заметен
00:49 +888: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров гамма и инверсия требуют шейдера, остальное — нет
00:49 +889: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: запасная цветовая матрица при гамме 1 совпадает с эталоном
00:49 +890: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: запасная цветовая матрица приближение гаммы точно в единице
00:49 +891: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: запасная цветовая матрица матрица уложена так, как её ждёт движок
00:49 +892: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером объявлены те же uniform и в том же порядке
00:49 +893: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером первый uniform — vec2, как требует движок
00:49 +894: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером сэмплер страницы назван так же, как в коде
00:49 +895: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером число значений совпадает с числом uniform после размера
00:50 +896: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером номера фильтров в шейдере совпадают с порядком в перечислении
00:50 +897: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером ось Y перевёрнута для OpenGL ES
00:50 +898: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: фильтр собирается из настроек книги
00:50 +899: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: прямоугольники подсветки на каждую строку — один прямоугольник, а не на каждую букву
00:50 +900: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: прямоугольники подсветки прямоугольник тянется на всю высоту строки
00:50 +901: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: прямоугольники подсветки пустой кусок ничего не подсвечивает
00:50 +902: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: прямоугольники подсветки подсветка не выходит за пределы страницы
00:50 +903: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: слово вокруг места палец в середине слова берёт слово целиком
00:50 +904: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: слово вокруг места палец в пробел берёт слово слева
00:50 +905: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: слово вокруг места дефис внутри слова слово не разрезает
00:50 +906: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: слово вокруг места строка из одних знаков препинания слова не даёт
00:50 +907: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: слово вокруг места иероглиф считается словом
00:50 +908: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: двухколоночная страница делится по колонкам
00:50 +909: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: сплошной текст остаётся одной колонкой
00:50 +910: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: титульный лист в три строки на колонки не разбирается
00:50 +911: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: просвет у самого края колонкой не считается
00:50 +912: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: пустой список — одна колонка во всю рамку
00:50 +913: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: колонки не залезают в межколоночное поле
00:51 +914: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:51 +915: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:51 +916: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:51 +917: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:51 +918: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:51 +919: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:51 +920: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:51 +921: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:51 +922: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:51 +923: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:51 +924: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_search_test.dart: findInPageText многоточия появляются только там, где текст обрезан
00:51 +925: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:51 +926: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:51 +927: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:51 +928: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:52 +929: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: повторное нажатие возвращает страницу целиком
00:52 +930: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: чужая дробь переключает режим, а не выключает его
00:52 +931: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: включённый режим видно по кнопке
00:52 +932: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: разворот не гасит кнопки: из него тоже делят страницу
00:52 +933: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь без выигрыша говорит об этом заранее
00:52 +934: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: погасшая дробь всё-таки нажимается
00:52 +935: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/session_numbers_test.dart: настоящие файлы реестр в PROGRESS.md сходится
00:52 +936: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/session_numbers_test.dart: настоящие файлы план, если он рядом, сходится с реестром
00:52 +937: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/session_numbers_test.dart: битые примеры правильный реестр нарушений не даёт
00:52 +938: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/session_numbers_test.dart: битые примеры дважды выданный номер виден
00:52 +939: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/session_numbers_test.dart: битые примеры номер без статуса виден
00:52 +940: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/session_numbers_test.dart: битые примеры отсутствующий реестр виден
00:52 +941: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/session_numbers_test.dart: битые примеры номер из плана без строки статуса виден
00:52 +942: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/session_numbers_test.dart: битые примеры номер, объявленный в плане дважды, виден
00:52 +943: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/session_numbers_test.dart: битые примеры план без замечаний молчит
00:52 +944: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/session_numbers_test.dart: разбор реестр читается построчно с номерами строк
00:52 +945: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/session_numbers_test.dart: разбор заголовок таблицы и разделитель за номера не считаются
00:52 +946: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/session_numbers_test.dart: разбор объявления в плане находятся вместе со строками
00:52 +947: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/build_lock_test.dart: замок зависимостей pubspec.lock отслеживается git
00:52 +948: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/build_lock_test.dart: замок зависимостей в замке есть движок с точной версией
00:52 +949: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/build_lock_test.dart: версия Flutter записана в одном месте у композитного действия версия точная
00:52 +950: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/build_lock_test.dart: версия Flutter записана в одном месте напрямую ставит Flutter только канарейка
00:52 +951: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/build_lock_test.dart: версия Flutter записана в одном месте версия в действии — не канал
00:52 +952: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/build_lock_test.dart: CI не обновляет замок молча каждый pub get идёт с --enforce-lockfile
00:53 +953: /home/runner/work/MemoriaLLM/MemoriaLLM/test/tool/pdfium_version_test.dart: версия PDFium у нас и в хуке pdfium_dart совпадает
00:53 +954: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: расчёт контраста чёрный против белого даёт максимум 21:1
00:53 +955: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: расчёт контраста одинаковые цвета дают 1:1
00:53 +956: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: расчёт контраста порядок цветов не влияет на результат
00:53 +957: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: расчёт контраста яркость белого равна единице, чёрного — нулю
00:53 +958: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем в приложении есть все объявленные темы
00:53 +959: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем тема по умолчанию — тёмно-красная
00:53 +960: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Тёмно-красная основной текст читается на фоне и на поверхности
00:53 +961: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Тёмно-красная вторичный текст читается на фоне и на поверхности
00:53 +962: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Тёмно-красная акцентный текст читается
00:53 +963: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Тёмно-красная подпись на акцентной заливке читается
00:53 +964: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Тёмно-красная нажатый акцент виден на фоне
00:53 +965: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Тёмно-красная разделитель не сливается с фоном
00:53 +966: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Тёмно-красная цвета непрозрачные
00:53 +967: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Ночная красная основной текст читается на фоне и на поверхности
00:53 +968: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Ночная красная вторичный текст читается на фоне и на поверхности
00:53 +969: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Ночная красная акцентный текст читается
00:53 +970: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Ночная красная подпись на акцентной заливке читается
00:53 +971: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Ночная красная нажатый акцент виден на фоне
00:53 +972: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Ночная красная разделитель не сливается с фоном
00:53 +973: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Ночная красная цвета непрозрачные
00:53 +974: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Нейтральная тёмная основной текст читается на фоне и на поверхности
00:53 +975: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Нейтральная тёмная вторичный текст читается на фоне и на поверхности
00:53 +976: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Нейтральная тёмная акцентный текст читается
00:53 +977: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Нейтральная тёмная подпись на акцентной заливке читается
00:53 +978: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Нейтральная тёмная нажатый акцент виден на фоне
00:53 +979: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Нейтральная тёмная разделитель не сливается с фоном
00:53 +980: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Нейтральная тёмная цвета непрозрачные
00:53 +981: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Сепия основной текст читается на фоне и на поверхности
00:53 +982: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Сепия вторичный текст читается на фоне и на поверхности
00:53 +983: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Сепия акцентный текст читается
00:53 +984: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Сепия подпись на акцентной заливке читается
00:53 +985: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Сепия нажатый акцент виден на фоне
00:53 +986: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Сепия разделитель не сливается с фоном
00:53 +987: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Сепия цвета непрозрачные
00:53 +988: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Светлая основной текст читается на фоне и на поверхности
00:53 +989: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Светлая вторичный текст читается на фоне и на поверхности
00:53 +990: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Светлая акцентный текст читается
00:53 +991: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Светлая подпись на акцентной заливке читается
00:53 +992: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Светлая нажатый акцент виден на фоне
00:53 +993: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Светлая разделитель не сливается с фоном
00:53 +994: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Светлая цвета непрозрачные
00:54 +995: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
00:54 +996: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: по умолчанию включена тёмно-красная тема
00:55 +997: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
00:55 +998: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: на пустой полке предложено добавить книги
00:55 +999: All tests passed!
```

## sessions
```
Running build hooks...Running build hooks...Проверен PROGRESS.md; плана нет (../docs/dev_plan_sessions.md) — пропущен.
Номера сессий в порядке.
```
