import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/fragments.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/sheet_placement.dart';

/// Страница А4 в точках и телефон 800×360 в альбоме, 360×800 в портрете.
const double _pageWidth = 595;
const double _pageHeight = 842;
const double _shortSide = 360;
const double _longSide = 800;

SheetPlacement place({
  required CropBox fragment,
  bool landscape = false,
  double sheetWidth = _pageWidth,
  double sheetHeight = _pageHeight,
}) {
  return placeFragment(
    sheetWidth: sheetWidth,
    sheetHeight: sheetHeight,
    fragment: fragment,
    screenWidth: landscape ? _longSide : _shortSide,
    screenHeight: landscape ? _shortSide : _longSide,
  );
}

/// Прямоугольник листа, реально видимый на экране, в долях листа.
///
/// Обратный пересчёт: по раскладке восстанавливаем, что попало в окно.
/// Так проверяется не формула сама по себе, а её смысл — что именно
/// увидит читатель.
CropBox visible(SheetPlacement placement, {bool landscape = false}) {
  final double screenWidth = landscape ? _longSide : _shortSide;
  final double screenHeight = landscape ? _shortSide : _longSide;
  return CropBox(
    left: (-placement.left / placement.sheetWidth).clamp(0.0, 1.0),
    top: (-placement.top / placement.sheetHeight).clamp(0.0, 1.0),
    right: ((screenWidth - placement.left) / placement.sheetWidth).clamp(
      0.0,
      1.0,
    ),
    bottom: ((screenHeight - placement.top) / placement.sheetHeight).clamp(
      0.0,
      1.0,
    ),
  );
}

