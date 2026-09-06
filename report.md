# Прогон CI №108

- коммит: `0226818a279d1e58c07e4042a8dadf5b377e497e`
- ветка: `main`
- анализ и тесты: **success**
- сборка APK: **success**
- сборка Windows: **success**
- страница прогона:
  https://github.com/Owner102007/MemoriaLLM/actions/runs/34043900915

## analyze
```
Analyzing MemoriaLLM...                                         
No issues found! (ran in 15.4s)
```

## codegen
```
  compiling builders/aot
  30s compiling builders/aot
  0s drift_dev on 712 inputs; lib/application/app_services.dart
  11s drift_dev on 712 inputs: 1 output; spent 8s analyzing, 2s resolving, 1s sdk; lib/application/build_info.dart
  12s drift_dev on 712 inputs: 183 output, 1 no-op; spent 9s analyzing, 2s resolving, 1s sdk; lib/application/reading/book_selection.dart
  14s drift_dev on 712 inputs: 212 output, 22 no-op; spent 11s analyzing, 2s resolving, 1s sdk; lib/infrastructure/files/android_book_storage.dart
  14s drift_dev on 712 inputs: 178 skipped, 333 output, 201 no-op; spent 11s analyzing, 2s resolving, 1s sdk
  0s source_gen:combining_builder on 356 inputs; lib/application/app_services.dart
  0s source_gen:combining_builder on 356 inputs: 178 skipped, 1 output, 177 no-op
  Built with build_runner/aot in 45s; wrote 334 outputs.
```

