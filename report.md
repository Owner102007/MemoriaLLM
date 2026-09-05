# Прогон CI №91

- коммит: `e290db637acb784b8c5994da8312a62716025bf4`
- ветка: `main`
- анализ и тесты: **success**
- сборка APK: **success**
- сборка Windows: **success**
- страница прогона:
  https://github.com/Owner102007/MemoriaLLM/actions/runs/33977719184

## analyze
```
Analyzing MemoriaLLM...                                         
No issues found! (ran in 17.0s)
```

## codegen
```
  compiling builders/aot
  34s compiling builders/aot
  0s drift_dev on 604 inputs; lib/application/app_services.dart
  13s drift_dev on 604 inputs: 1 output; spent 9s analyzing, 2s resolving, 1s sdk; lib/application/build_info.dart
  14s drift_dev on 604 inputs: 156 output, 1 no-op; spent 10s analyzing, 2s resolving, 1s sdk; lib/application/reading/document_search.dart
  15s drift_dev on 604 inputs: 179 output, 20 no-op; spent 11s analyzing, 2s resolving, 1s sdk; lib/infrastructure/files/android_book_storage.dart
  16s drift_dev on 604 inputs: 151 skipped, 281 output, 172 no-op; spent 11s analyzing, 2s resolving, 1s sdk
  0s source_gen:combining_builder on 302 inputs; lib/application/app_services.dart
  0s source_gen:combining_builder on 302 inputs: 151 skipped, 1 output, 150 no-op
  Built with build_runner/aot in 50s; wrote 282 outputs.
```