void main() {
  group('страница целиком', () {
    test('вписывается в вертикальный экран без обрезки', () {
      final SheetPlacement placement = place(fragment: CropBox.full);

      expect(placement.isVisible, isTrue);
      // Лист влезает целиком: ни одна его сторона не выходит за экран.
      expect(placement.left, greaterThanOrEqualTo(-1e-9));
      expect(placement.top, greaterThanOrEqualTo(-1e-9));
      expect(
        placement.left + placement.sheetWidth,
        lessThanOrEqualTo(_shortSide + 1e-9),
      );
      expect(
        placement.top + placement.sheetHeight,
        lessThanOrEqualTo(_longSide + 1e-9),
      );
    });

    test('занимает экран по узкой стороне, а не болтается в углу', () {
      final SheetPlacement placement = place(fragment: CropBox.full);
      // Страница уже экрана по пропорциям, поэтому упирается в ширину.
      expect(placement.sheetWidth, closeTo(_shortSide, 1e-9));
      expect(placement.left, closeTo(0, 1e-9));
      // По высоте остаётся запас, и он целиком уходит вниз (F-READ-11).
      expect(placement.top, closeTo(0, 1e-9));
      expect(_longSide - placement.sheetHeight, greaterThan(100));
    });
  });

  group('F-READ-11: полоса прижата кверху', () {
    // Широкое низкое окно ПК не годится: там полоса упирается в высоту,
    // и прижимать нечего. Запас по вертикали появляется, когда полоса
    // упёрлась в ширину, — на высоком экране.
    final List<CropBox> halves = fragmentsFor(
      content: CropBox.full,
      mode: PageDisplayMode.half,
      breaks: const <double>[0.5],
    );

    test('F-READ-11: полоса уже экрана начинается у его верха', () {
      for (final CropBox half in halves) {
        final SheetPlacement placement = place(fragment: half);
        final SheetViewport window = fragmentBounds(
          placement: placement,
          fragment: half,
        );
        // Половина А4 на вертикальном телефоне упирается в ширину.
        expect(window.width, closeTo(_shortSide, 1e-9));
        expect(window.height, lessThan(_longSide - 100));
        expect(window.top, closeTo(0, 1e-9), reason: 'весь запас — вниз');
      }
    });

    test('F-READ-11: верх полосы не зависит от её высоты', () {
      // Жалоба владельца была ровно на это: полосы одной страницы разной
      // высоты — граница ищет просвет между строками, — и при центровке
      // первая строка гуляла от экрана к экрану.
      const CropBox shortStrip = CropBox(
        left: 0,
        top: 0,
        right: 1,
        bottom: 0.42,
      );
      const CropBox tallStrip = CropBox(
        left: 0,
        top: 0.42,
        right: 1,
        bottom: 1,
      );
      double topOf(CropBox strip) {
        final SheetPlacement placement = place(fragment: strip);
        return fragmentBounds(placement: placement, fragment: strip).top;
      }

      expect(topOf(shortStrip), closeTo(topOf(tallStrip), 1e-9));
    });

    test('F-READ-11: по горизонтали полоса по-прежнему по центру', () {
      final SheetPlacement placement = place(
        fragment: halves.first,
        landscape: true,
      );
      final SheetViewport window = fragmentBounds(
        placement: placement,
        fragment: halves.first,
      );
      expect(window.left, greaterThan(1));
      expect(
        window.left,
        closeTo(_longSide - (window.left + window.width), 1e-9),
      );
    });

    test('F-READ-11: запас по краям отодвигает полосу и от верха', () {
      final SheetViewport window = fragmentBounds(
        placement: placeFragment(
          sheetWidth: _pageWidth,
          sheetHeight: _pageHeight,
          fragment: halves.first,
          screenWidth: _shortSide,
          screenHeight: _longSide,
          fit: 0.9,
        ),
        fragment: halves.first,
      );
      // Крайняя строка уходит от выреза камеры: сверху остаётся столько
      // же, сколько осталось бы у полосы, упёршейся в высоту.
      expect(window.top, closeTo(_longSide * 0.05, 1e-9));
      expect(window.left, closeTo(_shortSide * 0.05, 1e-9));
    });
  });

  group('F-READ-12: нахлёст', () {
    final List<CropBox> halves = fragmentsFor(
      content: CropBox.full,
      mode: PageDisplayMode.half,
      breaks: const <double>[0.5],
    );
    final List<CropBox> thirds = fragmentsFor(
      content: CropBox.full,
      mode: PageDisplayMode.third,
      breaks: const <double>[1 / 3, 2 / 3],
    );

    SheetViewport windowOf(
      CropBox strip, {
      required double overlap,
      bool landscape = true,
    }) {
      final double width = landscape ? _longSide : _shortSide;
      final double height = landscape ? _shortSide : _longSide;
      return fragmentBounds(
        placement: placeFragment(
          sheetWidth: _pageWidth,
          sheetHeight: _pageHeight,
          fragment: strip,
          screenWidth: width,
          screenHeight: height,
          overlap: overlap,
        ),
        fragment: strip,
      );
    }

    test('F-READ-12: над полосой и под ней остаётся по нахлёсту', () {
      // Половина А4 на лежащем телефоне упирается в высоту: нахлёст
      // отнимает у неё экран сверху и снизу поровну.
      final SheetViewport window = windowOf(halves.first, overlap: 0.07);
      expect(window.top, closeTo(_shortSide * 0.07, 1e-9));
      expect(window.top + window.height, closeTo(_shortSide * 0.93, 1e-9));
    });

    test('F-READ-12: полоса содержимого равна 1/N при любом нахлёсте', () {
      // Нахлёст расширяет окно показа, а не делитель: дробь на кнопке
      // значит ровно то, что нарисована. Проверяется смыслом — какая
      // доля листа лежит в светлом окне.
      for (final List<CropBox> parts in <List<CropBox>>[halves, thirds]) {
        for (final CropBox strip in parts) {
          for (final double overlap in <double>[0, 0.035, 0.07, 0.15]) {
            for (final bool landscape in <bool>[true, false]) {
              final double width = landscape ? _longSide : _shortSide;
              final double height = landscape ? _shortSide : _longSide;
              final SheetPlacement placement = placeFragment(
                sheetWidth: _pageWidth,
                sheetHeight: _pageHeight,
                fragment: strip,
                screenWidth: width,
                screenHeight: height,
                overlap: overlap,
              );
              final SheetViewport window = fragmentBounds(
                placement: placement,
                fragment: strip,
              );
              final String at = 'нахлёст $overlap, полос ${parts.length}';
              expect(
                window.height / placement.sheetHeight,
                closeTo(1 / parts.length, 1e-9),
                reason: at,
              );
              expect(
                window.width / placement.sheetWidth,
                closeTo(1, 1e-9),
                reason: at,
              );
              // И полоса целиком на экране, между нахлёстами.
              expect(
                window.top,
                greaterThanOrEqualTo(height * overlap - 1e-9),
                reason: at,
              );
              expect(
                window.top + window.height,
                lessThanOrEqualTo(height * (1 - overlap) + 1e-9),
                reason: at,
              );
              expect(window.left, greaterThanOrEqualTo(-1e-9), reason: at);
              expect(
                window.left + window.width,
                lessThanOrEqualTo(width + 1e-9),
                reason: at,
              );
            }
          }
        }
      }
    });

    test('F-READ-12: в нахлёсте видно продолжение той же страницы', () {
      // Под первой половиной — начало второй: лист не обрезан, он
      // продолжается под полосой, и маска его только затемняет.
      final SheetPlacement placement = placeFragment(
        sheetWidth: _pageWidth,
        sheetHeight: _pageHeight,
        fragment: halves.first,
        screenWidth: _longSide,
        screenHeight: _shortSide,
        overlap: 0.07,
      );
      final CropBox shown = visible(placement, landscape: true);
      expect(shown.bottom, greaterThan(halves.first.bottom + 0.01));
      // А над первой полосой страницы нет: там её верхний край.
      expect(placement.top, closeTo(_shortSide * 0.07, 1e-9));
    });

    test('F-READ-12: нулевой нахлёст — полоса вплотную, как прежде', () {
      final SheetViewport window = windowOf(halves.first, overlap: 0);
      expect(window.top, closeTo(0, 1e-9));
      expect(window.height, closeTo(_shortSide, 1e-9));
    });

    test('F-READ-12: нахлёст не бывает больше потолка', () {
      final SheetViewport capped = windowOf(halves.first, overlap: 0.6);
      final SheetViewport top = windowOf(
        halves.first,
        overlap: kMaxStripOverlap,
      );
      expect(capped.top, closeTo(top.top, 1e-9));
      expect(capped.height, closeTo(top.height, 1e-9));
      expect(clampStripOverlap(double.nan), 0);
      expect(clampStripOverlap(-1), 0);
    });

    test('F-READ-12: полосе, упёршейся в ширину, нахлёст ничего не стоит', () {
      // На вертикальном экране запас по высоте и так есть: полоса
      // остаётся того же размера и только съезжает под нахлёст.
      final SheetViewport plain = windowOf(
        halves.first,
        overlap: 0,
        landscape: false,
      );
      final SheetViewport lapped = windowOf(
        halves.first,
        overlap: 0.07,
        landscape: false,
      );
      expect(lapped.height, closeTo(plain.height, 1e-9));
      expect(lapped.top, closeTo(_longSide * 0.07, 1e-9));
    });

    test('F-READ-12: у трети нахлёст вдвое меньше, у страницы его нет', () {
      expect(stripOverlapFor(overlap: 0.07, count: 2), closeTo(0.07, 1e-12));
      expect(stripOverlapFor(overlap: 0.07, count: 3), closeTo(0.035, 1e-12));
      expect(stripOverlapFor(overlap: 0.07, count: 1), 0);
      expect(stripOverlapFor(overlap: 0.5, count: 2), kMaxStripOverlap);
      expect(stripOverlapFor(overlap: 0, count: 2), 0);
    });
  });

  group('половина страницы', () {
    // Просвет ровно посередине: раскладку проверяем на чистом делении,
    // а нахлёст «слепой» границы — там, где ему место, в тестах деления.
    final List<CropBox> halves = fragmentsFor(
      content: CropBox.full,
      mode: PageDisplayMode.half,
      breaks: const <double>[0.5],
    );

    test('на горизонтальном экране страница шире, чем в портрете', () {
      final SheetPlacement whole = place(fragment: CropBox.full);
      final SheetPlacement top = place(fragment: halves.first, landscape: true);
      expect(top.scale, greaterThan(whole.scale));
    });

    test('боковые поля не срезаны, срезан только низ', () {
      final SheetPlacement top = place(fragment: halves.first, landscape: true);
      final CropBox shown = visible(top, landscape: true);

      expect(shown.left, closeTo(0, 1e-9), reason: 'левое поле на месте');
      expect(shown.right, closeTo(1, 1e-9), reason: 'правое поле на месте');
      expect(shown.top, closeTo(0, 1e-9), reason: 'верхнее поле на месте');
      expect(shown.bottom, lessThan(0.75), reason: 'низ обрезан');
    });

    test('вторая половина показывает низ страницы', () {
      final SheetPlacement bottom = place(
        fragment: halves.last,
        landscape: true,
      );
      final CropBox shown = visible(bottom, landscape: true);

      expect(shown.bottom, closeTo(1, 1e-9), reason: 'нижнее поле на месте');
      expect(shown.top, greaterThan(0.25), reason: 'верх обрезан');
    });

    test('половины стыкуются ровно и ничего не повторяют', () {
      final CropBox top = visible(
        place(fragment: halves.first, landscape: true),
        landscape: true,
      );
      final CropBox bottom = visible(
        place(fragment: halves.last, landscape: true),
        landscape: true,
      );
      // Ни щели, ни повтора: где кончилась первая половина, там ровно
      // и начинается вторая.
      expect(top.bottom, closeTo(bottom.top, 1e-9));
      expect(top.top, closeTo(0, 1e-9));
      expect(bottom.bottom, closeTo(1, 1e-9));
    });
  });

  group('разворот', () {
    test('две страницы рядом вписаны в горизонтальный экран', () {
      final SheetPlacement placement = place(
        fragment: CropBox.full,
        landscape: true,
        sheetWidth: _pageWidth * 2,
      );

      expect(placement.isVisible, isTrue);
      expect(
        placement.sheetWidth,
        lessThanOrEqualTo(_longSide + 1e-9),
        reason: 'разворот целиком на экране',
      );
      expect(
        placement.sheetHeight,
        lessThanOrEqualTo(_shortSide + 1e-9),
        reason: 'по высоте тоже влезает',
      );
      expect(placement.left, greaterThanOrEqualTo(-1e-9));
      expect(placement.top, greaterThanOrEqualTo(-1e-9));
    });

    test('разворот на вертикальном экране мельче, чем на горизонтальном', () {
      final SheetPlacement portrait = place(
        fragment: CropBox.full,
        sheetWidth: _pageWidth * 2,
      );
      final SheetPlacement landscape = place(
        fragment: CropBox.full,
        landscape: true,
        sheetWidth: _pageWidth * 2,
      );
      expect(landscape.scale, greaterThan(portrait.scale));
    });
  });

  group('масштаб не зависит ни от чего, кроме листа и экрана', () {
    test('одна и та же страница в одном режиме — один и тот же масштаб', () {
      final SheetPlacement first = place(fragment: CropBox.full);
      final SheetPlacement second = place(fragment: CropBox.full);
      expect(first, second);
    });

    test('страницы разного размера дают разный масштаб, но обе целиком', () {
      final SheetPlacement small = place(
        fragment: CropBox.full,
        sheetWidth: 300,
        sheetHeight: 400,
      );
      expect(small.sheetWidth, lessThanOrEqualTo(_shortSide + 1e-9));
      expect(small.sheetHeight, lessThanOrEqualTo(_longSide + 1e-9));
    });
  });

  group('запас по краям', () {
    final List<CropBox> halves = fragmentsFor(
      content: CropBox.full,
      mode: PageDisplayMode.half,
      breaks: const <double>[0.5],
    );

    SheetPlacement placeWithFit(double fit) {
      return placeFragment(
        sheetWidth: _pageWidth,
        sheetHeight: _pageHeight,
        fragment: halves.first,
        screenWidth: _longSide,
        screenHeight: _shortSide,
        fit: fit,
      );
    }

    test('уменьшение отодвигает полосу от краёв экрана', () {
      final SheetPlacement tight = placeWithFit(1);
      final SheetPlacement loose = placeWithFit(0.85);
      expect(loose.scale, closeTo(tight.scale * 0.85, 1e-9));

      final SheetViewport window = fragmentBounds(
        placement: loose,
        fragment: halves.first,
      );
      expect(window.left, greaterThan(0));
      expect(window.top, greaterThan(0));
      expect(window.width + window.left, lessThan(_longSide));
      expect(window.height + window.top, lessThan(_shortSide));
    });

    test('вплотную окно совпадает с той стороной, которой не хватало', () {
      final SheetPlacement tight = placeWithFit(1);
      final SheetViewport window = fragmentBounds(
        placement: tight,
        fragment: halves.first,
      );
      // Половина А4 ниже и шире экрана телефона: масштаб упирается в
      // высоту, по бокам остаётся фон.
      expect(window.height, closeTo(_shortSide, 1e-9));
      expect(window.width, lessThan(_longSide));
    });

    test('читаемая полоса не выходит за экран', () {
      for (final double fit in <double>[1, 0.9, 0.8, 0.7]) {
        final SheetPlacement placement = placeWithFit(fit);
        final SheetViewport window = fragmentBounds(
          placement: placement,
          fragment: halves.first,
        );
        expect(window.isVisible, isTrue, reason: 'запас $fit');
        expect(window.left, greaterThanOrEqualTo(-1e-9));
        expect(window.top, greaterThanOrEqualTo(-1e-9));
        expect(window.left + window.width, lessThanOrEqualTo(_longSide + 1e-9));
        expect(
          window.top + window.height,
          lessThanOrEqualTo(_shortSide + 1e-9),
        );
      }
    });

    test('затемнённая часть листа остаётся за краем экрана', () {
      // Главное свойство затемнения: соседние полосы не вырезаны, они
      // просто лежат за краем. Уменьшил щипком — увидел страницу целиком.
      final SheetPlacement placement = placeWithFit(1);
      final SheetViewport window = fragmentBounds(
        placement: placement,
        fragment: halves.first,
      );
      expect(
        placement.top + placement.sheetHeight,
        greaterThan(window.top + window.height + 1),
        reason: 'вторая половина листа существует ниже экрана',
      );
    });

    test('мельче предела полоса не уменьшается', () {
      expect(clampStripFit(0.1), kMinStripFit);
      expect(clampStripFit(-3), kMinStripFit);
      expect(clampStripFit(double.nan), 1);
      expect(clampStripFit(2), 1);
      expect(clampStripFit(0.9), 0.9);
      expect(placeWithFit(0.1).scale, closeTo(placeWithFit(0).scale, 1e-9));
    });

    test('запас не меняет того, какая часть листа показана', () {
      // Уменьшение — это про края экрана, а не про содержимое: полоса
      // остаётся той же, иначе читатель терял бы строки при подгонке.
      final SheetPlacement loose = placeWithFit(0.8);
      final SheetViewport window = fragmentBounds(
        placement: loose,
        fragment: halves.first,
      );
      expect(
        window.width / window.height,
        closeTo(
          halves.first.width * _pageWidth / (halves.first.height * _pageHeight),
          1e-9,
        ),
      );
    });
  });

  group('бессмыслица не ломает экран', () {
    test('нулевой лист или экран — показывать нечего', () {
      expect(place(fragment: CropBox.full, sheetWidth: 0), SheetPlacement.none);
      expect(
        placeFragment(
          sheetWidth: 100,
          sheetHeight: 100,
          fragment: CropBox.full,
          screenWidth: 0,
          screenHeight: 100,
        ),
        SheetPlacement.none,
      );
    });

    test('вывернутый фрагмент — показывать нечего', () {
      expect(
        place(fragment: const CropBox(left: 1, top: 1, right: 0, bottom: 0)),
        SheetPlacement.none,
      );
    });

    test('у пустой раскладки нет и полосы', () {
      expect(
        fragmentBounds(placement: SheetPlacement.none, fragment: CropBox.full),
        SheetViewport.none,
      );
    });
  });

  group('замок и масштаб', () {
    test('нетронутый масштаб узнаётся с поправкой на пальцы', () {
      // Ровной единицы жест не оставляет почти никогда, поэтому «не
      // трогал» — это окрестность, а не равенство.
      expect(isSheetZoomNeutral(1), isTrue);
      expect(isSheetZoomNeutral(1.001), isTrue);
      expect(isSheetZoomNeutral(0.999), isTrue);
    });

    test('осознанный масштаб замок обязан сохранить', () {
      expect(isSheetZoomNeutral(1.4), isFalse);
      expect(isSheetZoomNeutral(0.5), isFalse);
      expect(isSheetZoomNeutral(double.nan), isFalse);
    });
  });

  group('F-READ-35: чтение во весь экран', () {
    test('F-READ-35: во весь экран полоса вписана вплотную', () {
      // Каким бы ни был запас по краям у книги: режим затем и включают,
      // чтобы экран занимала именно читаемая полоса.
      expect(stripFitFor(stripFit: 0.85, fullScreen: true), 1);
      expect(stripFitFor(stripFit: kMinStripFit, fullScreen: true), 1);
    });

    test('F-READ-35: в окне запас книги остаётся прежним', () {
      expect(stripFitFor(stripFit: 0.85, fullScreen: false), 0.85);
      expect(stripFitFor(stripFit: 1, fullScreen: false), 1);
      expect(stripFitFor(stripFit: 0.1, fullScreen: false), kMinStripFit);
    });

    test('F-READ-35: полоса с запасом занимает монитор целиком', () {
      // Разворот на мониторе 16:10: в окне полоса с запасом 0,87 не
      // доходит до краёв, во весь экран — упирается в оба края той
      // стороной, которой не хватает.
      const CropBox strip = CropBox(
        left: 0.05,
        top: 0.04,
        right: 0.95,
        bottom: 0.96,
      );
      SheetViewport window({required bool fullScreen}) {
        return fragmentBounds(
          placement: placeFragment(
            sheetWidth: 1190,
            sheetHeight: 842,
            fragment: strip,
            screenWidth: 2000,
            screenHeight: 1250,
            fit: stripFitFor(stripFit: 0.87, fullScreen: fullScreen),
          ),
          fragment: strip,
        );
      }

      final SheetViewport framed = window(fullScreen: false);
      expect(framed.left, greaterThan(1));
      expect(framed.top, greaterThan(1));

      final SheetViewport full = window(fullScreen: true);
      final bool touchesWidth =
          full.left.abs() < 1e-6 && (full.width - 2000).abs() < 1e-6;
      final bool touchesHeight =
          full.top.abs() < 1e-6 && (full.height - 1250).abs() < 1e-6;
      expect(touchesWidth || touchesHeight, isTrue);
      expect(full.width, greaterThan(framed.width));
    });
  });
}
