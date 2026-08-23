import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/columns.dart';
import 'package:memoria/domain/reading/fragments.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/text_geometry.dart';

import '../support/fake_reading.dart';

const CropBox _content = CropBox(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9);

const List<ColumnBand> _twoColumns = <ColumnBand>[
  ColumnBand(left: 0.1, right: 0.45),
  ColumnBand(left: 0.55, right: 0.9),
];

void main() {
  group('одна колонка', () {
    test('страница целиком — один фрагмент', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.full,
      );
      expect(parts, <CropBox>[_content]);
    });

    test('половина — две полосы, накрывающие всё содержимое', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.half,
      );
      expect(parts.length, 2);
      expect(parts.first.top, _content.top);
      expect(parts.last.bottom, _content.bottom);
      expect(parts.first.left, _content.left);
      expect(parts.last.right, _content.right);
    });

    test('по просвету половины делятся чёткой линией, без повторов', () {
      // Нахлёст задумывался как забота о строке на границе, но повторял
      // её на обоих экранах, и читатель терял место. Раз граница попала
      // в просвет, повторять нечего: граница одна.
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.half,
        breaks: const <double>[0.5],
      );
      expect(parts.first.bottom, closeTo(parts.last.top, 1e-9));
      expect(
        parts.first.height,
        closeTo(parts.last.height, 1e-9),
        reason: 'половины равны',
      );
    });

    test('треть — три полосы', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.third,
      );
      expect(parts.length, 3);
      expect(parts.first.top, _content.top);
      expect(parts.last.bottom, _content.bottom);
      for (final CropBox part in parts) {
        expect(part.isValid, isTrue);
        expect(part.height, lessThan(_content.height));
      }
    });

    test('половина действительно вдвое крупнее страницы', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.half,
      );
      // Смысл режима: во столько же раз вырастет кегль на экране.
      expect(_content.height / parts.first.height, closeTo(2, 0.1));
    });
  });

  group('две колонки', () {
    test('половина — это колонка, а не верх страницы', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.half,
        columns: _twoColumns,
      );
      expect(parts.length, 2);
      expect(parts.first.left, 0.1);
      expect(parts.first.right, 0.45);
      expect(parts.first.top, _content.top);
      expect(parts.first.bottom, _content.bottom);
      expect(parts.last.left, 0.55);
    });

    test('треть — половина колонки, и порядок чтения сохранён', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.third,
        columns: _twoColumns,
      );
      expect(parts.length, 4);
      // Левая колонка сверху вниз, потом правая.
      expect(parts[0].right, 0.45);
      expect(parts[1].right, 0.45);
      expect(parts[0].top, lessThan(parts[1].top));
      expect(parts[2].left, 0.55);
      expect(parts[3].left, 0.55);
      expect(parts[2].top, lessThan(parts[3].top));
    });

    test('разворот колонками не делится', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.spread,
        columns: _twoColumns,
      );
      expect(parts, <CropBox>[_content]);
    });
  });

  test('испорченная рамка не оставляет читателя без фрагмента', () {
    final List<CropBox> parts = fragmentsFor(
      content: const CropBox(left: 1, top: 1, right: 0, bottom: 0),
      mode: PageDisplayMode.half,
    );
    expect(parts, <CropBox>[CropBox.full]);
  });

  group('граница проходит между строк', () {
    // Ровный блок из десяти строк: шаг 0.08, буквы 0.048, просвет 0.032.
    final List<TextLine> lines = groupTextLines(
      textBlock(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9, lines: 10),
    );
    final List<double> breaks = lineBreaks(lines);

    test('просветы найдены между всеми соседними строками', () {
      expect(breaks.length, lines.length - 1);
      for (int i = 1; i < lines.length; i++) {
        expect(breaks[i - 1], greaterThan(lines[i - 1].bottom));
        expect(breaks[i - 1], lessThan(lines[i].top));
      }
    });

    test('ни одна строка не разрезана пополам', () {
      // Ровно та беда, на которую наткнулся владелец: половина строки
      // остаётся на одном экране, половина на другом, и читать нельзя
      // ни там, ни там.
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.half,
        breaks: breaks,
      );
      final double edge = parts.first.bottom;
      for (final TextLine line in lines) {
        final bool cut = line.top < edge && line.bottom > edge;
        expect(cut, isFalse, reason: 'строка $line рассечена границей $edge');
      }
    });

    test('граница уезжает к просвету, но недалеко', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.half,
        breaks: breaks,
      );
      final double ideal = _content.top + _content.height / 2;
      expect(
        (parts.first.bottom - ideal).abs(),
        lessThan(_content.height / 2 * kBreakSearch + 1e-9),
      );
    });

    test('без просветов граница остаётся у середины', () {
      // Просветов нет вовсе: резать приходится по середине, и полосы
      // расходятся вокруг неё — середина между ними всё та же.
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.half,
      );
      final double middle = (parts.first.bottom + parts.last.top) / 2;
      expect(middle, closeTo(_content.top + _content.height / 2, 1e-9));
    });

    test('без просвета строка повторяется, а не теряется', () {
      // Потерянную строку читатель не восстановит никак: он даже не
      // узнает, что её не видел. Повторённую — просто пропустит глазом.
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.half,
      );
      expect(
        parts.first.bottom,
        greaterThan(parts.last.top),
        reason: 'между полосами не должно быть щели',
      );
      final double step = _content.height / 2;
      expect(
        parts.first.bottom - parts.last.top,
        closeTo(2 * step * kBlindOverlap, 1e-9),
        reason: 'нахлёст примерно в строку, а не в пол-экрана',
      );
    });

    test('нахлёста нет там, где просвет нашёлся', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.half,
        breaks: const <double>[0.52],
      );
      expect(parts.first.bottom, closeTo(0.52, 1e-9));
      expect(parts.last.top, closeTo(0.52, 1e-9));
    });

    test('далёкий просвет границу не утаскивает', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.half,
        breaks: const <double>[0.15, 0.85],
      );
      final double middle = (parts.first.bottom + parts.last.top) / 2;
      expect(middle, closeTo(_content.top + _content.height / 2, 1e-9));
    });

    test('полосы по-прежнему стыкуются без щели и без повтора', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.third,
        breaks: breaks,
      );
      expect(parts.length, 3);
      expect(parts[0].bottom, closeTo(parts[1].top, 1e-9));
      expect(parts[1].bottom, closeTo(parts[2].top, 1e-9));
      expect(parts.first.top, _content.top);
      expect(parts.last.bottom, _content.bottom);
    });
  });

  group('число фрагментов', () {
    test('совпадает с тем, что вернуло деление', () {
      for (final PageDisplayMode mode in PageDisplayMode.values) {
        for (final int columns in <int>[1, 2]) {
          final List<CropBox> parts = fragmentsFor(
            content: _content,
            mode: mode,
            columns: columns == 2
                ? _twoColumns
                : const <ColumnBand>[ColumnBand(left: 0.1, right: 0.9)],
          );
          expect(
            parts.length,
            fragmentCountFor(mode: mode, columnCount: columns),
            reason: 'режим $mode, колонок $columns',
          );
        }
      }
    });
  });

  group('смена режима не теряет место', () {
    test('верхняя половина остаётся верхом при переходе на треть', () {
      expect(remapFragment(index: 0, oldCount: 2, newCount: 3), 0);
    });

    test('нижняя половина попадает в нижнюю треть', () {
      expect(remapFragment(index: 1, oldCount: 2, newCount: 3), 2);
    });

    test('середина трети попадает в ту же половину', () {
      expect(remapFragment(index: 1, oldCount: 3, newCount: 2), 1);
      expect(remapFragment(index: 0, oldCount: 3, newCount: 2), 0);
      expect(remapFragment(index: 2, oldCount: 3, newCount: 2), 1);
    });

    test('переход на страницу целиком всегда даёт нулевой фрагмент', () {
      for (int i = 0; i < 4; i++) {
        expect(remapFragment(index: i, oldCount: 4, newCount: 1), 0);
      }
    });

    test('мусорный номер фрагмента не выводит за диапазон', () {
      expect(remapFragment(index: -5, oldCount: 3, newCount: 2), 0);
      expect(remapFragment(index: 99, oldCount: 3, newCount: 2), 1);
      expect(clampFragment(-1, 3), 0);
      expect(clampFragment(9, 3), 2);
      expect(clampFragment(9, 0), 0);
    });

    test('обратный переход возвращает примерно туда же', () {
      for (int i = 0; i < 3; i++) {
        final int toHalf = remapFragment(index: i, oldCount: 3, newCount: 2);
        final int back = remapFragment(index: toHalf, oldCount: 2, newCount: 3);
        expect((back - i).abs(), lessThanOrEqualTo(1));
      }
    });
  });

  group('разворот', () {
    test('первая страница стоит одна, дальше идут пары', () {
      expect(spreadPages(1, 10), <int>[1]);
      expect(spreadPages(2, 10), <int>[2, 3]);
      expect(spreadPages(3, 10), <int>[2, 3]);
      expect(spreadPages(4, 10), <int>[4, 5]);
      expect(spreadPages(9, 10), <int>[8, 9]);
    });

    test('последняя страница без пары показывается одна', () {
      expect(spreadPages(10, 10), <int>[10]);
    });

    test('края книги не ломают пару', () {
      expect(spreadPages(0, 10), <int>[1]);
      expect(spreadPages(99, 10), <int>[10]);
      expect(spreadPages(1, 0), <int>[1]);
      expect(spreadPages(1, 1), <int>[1]);
    });

    test('половина разворота делит его по горизонтали', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.spreadHalf,
        columns: _twoColumns,
        breaks: const <double>[0.5],
      );
      expect(parts.length, 2);
      // Строка идёт через обе страницы сразу, поэтому колонки внутри
      // страниц разворот не делят.
      expect(parts.first.left, _content.left);
      expect(parts.first.right, _content.right);
      expect(parts.first.top, _content.top);
      expect(parts.last.bottom, _content.bottom);
      expect(parts.first.bottom, closeTo(parts.last.top, 1e-9));
    });

    test('разворот и его половина показывают по две страницы', () {
      expect(isSpreadMode(PageDisplayMode.spread), isTrue);
      expect(isSpreadMode(PageDisplayMode.spreadHalf), isTrue);
      expect(isSpreadMode(PageDisplayMode.half), isFalse);
      expect(isSpreadMode(PageDisplayMode.full), isFalse);
    });
  });

  group('деление и форма области показа — одно решение', () {
    // Страница А4 и телефон 1080×2400. Область показа подаётся числами:
    // ориентации у окна на ПК нет вовсе, а форма есть всегда.
    const double sheetW = 595;
    const double sheetH = 842;
    const DisplayArea phone = DisplayArea(width: 1080, height: 2400);

    FragmentLayout layout(
      PageDisplayMode mode, {
      List<ColumnBand> columns = const <ColumnBand>[],
      DisplayArea area = phone,
      bool canTurn = true,
      double sheetWidth = sheetW,
      double sheetHeight = sheetH,
    }) {
      return chooseFragmentLayout(
        mode: mode,
        content: CropBox.full,
        sheetWidth: sheetWidth,
        sheetHeight: sheetHeight,
        area: area,
        columns: columns,
        canTurn: canTurn,
      );
    }

    test('целая страница читается вертикально', () {
      final FragmentLayout full = layout(PageDisplayMode.full);
      expect(full.orientation, ScreenOrientation.portrait);
      expect(full.gain, closeTo(1, 1e-9));
      expect(full.split, FragmentSplit.whole);
    });

    test('полосы одноколоночной страницы просят альбом', () {
      final FragmentLayout half = layout(PageDisplayMode.half);
      expect(half.split, FragmentSplit.rows);
      expect(half.orientation, ScreenOrientation.landscape);
      expect(half.gain, greaterThan(1.3));
      expect(half.isWorthwhile, isTrue);
    });

    test('колонка просит портрет, а не альбом', () {
      // Ровно та ошибка, на которую наткнулся владелец: колонка — узкий
      // и высокий прямоугольник, и в широкий низкий экран она вписывается
      // по высоте. Текст выходил мельче, чем на целой странице.
      final FragmentLayout half = layout(
        PageDisplayMode.half,
        columns: _twoColumns,
      );
      expect(half.split, FragmentSplit.columns);
      expect(half.orientation, ScreenOrientation.portrait);
      expect(half.gain, greaterThan(1.3));
    });

    test('половина колонки тоже просит портрет', () {
      // План предполагал здесь альбом. Счёт говорит другое: колонка узкая,
      // и даже её половина упирается в ширину экрана раньше, чем в высоту.
      // Ради этого функция и считает, а не помнит правило наизусть.
      final FragmentLayout third = layout(
        PageDisplayMode.third,
        columns: _twoColumns,
      );
      expect(third.split, FragmentSplit.columnRows);
      expect(third.orientation, ScreenOrientation.portrait);
      expect(third.gain, greaterThan(2));
    });

    test('выбранное положение экрана — лучшее из двух', () {
      for (final PageDisplayMode mode in PageDisplayMode.values) {
        for (final List<ColumnBand> columns in <List<ColumnBand>>[
          const <ColumnBand>[],
          _twoColumns,
        ]) {
          final FragmentLayout best = layout(mode, columns: columns);
          final FragmentLayout turned = chooseFragmentLayout(
            mode: mode,
            content: CropBox.full,
            sheetWidth: sheetW,
            sheetHeight: sheetH,
            area: best.area.turned,
            columns: columns,
            canTurn: false,
          );
          expect(
            best.scale,
            greaterThanOrEqualTo(turned.scale - 1e-9),
            reason: '$mode, колонок ${columns.length}',
          );
        }
      }
    });

    test('режим без выигрыша не включается', () {
      // Широкое низкое окно на ПК: повернуть его нельзя, а колонка в него
      // вписывается по высоте — ровно так же, как на целой странице.
      final FragmentLayout half = layout(
        PageDisplayMode.half,
        columns: _twoColumns,
        area: const DisplayArea(width: 2560, height: 1080),
        canTurn: false,
      );
      expect(half.gain, closeTo(1, 0.01));
      expect(half.isWorthwhile, isFalse);
    });

    test('узкое высокое окно не даёт выигрыша полосам', () {
      final FragmentLayout half = layout(
        PageDisplayMode.half,
        area: const DisplayArea(width: 600, height: 2000),
        canTurn: false,
      );
      expect(half.isWorthwhile, isFalse);
    });

    test('разворот не гасится за отсутствие выигрыша', () {
      // Развороты показывают больше книги сразу, а не крупнее: мерить их
      // кеглем бессмысленно, и запрещать по этой мерке нечего.
      final FragmentLayout spread = chooseFragmentLayout(
        mode: PageDisplayMode.spread,
        content: CropBox.full,
        sheetWidth: sheetW * 2,
        sheetHeight: sheetH,
        area: phone,
      );
      expect(spread.magnifies, isFalse);
      expect(spread.isWorthwhile, isTrue);
      expect(spread.orientation, ScreenOrientation.landscape);
    });

    test('неизмеренная область не запрещает ничего', () {
      final FragmentLayout half = layout(
        PageDisplayMode.half,
        area: DisplayArea.unknown,
      );
      expect(half.isKnown, isFalse);
      expect(half.isWorthwhile, isTrue, reason: 'запрет по незнанию — хуже');
    });

    test('бессмысленный лист не роняет выбор', () {
      final FragmentLayout half = layout(
        PageDisplayMode.half,
        sheetWidth: 0,
        sheetHeight: double.nan,
      );
      expect(half.isKnown, isFalse);
      expect(half.gain, 0);
    });
  });

  group('форма области показа', () {
    test('стороны переставляются по длине, а не как попало', () {
      const DisplayArea phone = DisplayArea(width: 1080, height: 2400);
      expect(
        phone.oriented(ScreenOrientation.landscape),
        const DisplayArea(width: 2400, height: 1080),
      );
      // Уже альбомная область в альбоме не переворачивается: иначе выбор
      // раскладки скакал бы при каждом повороте телефона.
      expect(
        phone.turned.oriented(ScreenOrientation.landscape),
        const DisplayArea(width: 2400, height: 1080),
      );
      expect(phone.orientation, ScreenOrientation.portrait);
      expect(phone.turned.orientation, ScreenOrientation.landscape);
    });

    test('неизмеренная область так и говорит', () {
      expect(DisplayArea.unknown.isKnown, isFalse);
      expect(const DisplayArea(width: 10, height: 0).isKnown, isFalse);
      expect(const DisplayArea(width: 10, height: 10).isKnown, isTrue);
    });
  });

  group('ради чего всё затевалось: текст должен стать крупнее', () {
    // Обрезанное содержимое страницы А4 и экран телефона 1080×2400.
    const double pageWidth = 428;
    const double pageHeight = 640;
    const double screenShort = 1080;
    const double screenLong = 2400;

    double scale({
      required double width,
      required double height,
      required bool landscape,
    }) {
      return fragmentScale(
        fragmentWidth: width,
        fragmentHeight: height,
        screenWidth: landscape ? screenLong : screenShort,
        screenHeight: landscape ? screenShort : screenLong,
      );
    }

    final double wholeInPortrait = scale(
      width: pageWidth,
      height: pageHeight,
      landscape: false,
    );

    test('половина на вертикальном экране не даёт ничего', () {
      // Ровно то, на что наткнулся владелец: полоса вдвое ниже, но той же
      // ширины, а страница вписывается в вертикальный экран по ширине.
      final double halfInPortrait = scale(
        width: pageWidth,
        height: pageHeight / 2,
        landscape: false,
      );
      expect(halfInPortrait, closeTo(wholeInPortrait, 1e-9));
    });

    test('половина на горизонтальном экране крупнее', () {
      final double halfInLandscape = scale(
        width: pageWidth,
        height: pageHeight / 2,
        landscape: true,
      );
      expect(halfInLandscape, greaterThan(wholeInPortrait));
      expect(halfInLandscape / wholeInPortrait, greaterThan(1.3));
    });

    test('треть на горизонтальном экране крупнее вдвое', () {
      final double thirdInLandscape = scale(
        width: pageWidth,
        height: pageHeight / 3,
        landscape: true,
      );
      expect(thirdInLandscape / wholeInPortrait, greaterThan(1.9));
    });

    test('бессмысленные размеры дают ноль, а не бесконечность', () {
      expect(
        fragmentScale(
          fragmentWidth: 0,
          fragmentHeight: 10,
          screenWidth: 100,
          screenHeight: 100,
        ),
        0,
      );
      expect(
        fragmentScale(
          fragmentWidth: 10,
          fragmentHeight: 10,
          screenWidth: -1,
          screenHeight: 100,
        ),
        0,
      );
    });
  });
}
