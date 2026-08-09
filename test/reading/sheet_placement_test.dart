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
      // По высоте остаётся запас, и лист стоит по центру.
      final double slack = _longSide - placement.sheetHeight;
      expect(placement.top, closeTo(slack / 2, 1e-9));
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

      final SheetViewport window = fragmentViewport(
        placement: loose,
        fragment: halves.first,
        screenWidth: _longSide,
        screenHeight: _shortSide,
      );
      expect(window.left, greaterThan(0));
      expect(window.top, greaterThan(0));
      expect(window.width + window.left, lessThan(_longSide));
      expect(window.height + window.top, lessThan(_shortSide));
    });

    test('вплотную окно совпадает с той стороной, которой не хватало', () {
      final SheetPlacement tight = placeWithFit(1);
      final SheetViewport window = fragmentViewport(
        placement: tight,
        fragment: halves.first,
        screenWidth: _longSide,
        screenHeight: _shortSide,
      );
      // Половина А4 ниже и шире экрана телефона: масштаб упирается в
      // высоту, по бокам остаётся фон.
      expect(window.height, closeTo(_shortSide, 1e-9));
      expect(window.width, lessThan(_longSide));
    });

    test('окно фрагмента не выходит за экран', () {
      for (final double fit in <double>[1, 0.9, 0.8, 0.7]) {
        final SheetPlacement placement = placeWithFit(fit);
        final SheetViewport window = fragmentViewport(
          placement: placement,
          fragment: halves.first,
          screenWidth: _longSide,
          screenHeight: _shortSide,
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
      final SheetViewport window = fragmentViewport(
        placement: loose,
        fragment: halves.first,
        screenWidth: _longSide,
        screenHeight: _shortSide,
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
  });
}
