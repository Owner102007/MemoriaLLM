import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/library/shelf_title_search.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/domain/theme/app_palette.dart';
import 'package:memoria/domain/theme/contrast.dart';
import 'package:memoria/ui/library/library_screen.dart';
import 'package:memoria/ui/library/shelf_search.dart';
import 'package:memoria/ui/reader/reader_screen.dart';

import '../data/test_data.dart';
import '../support/test_services.dart';

/// SNO-F-LIB-01: поиск по названию на полке сборки ветви.
///
/// Полка получает признак параметром, поэтому проверяется одним
/// прогоном, без флагов сборки.
void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  Future<void> pumpShelf(
    WidgetTester tester,
    AppServices services, {
    bool titleSearch = true,
    bool models = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          services: services,
          canAddBooks: false,
          titleSearch: titleSearch,
          models: models,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Широкое окно: навигация наверху, поле поиска стоит в шапке.
  void wideWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Три книги: две в категориях, одна без.
  Future<void> threeBooks() async {
    await data.categories.save(
      BookCategory(
        id: 'pathology',
        title: 'Патология',
        position: 0,
        createdAt: DateTime.utc(2026, 8, 20),
      ),
    );
    await data.categories.save(
      BookCategory(
        id: 'anatomy',
        title: 'Анатомия',
        position: 1,
        createdAt: DateTime.utc(2026, 8, 20),
      ),
    );
    await data.library.save(
      testBook(id: 'pat', title: 'Патанатомия', hash: 'hash-pat'),
    );
    await data.library.save(
      testBook(
        id: 'prives',
        title: 'Привес. Анатомия человека',
        hash: 'hash-prives',
      ),
    );
    await data.library.save(
      testBook(id: 'hist', title: 'Гистология', hash: 'hash-hist'),
    );
    await placeBook(data, 'pat', 'pathology');
    await placeBook(data, 'prives', 'anatomy');
  }

  Future<void> type(WidgetTester tester, String query) async {
    await tester.enterText(find.byKey(const Key('shelf-search-field')), query);
    await tester.pumpAndSettle();
  }

  Finder hit(String id) => find.byKey(Key('shelf-search-hit-$id'));

  group('SNO-F-LIB-01: поиск по названию на телефоне', () {
    testWidgets('SNO-F-LIB-01: значок в шапке открывает поле', (
      WidgetTester tester,
    ) async {
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));

      expect(find.byKey(const Key('shelf-search-field')), findsNothing);
      await tester.tap(find.byKey(const Key('library-search')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shelf-search-field')), findsOneWidget);
      // Пока в поле пусто, на экране полка как есть.
      expect(find.byKey(const Key('library-shelf')), findsOneWidget);
      expect(find.byKey(const Key('shelf-search-results')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: с первой буквы полка сменяется списком', (
      WidgetTester tester,
    ) async {
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));
      await tester.tap(find.byKey(const Key('library-search')));
      await tester.pumpAndSettle();

      await type(tester, 'а');

      expect(find.byKey(const Key('shelf-search-results')), findsOneWidget);
      expect(find.byKey(const Key('library-shelf')), findsNothing);
      // «а» есть в названиях двух книг из трёх.
      expect(hit('prives'), findsOneWidget);
      expect(hit('pat'), findsOneWidget);
      expect(hit('hist'), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: начало слова стоит выше середины слова', (
      WidgetTester tester,
    ) async {
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));
      await tester.tap(find.byKey(const Key('library-search')));
      await tester.pumpAndSettle();

      // На полке «Патанатомия» стоит раньше; в списке — позже.
      await type(tester, 'АНАТ');

      expect(
        tester.getTopLeft(hit('prives')).dy,
        lessThan(tester.getTopLeft(hit('pat')).dy),
      );

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: под названием стоит категория книги', (
      WidgetTester tester,
    ) async {
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));
      await tester.tap(find.byKey(const Key('library-search')));
      await tester.pumpAndSettle();
      await type(tester, 'привес');

      expect(
        find.descendant(of: hit('prives'), matching: find.text('Анатомия')),
        findsOneWidget,
      );

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: нет совпадений — сказано словами', (
      WidgetTester tester,
    ) async {
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));
      await tester.tap(find.byKey(const Key('library-search')));
      await tester.pumpAndSettle();

      await type(tester, 'квант');
      expect(find.text('Ничего не найдено по названию'), findsOneWidget);
      expect(find.byKey(const Key('library-shelf')), findsNothing);

      // Запрос из одних знаков — тоже «ничего», а не вся полка.
      await type(tester, '...');
      expect(find.byKey(const Key('shelf-search-empty')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: «назад» и крестик возвращают полку', (
      WidgetTester tester,
    ) async {
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));

      await tester.tap(find.byKey(const Key('library-search')));
      await tester.pumpAndSettle();
      await type(tester, 'анат');
      await tester.tap(find.byKey(const Key('shelf-search-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shelf-search-field')), findsNothing);
      expect(find.byKey(const Key('library-shelf')), findsOneWidget);

      // Открытый заново поиск пуст: прежний запрос не вернулся.
      await tester.tap(find.byKey(const Key('library-search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shelf-search-results')), findsNothing);
      await type(tester, 'гист');
      expect(hit('hist'), findsOneWidget);
      await tester.tap(find.byKey(const Key('shelf-search-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shelf-search-field')), findsNothing);
      expect(find.byKey(const Key('library-shelf')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: системное «назад» закрывает поиск', (
      WidgetTester tester,
    ) async {
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));
      await tester.tap(find.byKey(const Key('library-search')));
      await tester.pumpAndSettle();
      await type(tester, 'анат');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Закрыт поиск, а не экран.
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(find.byKey(const Key('shelf-search-field')), findsNothing);
      expect(find.byKey(const Key('library-shelf')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: Esc в поле закрывает поиск', (
      WidgetTester tester,
    ) async {
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));
      await tester.tap(find.byKey(const Key('library-search')));
      await tester.pumpAndSettle();
      await type(tester, 'анат');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shelf-search-field')), findsNothing);
      expect(find.byKey(const Key('library-shelf')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: найденное открывает книгу, потом — полка', (
      WidgetTester tester,
    ) async {
      await data.settings.write(SettingsKeys.tapZoneHintSeen, 'true');
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));
      await tester.tap(find.byKey(const Key('library-search')));
      await tester.pumpAndSettle();
      await type(tester, 'гист');

      await tester.tap(hit('hist'));
      await tester.pumpAndSettle();
      final ReaderScreen reader = tester.widget(find.byType(ReaderScreen));
      expect(reader.book.id, 'hist');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Вернувшись, читатель видит полку, а не список найденного.
      expect(find.byType(ReaderScreen), findsNothing);
      expect(find.byKey(const Key('shelf-search-field')), findsNothing);
      expect(find.byKey(const Key('shelf-search-results')), findsNothing);
      expect(find.byKey(const Key('library-shelf')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: после поиска полка стоит там же', (
      WidgetTester tester,
    ) async {
      // Категорий больше, чем помещается на экране: полку можно
      // прокрутить.
      for (int i = 0; i < 8; i++) {
        await data.categories.save(
          BookCategory(
            id: 'c$i',
            title: 'Раздел $i',
            position: i,
            createdAt: DateTime.utc(2026, 8, 20),
          ),
        );
        await data.library.save(
          testBook(id: 'b$i', title: 'Том $i', hash: 'hash-b$i'),
        );
        await placeBook(data, 'b$i', 'c$i');
      }
      await pumpShelf(tester, testServices(data: data));

      double offset() {
        return tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byKey(const Key('library-shelf')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position
            .pixels;
      }

      await tester.drag(
        find.byKey(const Key('library-shelf')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      final double before = offset();
      expect(before, greaterThan(0));

      await tester.tap(find.byKey(const Key('library-search')));
      await tester.pumpAndSettle();
      await type(tester, 'том');
      expect(find.byKey(const Key('library-shelf')), findsNothing);
      await tester.tap(find.byKey(const Key('shelf-search-back')));
      await tester.pumpAndSettle();

      // Расположение книг участник запоминает: полка не прыгает в начало.
      expect(offset(), before);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: книга с полки закрывает открытое поле', (
      WidgetTester tester,
    ) async {
      await data.settings.write(SettingsKeys.tapZoneHintSeen, 'true');
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));
      // Поле открыто и пусто: на экране полка, и книгу открывают с неё.
      await tester.tap(find.byKey(const Key('library-search')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('library-book-hist')));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Вернулись к полке, а не к полю с клавиатурой.
      expect(find.byKey(const Key('shelf-search-field')), findsNothing);
      expect(find.byKey(const Key('library-search')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: в основном приложении поиска на полке нет', (
      WidgetTester tester,
    ) async {
      await threeBooks();
      await pumpShelf(tester, testServices(data: data), titleSearch: false);

      expect(find.byKey(const Key('library-search')), findsNothing);
      expect(find.byKey(const Key('shelf-search-field')), findsNothing);
      expect(find.byKey(const Key('library-sort')), findsOneWidget);

      await unmount(tester);
    });
  });

  group('SNO-F-LIB-01: поиск по названию на широком окне', () {
    testWidgets('SNO-F-LIB-01: поле стоит в шапке всегда', (
      WidgetTester tester,
    ) async {
      wideWindow(tester);
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));

      expect(find.byKey(const Key('shelf-search-field')), findsOneWidget);
      expect(find.byKey(const Key('library-search')), findsNothing);
      expect(find.text('Полка'), findsOneWidget);
      // В пустом поле закрывать нечего.
      expect(find.byKey(const Key('shelf-search-close')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: найденное — под полем, полка видна', (
      WidgetTester tester,
    ) async {
      wideWindow(tester);
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));

      await type(tester, 'анат');

      expect(hit('prives'), findsOneWidget);
      expect(hit('pat'), findsOneWidget);
      // Полка осталась на экране — затемнённой, под списком.
      expect(find.byKey(const Key('library-shelf')), findsOneWidget);
      expect(find.byKey(const Key('shelf-search-scrim')), findsOneWidget);
      // Список стоит ровно под полем: левый край и ширина те же.
      final Rect field = tester.getRect(
        find.byKey(const Key('shelf-search-field')),
      );
      final Rect list = tester.getRect(
        find.byKey(const Key('shelf-search-results')),
      );
      expect(list.left, closeTo(field.left, 0.5));
      expect(list.width, closeTo(field.width, 0.5));
      expect(list.width, kShelfSearchWidth);
      expect(list.top, greaterThanOrEqualTo(field.bottom));

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: нажатие мимо списка закрывает поиск', (
      WidgetTester tester,
    ) async {
      wideWindow(tester);
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));
      await type(tester, 'анат');

      // Правый нижний угол окна: там затемнённая полка, списка нет.
      await tester.tapAt(const Offset(1100, 700));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shelf-search-results')), findsNothing);
      expect(find.byKey(const Key('shelf-search-scrim')), findsNothing);
      final TextField field = tester.widget(
        find.byKey(const Key('shelf-search-field')),
      );
      expect(field.controller!.text, isEmpty);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: после Enter поиск закрывается по Esc', (
      WidgetTester tester,
    ) async {
      wideWindow(tester);
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));
      await type(tester, 'анат');

      // Enter указатель ввода из поля не уводит — иначе Esc до поля не
      // дошёл бы, и закрыть найденное с клавиатуры было бы нечем.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shelf-search-results')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shelf-search-results')), findsNothing);
      expect(find.byKey(const Key('shelf-search-scrim')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: окно сузили — поле и найденное на месте', (
      WidgetTester tester,
    ) async {
      wideWindow(tester);
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));
      await type(tester, 'гист');
      expect(hit('hist'), findsOneWidget);

      tester.view.physicalSize = const Size(600, 800);
      await tester.pumpAndSettle();

      // Узкий экран: поле — на месте заголовка, найденное — вместо полки.
      expect(find.byKey(const Key('shelf-search-field')), findsOneWidget);
      expect(find.byKey(const Key('shelf-search-back')), findsOneWidget);
      expect(hit('hist'), findsOneWidget);
      expect(find.byKey(const Key('library-shelf')), findsNothing);

      // Стёрли запрос — поле не закрылось посреди набора.
      await type(tester, '');
      expect(find.byKey(const Key('shelf-search-field')), findsOneWidget);
      expect(find.byKey(const Key('library-shelf')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-01: нет совпадений — строка под полем', (
      WidgetTester tester,
    ) async {
      wideWindow(tester);
      await threeBooks();
      await pumpShelf(tester, testServices(data: data));

      await type(tester, 'квант');

      expect(find.byKey(const Key('shelf-search-empty')), findsOneWidget);
      expect(find.byKey(const Key('library-shelf')), findsOneWidget);

      await unmount(tester);
    });
  });

  group('SNO-F-LIB-01: подсветка совпавшего', () {
    const TextStyle mark = TextStyle(fontWeight: FontWeight.w700);

    List<String> pieces(TextSpan span, {required bool marked}) {
      return <String>[
        for (final InlineSpan part in span.children!)
          if (((part as TextSpan).style != null) == marked) part.text!,
      ];
    }

    test('SNO-F-LIB-01: название цело, отмечено совпавшее', () {
      const String title = 'Привес. Анатомия человека';
      final TextSpan span = highlightedTitle(title, const <TitleSpan>[
        TitleSpan(0, 4),
        TitleSpan(8, 12),
      ], mark);

      expect(span.toPlainText(), title);
      expect(pieces(span, marked: true), <String>['Прив', 'Анат']);
      expect(pieces(span, marked: false), <String>['ес. ', 'омия человека']);
    });

    test('SNO-F-LIB-01: без совпавшего название показано как есть', () {
      final TextSpan span = highlightedTitle(
        'Гистология',
        const <TitleSpan>[],
        mark,
      );
      expect(span.toPlainText(), 'Гистология');
      expect(pieces(span, marked: true), isEmpty);
    });

    test('SNO-F-LIB-01: кусок за краем названия обрезан по краю', () {
      final TextSpan span = highlightedTitle('Атлас', const <TitleSpan>[
        TitleSpan(3, 40),
      ], mark);
      expect(span.toPlainText(), 'Атлас');
      expect(pieces(span, marked: true), <String>['ас']);
    });
  });

  group('SNO-F-LIB-01: совпавшее читается на любой теме', () {
    for (final AppPalette palette in appPalettes.values) {
      test('SNO-F-LIB-01: ${palette.title} — буквы на подложке 4,5:1', () {
        // Список найденного лежит на фоне экрана (телефон) или на
        // поверхности (карточка под полем на широком окне).
        for (final int under in <int>[palette.background, palette.surface]) {
          final int mark = blendOver(
            palette.accentText,
            kShelfMarkOpacity,
            under,
          );
          final double ratio = contrastRatio(palette.text, mark);
          expect(
            ratio,
            greaterThanOrEqualTo(wcagAaNormalText),
            reason: 'выходит ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });
    }
  });

  group('SNO-F-READ-01: полка передаёт чтению, есть ли модель', () {
    testWidgets('SNO-F-READ-01: без модели книга открывается без промптов', (
      WidgetTester tester,
    ) async {
      await data.settings.write(SettingsKeys.tapZoneHintSeen, 'true');
      await data.library.save(testBook());
      await pumpShelf(tester, testServices(data: data), models: false);

      await tester.tap(find.byKey(const Key('library-book-book-1')));
      await tester.pumpAndSettle();
      final ReaderScreen reader = tester.widget(find.byType(ReaderScreen));
      expect(reader.models, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('SNO-F-READ-01: с моделью — как прежде', (
      WidgetTester tester,
    ) async {
      await data.settings.write(SettingsKeys.tapZoneHintSeen, 'true');
      await data.library.save(testBook());
      await pumpShelf(tester, testServices(data: data));

      await tester.tap(find.byKey(const Key('library-book-book-1')));
      await tester.pumpAndSettle();
      final ReaderScreen reader = tester.widget(find.byType(ReaderScreen));
      expect(reader.models, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await unmount(tester);
    });
  });
}
