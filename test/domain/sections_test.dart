import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/navigation/sections.dart';
import 'package:memoria/domain/reading/search_dock.dart';

/// F-APP-02: разделы главной навигации — правила без виджетов.
void main() {
  group('F-APP-02: где стоит навигация', () {
    test('F-APP-02: телефон и узкое окно — у нижнего края', () {
      for (final double width in <double>[320, 360, 412, 600, 800, 899.9]) {
        expect(
          navPlacementFor(width),
          NavPlacement.bottom,
          reason: 'ширина $width',
        );
      }
    });

    test('F-APP-02: окно от 900 точек — полосой наверху', () {
      for (final double width in <double>[900, 1024, 1280, 1920, 3840]) {
        expect(
          navPlacementFor(width),
          NavPlacement.top,
          reason: 'ширина $width',
        );
      }
    });

    test('F-APP-02: «широкое окно» значит одно и то же везде', () {
      // Панель поиска встаёт рядом со страницей с той же ширины, с какой
      // навигация встаёт наверх: два разных порога читатель видел бы как
      // окно, которое при одной ширине ведёт себя то так, то эдак.
      expect(kTopNavWidth, kSearchWideWindow);
    });
  });

  group('F-APP-02: разделы', () {
    test('F-APP-02: разделов три, и «Полка» первая', () {
      expect(AppSection.values, <AppSection>[
        AppSection.shelf,
        AppSection.device,
        AppSection.settings,
      ]);
    });

    test('F-APP-02: у каждого раздела своё название', () {
      final Set<String> titles = <String>{
        for (final AppSection section in AppSection.values)
          sectionTitle(section),
      };
      expect(titles, <String>{'Полка', 'Устройство', 'Настройки'});
    });

    test('F-APP-02: «назад» ведёт на «Полку», а с неё — из приложения', () {
      expect(sectionBehind(AppSection.device), AppSection.shelf);
      expect(sectionBehind(AppSection.settings), AppSection.shelf);
      expect(sectionBehind(AppSection.shelf), isNull);
    });
  });
}