## tests
```
agments_test.dart: граница проходит между строк без просветов граница остаётся у середины
00:25 +506: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: граница проходит между строк без просвета строка повторяется, а не теряется
00:25 +507: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: граница проходит между строк нахлёста нет там, где просвет нашёлся
00:25 +508: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: граница проходит между строк далёкий просвет границу не утаскивает
00:25 +509: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: граница проходит между строк полосы по-прежнему стыкуются без щели и без повтора
00:25 +510: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: число фрагментов совпадает с тем, что вернуло деление
00:25 +511: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: число фрагментов дробь на кнопке равна числу полос
00:25 +512: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: смена режима не теряет место верхняя половина остаётся верхом при переходе на треть
00:25 +513: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: смена режима не теряет место нижняя половина попадает в нижнюю треть
00:25 +514: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: смена режима не теряет место середина трети попадает в ту же половину
00:25 +515: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: смена режима не теряет место переход на страницу целиком всегда даёт нулевой фрагмент
00:25 +516: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: смена режима не теряет место мусорный номер фрагмента не выводит за диапазон
00:25 +517: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: смена режима не теряет место обратный переход возвращает примерно туда же
00:25 +518: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: разворот первая страница стоит одна, дальше идут пары
00:25 +519: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: разворот последняя страница без пары показывается одна
00:25 +520: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: разворот края книги не ломают пару
00:25 +521: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: разворот половина разворота делит его по горизонтали
00:25 +522: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: разворот разворот и его половина показывают по две страницы
00:25 +523: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: деление и форма области показа — одно решение целая страница читается вертикально
00:25 +524: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: деление и форма области показа — одно решение половина просит альбом и увеличивает текст
00:25 +525: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: деление и форма области показа — одно решение треть увеличивает вдвое
00:25 +526: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: деление и форма области показа — одно решение альбомная страница считается по своей форме
00:25 +527: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: деление и форма области показа — одно решение выбранное положение экрана — лучшее из двух
00:25 +528: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: деление и форма области показа — одно решение узкое высокое окно не даёт выигрыша полосам
00:25 +529: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: деление и форма области показа — одно решение разворот не гасится за отсутствие выигрыша
00:25 +530: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: деление и форма области показа — одно решение неизмеренная область не запрещает ничего
00:25 +531: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: деление и форма области показа — одно решение бессмысленный лист не роняет выбор
00:25 +532: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: форма области показа стороны переставляются по длине, а не как попало
00:25 +533: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: форма области показа неизмеренная область так и говорит
00:25 +534: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: ради чего всё затевалось: текст должен стать крупнее половина на вертикальном экране не даёт ничего
00:25 +535: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: ради чего всё затевалось: текст должен стать крупнее половина на горизонтальном экране крупнее
00:25 +536: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: ради чего всё затевалось: текст должен стать крупнее треть на горизонтальном экране крупнее вдвое
00:25 +537: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/fragments_test.dart: ради чего всё затевалось: текст должен стать крупнее бессмысленные размеры дают ноль, а не бесконечность
00:25 +538: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_frames_test.dart: страница с текстом разбирается по тексту
00:25 +539: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_frames_test.dart: двухколоночная страница отдаёт две колонки
00:25 +540: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_frames_test.dart: страница без текста разбирается по пикселям
00:25 +541: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_frames_test.dart: одинокий номер страницы за текстовый слой не считается
00:25 +542: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_frames_test.dart: рамка считается один раз, а не в каждом кадре
00:25 +543: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_frames_test.dart: два одновременных запроса не считают страницу дважды
00:25 +544: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_frames_test.dart: смена настроек обрезки забывает посчитанное
00:25 +545: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_frames_test.dart: те же настройки кэш не сбрасывают
00:25 +546: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_frames_test.dart: кэш не растёт бесконечно
00:26 +547: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/page_frames_test.dart: страница за краем книги даёт страницу целиком
00:26 +548: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: clampPage оставляет страницу внутри книги
00:26 +549: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: clampPage прижимает к краям вместо ошибки
00:26 +550: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: clampPage книга без страниц не роняет арифметику
00:26 +551: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: progressForPage первая страница уже что-то, последняя — ровно всё
00:26 +552: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: progressForPage растёт монотонно и не выходит за единицу
00:26 +553: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: progressForPage смещение внутри страницы только увеличивает прогресс
00:26 +554: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: progressForPage мусорные значения не ломают счёт
00:26 +555: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: pageForProgress обратна progressForPage
00:26 +556: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: pageForProgress края ведут себя предсказуемо
00:26 +557: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: restorePage книгу без позиции открываем с первой страницы
00:26 +558: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: restorePage позиция возвращает туда, где остановились
00:26 +559: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: restorePage позиция за краем прижимается к концу, а не к началу
00:26 +560: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: шаги и подписи на краях книги шаг никуда не уводит
00:26 +561: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: шаги и подписи подпись страницы
00:26 +562: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: шаги и подписи проценты
00:26 +563: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: positionForPage собирает позицию с прогрессом
00:26 +564: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/navigation_test.dart: positionForPage страница за краем прижимается вместе с прогрессом
00:27 +565: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +566: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +567: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +568: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +569: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +570: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +571: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +572: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +573: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +574: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +575: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +576: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +577: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +578: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +579: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +580: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +581: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +582: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +583: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +584: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +585: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +586: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +587: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +588: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +589: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +590: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +591: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +592: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +593: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +594: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +595: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +596: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +597: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +598: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +599: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:27 +600: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: файл недоступен — книга ждёт, а не пропадает
00:28 +601: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_relink_test.dart: повреждённый файл перевыбором не лечится
00:28 +602: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели по умолчанию не видно ничего, кроме страницы
00:28 +603: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели по умолчанию не видно ничего, кроме страницы
00:28 +604: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели по умолчанию не видно ничего, кроме страницы
00:28 +605: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели по умолчанию не видно ничего, кроме страницы
00:28 +606: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели по умолчанию не видно ничего, кроме страницы
00:28 +607: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели по умолчанию не видно ничего, кроме страницы
00:28 +608: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели по умолчанию не видно ничего, кроме страницы
00:28 +609: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели по умолчанию не видно ничего, кроме страницы
00:28 +610: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели по умолчанию не видно ничего, кроме страницы
00:28 +611: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели по умолчанию не видно ничего, кроме страницы
00:28 +612: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели по умолчанию не видно ничего, кроме страницы
00:29 +613: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: панели нажатие в середину показывает и прячет панели
00:29 +614: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: навигация счётчик страниц следует за просмотрщиком
00:29 +615: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:29 +616: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:29 +617: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:30 +618: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:30 +619: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:30 +620: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: разворот переключается и запоминается
00:30 +621: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: оглавление книга без оглавления объясняет, почему его нет
00:30 +622: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: половина и треть из панели уехали в чтение
00:30 +623: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
00:30 +624: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
00:30 +625: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск показывает найденное и переводит на страницу
00:31 +626: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: автообрезка выключена по умолчанию и включается
00:31 +627: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_scaffold_test.dart: поиск пустой результат так и написан
00:31 +628: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: ручная правка рамки открывается кнопкой
00:31 +629: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: кнопка сброса рамки появляется только при ручной рамке
00:31 +630: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: про двухколоночную страницу сказано прямо
00:31 +631: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: способ листания переехал в настройки
00:31 +632: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: затемнение есть в панели и меняется ползунком
00:31 +633: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: сказано, зачем режимы поворачивают экран
00:32 +634: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_settings_sheet_test.dart: яркость, контраст и гамма меняются ползунками
00:32 +635: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране книга и подпись нарисованы
00:32 +636: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране книга и подпись нарисованы
00:32 +637: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране в узком поле рисунок остаётся
00:32 +638: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране без места указателя нет вовсе
00:32 +639: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: рисунок на экране поверх страницы указатель получает подложку
00:32 +640: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц в начале книги слева ничего, справа вся толщина
00:32 +641: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц к концу книги стопки меняются местами
00:32 +642: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц левая растёт, а правая тает — и сумма постоянна
00:32 +643: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц брошюра и том выглядят по-разному
00:32 +644: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_progress_book_test.dart: стопки страниц мусорный объём не ломает рисунок
00:32 +645: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:33 +646: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:33 +647: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:33 +648: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:33 +649: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:33 +650: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_editor_test.dart: рамка возвращается той же, если её не трогали
00:33 +651: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:33 +652: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:34 +653: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:34 +654: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:34 +655: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:34 +656: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции быстрое листание не пишет в базу на каждой странице
00:34 +657: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:35 +658: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:35 +659: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:35 +660: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:35 +661: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:35 +662: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: сохранение позиции долгое листание доходит до базы, не дожидаясь остановки
00:35 +663: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/dim_outside_test.dart: нулевое затемнение ничего не рисует
00:35 +664: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/dim_outside_test.dart: нулевое затемнение ничего не рисует
00:35 +665: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/dim_outside_test.dart: нулевое затемнение ничего не рисует
00:35 +666: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/dim_outside_test.dart: нулевое затемнение ничего не рисует
00:35 +667: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/dim_outside_test.dart: нулевое затемнение ничего не рисует
00:35 +668: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/dim_outside_test.dart: нулевое затемнение ничего не рисует
00:35 +669: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/dim_outside_test.dart: нулевое затемнение ничего не рисует
00:35 +670: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/dim_outside_test.dart: нулевое затемнение ничего не рисует
00:35 +671: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: подписи счётчик страниц и прогресс
00:35 +672: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/dim_outside_test.dart: тень не перехватывает нажатия по странице
00:35 +673: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/dim_outside_test.dart: тень не перехватывает нажатия по странице
00:35 +674: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/dim_outside_test.dart: тень не перехватывает нажатия по странице
00:35 +675: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/dim_outside_test.dart: тень не перехватывает нажатия по странице
00:35 +676: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/dim_outside_test.dart: тень не перехватывает нажатия по странице
00:35 +677: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/dim_outside_test.dart: тень не перехватывает нажатия по странице
00:35 +678: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка режим отображения переживает переоткрытие книги
00:35 +679: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка настройки книги одни на все положения экрана
00:35 +680: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка половина просит альбом в одноколоночной книге
00:35 +681: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка половина просит альбом в двухколоночной книге
00:35 +682: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка режим без выигрыша не включается и не молчит
00:35 +683: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка пока область показа не измерена, не запрещается ничего
00:35 +684: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка разворот не гасится за отсутствие выигрыша в кегле
00:35 +685: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка разворот на обложке остаётся одной страницей
00:35 +686: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка половина разворота делит его по горизонтали
00:35 +687: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка фрагменты листаются вперёд и переходят на страницу
00:35 +688: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка назад читатель попадает в низ предыдущей страницы
00:35 +689: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка на краях книги листание упирается, а не ломается
00:35 +690: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка в базу пишется и страница, и фрагмент
00:35 +691: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка ручная рамка главнее автообрезки и снимается сбросом
00:35 +692: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка вывернутая ручная рамка не принимается
00:35 +693: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка колонтитулы можно вернуть в содержимое
00:35 +694: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка запас по краям запоминается и не выходит за предел
00:35 +695: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка затемнение запоминается и не доходит до черноты
00:35 +696: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reader_controller_test.dart: читательская рамка светофильтр собирается из настроек книги
00:36 +697: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/progress_slot_test.dart: в вертикальном чтении указатель ложится под страницу
00:36 +698: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/progress_slot_test.dart: в горизонтальном чтении указатель встаёт сбоку
00:36 +699: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/progress_slot_test.dart: когда поля нет, указатель честно признаётся, что лёг поверх
00:36 +700: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/progress_slot_test.dart: узкая щель указателю не годится
00:36 +701: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/progress_slot_test.dart: указатель всегда внутри экрана
00:36 +702: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по тексту поля обрезаются, содержимое остаётся внутри
00:36 +703: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по тексту ни один символ не остаётся за рамкой
00:36 +704: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по тексту без текста рамка — страница целиком
00:36 +705: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по тексту одно слово посреди листа не растягивается на весь экран
00:36 +706: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: колонтитулы оторванные строки сверху и снизу не считаются содержимым
00:36 +707: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: колонтитулы если колонтитулы считать содержимым, рамка растёт
00:36 +708: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: колонтитулы на короткой странице ничего не выбрасывается
00:36 +709: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по пикселям тёмный прямоугольник на белом листе находится
00:36 +710: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по пикселям одинокая пылинка на поле рамку не растягивает
00:36 +711: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по пикселям чистый лист — страница целиком, а не вывернутая рамка
00:36 +712: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по пикселям светлый текст на тёмном фоне обрезается так же
00:36 +713: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: рамка по пикселям несогласованный растр не роняет обрезку
00:36 +714: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: просветы скана найдены все просветы между строками, и только они
00:36 +715: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: просветы скана каждый просвет лежит между строками, а не на строке
00:36 +716: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: просветы скана у скана без строк просветов нет, и это не ошибка
00:36 +717: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: просветы скана несогласованный растр не даёт ни рамки, ни просветов
00:36 +718: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: просветы скана по этим просветам страница делится между строк
00:36 +719: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: нормализация вывернутая рамка превращается в страницу целиком
00:36 +720: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: нормализация рамка никогда не выходит за страницу
00:36 +721: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: нормализация бесконечности не проходят
00:36 +722: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: какая рамка в итоге показывается по умолчанию поля не режутся
00:36 +723: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: какая рамка в итоге показывается с включённой обрезкой показывается содержимое
00:36 +724: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: какая рамка в итоге показывается ручная рамка главнее автоматической
00:36 +725: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: какая рамка в итоге показывается испорченная автоматическая рамка не показывается
00:36 +726: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: строки символы разных кеглей в строке не разбегаются
00:36 +727: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: строки строки идут сверху вниз
00:36 +728: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/crop_test.dart: строки мусорные прямоугольники выбрасываются
00:37 +729: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица таблица не пустая
00:37 +730: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица none: сила 0.0, яркость 1.0, контраст 1.0, гамма 1.0
00:37 +731: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица nightRed: сила 0.9, яркость 1.0, контраст 1.0, гамма 1.0
00:37 +732: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица nightRed: сила 0.5, яркость 1.0, контраст 1.0, гамма 1.0
00:37 +733: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица warm: сила 0.6, яркость 1.0, контраст 1.0, гамма 1.0
00:37 +734: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица sepia: сила 0.8, яркость 1.0, контраст 1.0, гамма 1.0
00:37 +735: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица invert: сила 1.0, яркость 1.0, контраст 1.0, гамма 1.0
00:37 +736: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица none: сила 0.0, яркость 1.0, контраст 1.0, гамма 1.4
00:37 +737: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица none: сила 0.0, яркость 1.0, контраст 1.5, гамма 1.0
00:37 +738: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица none: сила 0.0, яркость 0.4, контраст 1.0, гамма 1.0
00:37 +739: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица nightRed: сила 0.9, яркость 0.5, контраст 1.2, гамма 1.3
00:37 +740: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: эталонная таблица invert: сила 1.0, яркость 0.8, контраст 1.4, гамма 0.8
00:37 +741: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров ночной красный оставляет только красную составляющую
00:37 +742: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров тёплый гасит синее сильнее зелёного
00:37 +743: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров инверсия переворачивает текст и бумагу
00:37 +744: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров цветная картинка при инверсии остаётся собой
00:37 +745: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров гамма темнит середину, не трогая края
00:37 +746: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров яркость ниже системного минимума, но не в ноль
00:37 +747: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров ничего не настроено — фильтр ничего и не делает
00:37 +748: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров выбранный фильтр сразу заметен
00:37 +749: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: смысл фильтров гамма и инверсия требуют шейдера, остальное — нет
00:37 +750: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: запасная цветовая матрица при гамме 1 совпадает с эталоном
00:37 +751: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: запасная цветовая матрица приближение гаммы точно в единице
00:37 +752: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: запасная цветовая матрица матрица уложена так, как её ждёт движок
00:37 +753: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером объявлены те же uniform и в том же порядке
00:37 +754: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером первый uniform — vec2, как требует движок
00:37 +755: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером сэмплер страницы назван так же, как в коде
00:37 +756: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером число значений совпадает с числом uniform после размера
00:37 +757: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером номера фильтров в шейдере совпадают с порядком в перечислении
00:37 +758: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: договор с шейдером ось Y перевёрнута для OpenGL ES
00:37 +759: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/reading_filter_test.dart: фильтр собирается из настроек книги
00:37 +760: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: двухколоночная страница делится по колонкам
00:37 +761: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: сплошной текст остаётся одной колонкой
00:37 +762: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: титульный лист в три строки на колонки не разбирается
00:37 +763: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: просвет у самого края колонкой не считается
00:37 +764: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: пустой список — одна колонка во всю рамку
00:37 +765: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/columns_test.dart: колонки не залезают в межколоночное поле
00:38 +766: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:38 +767: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:38 +768: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:38 +769: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:38 +770: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:38 +771: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:38 +772: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:38 +773: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:38 +774: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:38 +775: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:38 +776: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:38 +777: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:38 +778: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:38 +779: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: обе дроби есть прямо в чтении
00:38 +780: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +781: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +782: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +783: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +784: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +785: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +786: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +787: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +788: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +789: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +790: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +791: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +792: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +793: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +794: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +795: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +796: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +797: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +798: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +799: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +800: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +801: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +802: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +803: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +804: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +805: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +806: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +807: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +808: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +809: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +810: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +811: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +812: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +813: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +814: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь включает свой режим
00:38 +815: /home/runner/work/MemoriaLLM/MemoriaLLM/test/theme_contrast_test.dart: читаемость тем Светлая основной текст читается на фоне и на поверхности
00:38 +816: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: повторное нажатие возвращает страницу целиком
00:38 +817: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: повторное нажатие возвращает страницу целиком
00:38 +818: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: повторное нажатие возвращает страницу целиком
00:38 +819: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: повторное нажатие возвращает страницу целиком
00:38 +820: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: повторное нажатие возвращает страницу целиком
00:38 +821: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: повторное нажатие возвращает страницу целиком
00:38 +822: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: повторное нажатие возвращает страницу целиком
00:38 +823: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: чужая дробь переключает режим, а не выключает его
00:38 +824: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: включённый режим видно по кнопке
00:39 +825: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: разворот не гасит кнопки: из него тоже делят страницу
00:39 +826: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: дробь без выигрыша говорит об этом заранее
00:39 +827: /home/runner/work/MemoriaLLM/MemoriaLLM/test/reading/display_mode_buttons_test.dart: погасшая дробь всё-таки нажимается
00:39 +828: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: приложение запускается на экране библиотеки
00:40 +829: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: по умолчанию включена тёмно-красная тема
00:40 +830: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: смена темы в настройках перекрашивает приложение
00:41 +831: /home/runner/work/MemoriaLLM/MemoriaLLM/test/app_smoke_test.dart: на пустой полке предложено добавить книги
00:41 +832: All tests passed!
```