## tests
```
�
00:39 +668: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/outline_test.dart: flattenOutline свёрнутое дерево показывает только верхний уровень
00:39 +669: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/outline_test.dart: flattenOutline развёрнутый узел показывает своих детей и только их
00:39 +670: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/outline_test.dart: flattenOutline expandAll показывает всё дерево
00:39 +671: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/outline_test.dart: flattenOutline идентификаторы — путь в дереве и они уникальны
00:39 +672: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/outline_test.dart: flattenOutline пустой заголовок не оставляет пустую строку в списке
00:39 +673: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/outline_test.dart: flattenOutline пункт без страницы виден, но не нажимается
00:39 +674: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/outline_test.dart: flattenOutline пустое оглавление даёт пустой список
00:39 +675: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/outline_test.dart: размеры дерева глубина и число узлов
00:39 +676: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/outline_test.dart: outlineIdsToDepth по умолчанию раскрывает только верхний уровень
00:39 +677: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/outline_test.dart: outlineIdsToDepth глубина два раскрывает и вторые уровни
00:39 +678: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/outline_test.dart: currentOutlineId подсвечивает раздел, в котором читатель находится
00:39 +679: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/outline_test.dart: currentOutlineId до первого пункта подсвечивать нечего
00:39 +680: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/outline_test.dart: currentOutlineId оглавления нет — подсветки нет
00:39 +681: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/outline_test.dart: outlineAncestors путь к пункту
00:39 +682: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: страница целиком вписывается в вертикальный экран без обрезки
00:39 +683: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: страница целиком занимает экран по узкой стороне, а не болтается в углу
00:39 +684: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: половина страницы на горизонтальном экране страница шире, чем в портрете
00:39 +685: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: половина страницы боковые поля не срезаны, срезан только низ
00:39 +686: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: половина страницы вторая половина показывает низ страницы
00:39 +687: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: половина страницы половины стыкуются ровно и ничего не повторяют
00:39 +688: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: разворот две страницы рядом вписаны в горизонтальный экран
00:39 +689: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: разворот разворот на вертикальном экране мельче, чем на горизонтальном
00:39 +690: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: масштаб не зависит ни от чего, кроме листа и экрана одна и та же страница в одном режиме — один и тот же масштаб
00:39 +691: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: масштаб не зависит ни от чего, кроме листа и экрана страницы разного размера дают разный масштаб, но обе целиком
00:39 +692: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: запас по краям уменьшение отодвигает полосу от краёв экрана
00:39 +693: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: запас по краям вплотную окно совпадает с той стороной, которой не хватало
00:39 +694: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: запас по краям читаемая полоса не выходит за экран
00:39 +695: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: запас по краям затемнённая часть листа остаётся за краем экрана
00:39 +696: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: запас по краям мельче предела полоса не уменьшается
00:39 +697: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: запас по краям запас не меняет того, какая часть листа показана
00:39 +698: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: бессмыслица не ломает экран нулевой лист или экран — показывать нечего
00:39 +699: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: бессмыслица не ломает экран вывернутый фрагмент — показывать нечего
00:39 +700: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: бессмыслица не ломает экран у пустой раскладки нет и полосы
00:39 +701: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: замок и масштаб нетронутый масштаб узнаётся с поправкой на пальцы
00:39 +702: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/sheet_placement_test.dart: замок и масштаб осознанный масштаб замок обязан сохранить
00:40 +703: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели по умолчанию не видно ничего, кроме страницы
00:40 +704: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +705: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +706: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +707: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +708: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +709: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +710: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +711: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +712: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +713: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:40 +714: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:41 +715: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация счётчик страниц следует за просмотрщиком
00:41 +716: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация кнопки шага переводят на соседние страницы
00:41 +717: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация на краях книги шагать некуда
00:41 +718: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация ползунок переводит на выбранную страницу
00:41 +719: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация книга из одной страницы обходится без ползунка
00:41 +720: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление открывается и переводит на выбранный раздел
00:41 +721: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:42 +722: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:42 +723: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:42 +724: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:42 +725: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:42 +726: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:42 +727: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:42 +728: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура Ctrl+F открывает поиск, Esc его закрывает
00:42 +729: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: половина и треть из панели уехали в чтение
00:42 +730: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: половина и треть из панели уехали в чтение
00:42 +731: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 ведёт по совпадениям по кругу
00:42 +732: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: выбранный фильтр сразу получает заметную силу
00:43 +733: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: выбранный фильтр сразу получает заметную силу
00:43 +734: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: выбранный фильтр сразу получает заметную силу
00:43 +735: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: клавиатура F3 работает и из поля: его поле не ждёт
00:43 +736: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: ползунка силы нет, пока нет фильтра
00:43 +737: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: ползунка силы нет, пока нет фильтра
00:43 +738: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: автообрезка выключена по умолчанию и включается
00:43 +739: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: ручная правка рамки открывается кнопкой
00:43 +740: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: кнопка сброса рамки появляется только при ручной рамке
00:43 +741: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: про двухколоночную страницу сказано прямо
00:43 +742: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: способ листания переехал в настройки
00:43 +743: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: затемнение есть в панели и меняется ползунком
00:43 +744: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: сказано, зачем режимы поворачивают экран
00:44 +745: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: яркость, контраст и гамма меняются ползунками
00:44 +746: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране книга и подпись нарисованы
00:44 +747: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране книга и подпись нарисованы
00:44 +748: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране в узком поле рисунок остаётся
00:44 +749: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране без места указателя нет вовсе
00:44 +750: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране поверх страницы указатель получает подложку
00:44 +751: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц в начале книги слева ничего, справа вся толщина
00:44 +752: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц к концу книги стопки меняются местами
00:44 +753: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц левая растёт, а правая тает — и сумма постоянна
00:44 +754: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц брошюра и том выглядят по-разному
00:44 +755: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц мусорный объём не ломает рисунок
00:45 +756: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:45 +757: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:45 +758: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:45 +759: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:45 +760: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:45 +761: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:45 +762: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:45 +763: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:45 +764: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:45 +765: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:45 +766: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:45 +767: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: маска целиком нулевое затемнение не гасит страницу, но соседей прячет
00:46 +768: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: маска целиком нулевое затемнение не гасит страницу, но соседей прячет
00:46 +769: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: маска целиком нулевое затемнение не гасит страницу, но соседей прячет
00:46 +770: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамку нельзя вывернуть наизнанку
00:46 +771: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_mask_test.dart: маска целиком маска не перехватывает нажатия по странице
00:46 +772: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: сброс возвращает страницу целиком
00:46 +773: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: сказано, что рамка ляжет на всю книгу
00:47 +774: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: листание вперёд листают стрелки, пробел и PageDown
00:47 +775: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: листание назад листают стрелки, PageUp и Shift+пробел
00:47 +776: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: листание клавиши листают и при выделенном тексте
00:47 +777: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск Ctrl+F открывает поиск
00:47 +778: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск Ctrl с чем угодно другим ничего не значит
00:47 +779: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск F3 ведёт по совпадениям, а Shift+F3 — назад
00:47 +780: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск F3 без найденного молчит
00:47 +781: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: поиск Enter — следующее совпадение, только пока ищут
00:47 +782: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: Esc закрывает то, что открыто
00:47 +783: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: обычная буква не значит ничего
00:47 +784: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст пробел и Backspace принадлежат полю, а не книге
00:47 +785: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст и стрелки с Page тоже: ими двигают курсор
00:47 +786: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст Enter в поле разбирает само поле
00:47 +787: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст Esc оставлен панели поиска: ей ближе
00:47 +788: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_keys_test.dart: пока читатель набирает текст F3 и Ctrl+F поле не ждёт никогда — они работают
00:47 +789: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: открытие книги книга без истории открывается с первой страницы
00:47 +790: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: открытие книги книга с историей открывается там, где её оставили
00:47 +791: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: открытие книги позиция за краем книги прижимается к последней странице
00:47 +792: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: открытие книги нечитаемый файл не открывается и не течёт
00:48 +793: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции место записывается в базу и переживает переоткрытие
00:48 +794: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:48 +795: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:48 +796: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:48 +797: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:48 +798: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:48 +799: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:48 +800: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:49 +801: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:49 +802: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:49 +803: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:49 +804: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:49 +805: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:49 +806: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:49 +807: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:49 +808: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:49 +809: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции flush записывает немедленно
00:49 +810: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции без изменений в базу не пишем
00:49 +811: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции страница за краем не попадает в базу как есть
00:49 +812: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: оглавление читается один раз и запоминается
00:49 +813: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: оглавление испорченное оглавление не мешает читать книгу
00:49 +814: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: закрытие документ закрывается вместе с контроллером
00:49 +815: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: закрытие повторное закрытие безвредно
00:49 +816: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: подписи счётчик страниц и прогресс
00:50 +817: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка по умолчанию показывается вся страница, с полями
00:50 +818: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка включённая обрезка срезает поля
00:50 +819: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка половина страницы вдвое ниже целой
00:50 +820: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка на двухколоночной странице половина — верх страницы
00:50 +821: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка смена режима не теряет место на странице
00:50 +822: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка режим отображения переживает переоткрытие книги
00:50 +823: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка настройки книги одни на все положения экрана
00:50 +824: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка половина просит альбом в одноколоночной книге
00:50 +825: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка половина просит альбом в двухколоночной книге
00:50 +826: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка режим без выигрыша не включается и не молчит
00:50 +827: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка пока область показа не измерена, не запрещается ничего
00:50 +828: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка разворот не гасится за отсутствие выигрыша в кегле
00:50 +829: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка разворот на обложке остаётся одной страницей
00:50 +830: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка половина разворота делит его по горизонтали
00:50 +831: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка фрагменты листаются вперёд и переходят на страницу
00:50 +832: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка назад читатель попадает в низ предыдущей страницы
00:50 +833: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка на краях книги листание упирается, а не ломается
00:50 +834: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка в базу пишется и страница, и фрагмент
00:50 +835: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка ручная рамка главнее автообрезки и снимается сбросом
00:50 +836: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка вывернутая ручная рамка не принимается
00:50 +837: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка колонтитулы можно вернуть в содержимое
00:50 +838: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка запас по краям запоминается и не выходит за предел
00:50 +839: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка затемнение запоминается и не доходит до черноты
00:50 +840: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка светофильтр собирается из настроек книги
00:50 +841: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по тексту поля обрезаются, содержимое остаётся внутри
00:50 +842: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по тексту ни один символ не остаётся за рамкой
00:50 +843: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по тексту без текста рамка — страница целиком
00:50 +844: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по тексту одно слово посреди листа не растягивается на весь экран
00:50 +845: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: колонтитулы оторванные строки сверху и снизу не считаются содержимым
00:50 +846: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: колонтитулы если колонтитулы считать содержимым, рамка растёт
00:50 +847: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: колонтитулы на короткой странице ничего не выбрасывается
00:50 +848: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по пикселям тёмный прямоугольник на белом листе находится
00:50 +849: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по пикселям одинокая пылинка на поле рамку не растягивает
00:50 +850: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по пикселям чистый лист — страница целиком, а не вывернутая рамка
00:50 +851: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по пикселям светлый текст на тёмном фоне обрезается так же
00:50 +852: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по пикселям несогласованный растр не роняет обрезку
00:50 +853: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: просветы скана найдены все просветы между строками, и только они
00:50 +854: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: просветы скана каждый просвет лежит между строками, а не на строке
00:50 +855: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: просветы скана у скана без строк просветов нет, и это не ошибка
00:50 +856: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: просветы скана несогласованный растр не даёт ни рамки, ни просветов
00:50 +857: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: просветы скана по этим просветам страница делится между строк
00:50 +858: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: нормализация вывернутая рамка превращается в страницу целиком
00:50 +859: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: нормализация рамка никогда не выходит за страницу
00:50 +860: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: нормализация бесконечности не проходят
00:50 +861: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: какая рамка в итоге показывается по умолчанию поля не режутся
00:50 +862: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: какая рамка в итоге показывается с включённой обрезкой показывается содержимое
00:50 +863: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: какая рамка в итоге показывается ручная рамка главнее автоматической
00:50 +864: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: какая рамка в итоге показывается испорченная автоматическая рамка не показывается
00:50 +865: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: строки символы разных кеглей в строке не разбегаются
00:50 +866: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: строки строки идут сверху вниз
00:50 +867: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: строки мусорные прямоугольники выбрасываются
00:51 +868: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица таблица не пустая
00:51 +869: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица none: сила 0.0, яркость 1.0, контраст 1.0, гамма 1.0
00:51 +870: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица nightRed: сила 0.9, яркость 1.0, контраст 1.0, гамма 1.0
00:51 +871: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица nightRed: сила 0.5, яркость 1.0, контраст 1.0, гамма 1.0
00:51 +872: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица warm: сила 0.6, яркость 1.0, контраст 1.0, гамма 1.0
00:51 +873: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица sepia: сила 0.8, яркость 1.0, контраст 1.0, гамма 1.0
00:51 +874: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица invert: сила 1.0, яркость 1.0, контраст 1.0, гамма 1.0
00:51 +875: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица none: сила 0.0, яркость 1.0, контраст 1.0, гамма 1.4
00:51 +876: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица none: сила 0.0, яркость 1.0, контраст 1.5, гамма 1.0
00:51 +877: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица none: сила 0.0, яркость 0.4, контраст 1.0, гамма 1.0
00:51 +878: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица nightRed: сила 0.9, яркость 0.5, контраст 1.2, гамма 1.3
00:51 +879: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица invert: сила 1.0, яркость 0.8, контраст 1.4, гамма 0.8
00:51 +880: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров ночной красный оставляет только красную составляющую
00:51 +881: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров тёплый гасит синее сильнее зелёного
00:51 +882: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров инверсия переворачивает текст и бумагу
00:51 +883: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров цветная картинка при инверсии остаётся собой
00:51 +884: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров гамма темнит середину, не трогая края
00:51 +885: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров яркость ниже системного минимума, но не в ноль
00:51 +886: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров ничего не настроено — фильтр ничего и не делает
00:51 +887: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров выбранный фильтр сразу заметен
00:51 +888: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров гамма и инверсия требуют шейдера, остальное — нет
00:51 +889: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: запасная цветовая матрица при гамме 1 совпадает с эталоном
00:51 +890: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: запасная цветовая матрица приближение гаммы точно в единице
00:51 +891: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: запасная цветовая матрица матрица уложена так, как её ждёт движок
00:51 +892: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером объявлены те же uniform и в том же порядке
00:51 +893: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером первый uniform — vec2, как требует движок
00:51 +894: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером сэмплер страницы назван так же, как в коде
00:51 +895: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером число значений совпадает с числом uniform после размера
00:51 +896: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером номера фильтров в шейдере совпадают с порядком в перечислении
00:51 +897: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером ось Y перевёрнута для OpenGL ES
00:51 +898: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: фильтр собирается из настроек книги
00:51 +899: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: прямоугольники подсветки на каждую строку — один прямоугольник, а не на каждую букву
00:51 +900: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: прямоугольники подсветки прямоугольник тянется на всю высоту строки
00:51 +901: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: прямоугольники подсветки пустой кусок ничего не подсвечивает
00:51 +902: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: прямоугольники подсветки подсветка не выходит за пределы страницы
00:51 +903: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: слово вокруг места палец в середине слова берёт слово целиком
00:51 +904: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: слово вокруг места палец в пробел берёт слово слева
00:51 +905: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: слово вокруг места дефис внутри слова слово не разрезает
00:51 +906: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: слово вокруг места строка из одних знаков препинания слова не даёт
00:51 +907: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_highlight_test.dart: слово вокруг места иероглиф считается словом
00:52 +908: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: двухколоночная страница делится по колонкам
00:52 +909: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: сплошной текст остаётся одной колонкой
00:52 +910: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: титульный лист в три строки на колонки не разбирается
00:52 +911: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: просвет у самого края колонкой не считается
00:52 +912: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: пустой список — одна колонка во всю рамку
00:52 +913: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: колонки не залезают в межколоночное поле
00:52 +914: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:53 +915: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/text_search_test.dart: SearchableText схлопывает переносы и лишние пробелы
00:53 +916: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:53 +917: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:53 +918: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:53 +919: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:53 +920: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:53 +921: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:53 +922: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:53 +923: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:53 +924: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:53 +925: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:53 +926: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:53 +927: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:53 +928: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:53 +929: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: повторное нажатие возвращает страницу целиком
00:53 +930: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: чужая дробь переключает режим, а не выключает его
00:53 +931: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: включённый режим видно по кнопке
00:53 +932: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: разворот не гасит кнопки: из него тоже делят страницу
00:53 +933: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь без выигрыша говорит об этом заранее
00:53 +934: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: погасшая дробь всё-таки нажимается
00:54 +935: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: расчёт контраста чёрный против белого даёт максимум 21:1
00:54 +936: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: расчёт контраста одинаковые цвета дают 1:1
00:54 +937: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: расчёт контраста порядок цветов не влияет на результат
00:54 +938: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: расчёт контраста яркость белого равна единице, чёрного — нулю
00:54 +939: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем в приложении есть все объявленные темы
00:54 +940: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем тема по умолчанию — тёмно-красная
00:54 +941: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Тёмно-красная основной текст читается на фоне и на поверхности
00:54 +942: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Тёмно-красная вторичный текст читается на фоне и на поверхности
00:54 +943: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Тёмно-красная акцентный текст читается
00:54 +944: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Тёмно-красная подпись на акцентной заливке читается
00:54 +945: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Тёмно-красная нажатый акцент виден на фоне
00:54 +946: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Тёмно-красная разделитель не сливается с фоном
00:54 +947: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Тёмно-красная цвета непрозрачные
00:54 +948: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Ночная красная основной текст читается на фоне и на поверхности
00:54 +949: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Ночная красная вторичный текст читается на фоне и на поверхности
00:54 +950: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Ночная красная акцентный текст читается
00:54 +951: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Ночная красная подпись на акцентной заливке читается
00:54 +952: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Ночная красная нажатый акцент виден на фоне
00:54 +953: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Ночная красная разделитель не сливается с фоном
00:54 +954: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Ночная красная цвета непрозрачные
00:54 +955: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Нейтральная тёмная основной текст читается на фоне и на поверхности
00:54 +956: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Нейтральная тёмная вторичный текст читается на фоне и на поверхности
00:54 +957: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Нейтральная тёмная акцентный текст читается
00:54 +958: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Нейтральная тёмная подпись на акцентной заливке читается
00:54 +959: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Нейтральная тёмная нажатый акцент виден на фоне
00:54 +960: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Нейтральная тёмная разделитель не сливается с фоном
00:54 +961: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Нейтральная тёмная цвета непрозрачные
00:54 +962: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Сепия основной текст читается на фоне и на поверхности
00:54 +963: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Сепия вторичный текст читается на фоне и на поверхности
00:54 +964: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Сепия акцентный текст читается
00:54 +965: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Сепия подпись на акцентной заливке читается
00:54 +966: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Сепия нажатый акцент виден на фоне
00:54 +967: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Сепия разделитель не сливается с фоном
00:54 +968: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Сепия цвета непрозрачные
00:54 +969: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Светлая основной текст читается на фоне и на поверхности
00:54 +970: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Светлая вторичный текст читается на фоне и на поверхности
00:54 +971: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Светлая акцентный текст читается
00:54 +972: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Светлая подпись на акцентной заливке читается
00:54 +973: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Светлая нажатый акцент виден на фоне
00:54 +974: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Светлая разделитель не сливается с фоном
00:54 +975: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Светлая цвета непрозрачные
00:54 +976: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
00:55 +977: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: по умолчанию включена тёмно-красная тема
00:55 +978: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
00:56 +979: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: на пустой полке предложено добавить книги
00:56 +980: All tests passed!
```
