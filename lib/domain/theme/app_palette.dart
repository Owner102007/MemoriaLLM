/// Палитры тем приложения.
///
/// Тема по умолчанию — тёмно-красная: часть визуального языка экосистемы
/// «Библиотека ХохлоБарона». Опорные значения зафиксированы в `CLAUDE.md`
/// и без явного решения владельца не меняются.
///
/// Читаемость каждой палитры проверяется автотестом
/// `test/theme_contrast_test.dart`: тёмно-красные схемы очень легко сделать
/// красивыми и нечитаемыми.
library;

/// Идентификатор темы. Хранится в настройках, поэтому имена значений
/// менять нельзя без миграции.
enum AppThemeId {
  /// Тёмно-красная — тема по умолчанию.
  darkRed,

  /// Ночная красная: почти монохром на чёрном, для чтения в темноте.
  nightRed,

  /// Нейтральная тёмная — для тех, кому красный мешает.
  neutralDark,

  /// Сепия — бумажный вариант для дневного света.
  sepia,

  /// Светлая.
  light,
}

/// Набор цветов одной темы. Цвета — целые в формате `0xFFRRGGBB`,
/// чтобы доменный слой не зависел от Flutter.
class AppPalette {
  /// Создаёт палитру. Все цвета обязательны: «умолчаний» здесь быть не
  /// должно, иначе тема тихо разъедется.
  const AppPalette({
    required this.id,
    required this.title,
    required this.isDark,
    required this.background,
    required this.surface,
    required this.divider,
    required this.accent,
    required this.accentPressed,
    required this.onAccent,
    required this.accentText,
    required this.text,
    required this.textSecondary,
  });

  /// Идентификатор темы.
  final AppThemeId id;

  /// Название для экрана настроек.
  final String title;

  /// Тёмная ли тема — влияет на системные элементы (курсор, скроллбары).
  final bool isDark;

  /// Фон экрана.
  final int background;

  /// Фон карточек, панелей и шапки.
  final int surface;

  /// Разделители и границы.
  final int divider;

  /// Акцент как заливка (кнопки, индикаторы).
  final int accent;

  /// Акцент в нажатом состоянии и контур фокуса.
  final int accentPressed;

  /// Текст поверх акцентной заливки.
  final int onAccent;

  /// Акцентный цвет для текста и иконок поверх фона — светлее заливки,
  /// потому что к нему применим порог 4.5:1.
  final int accentText;

  /// Основной текст.
  final int text;

  /// Вторичный текст: подписи, метаданные книг.
  final int textSecondary;
}

/// Все палитры приложения.
const Map<AppThemeId, AppPalette> appPalettes = <AppThemeId, AppPalette>{
  AppThemeId.darkRed: AppPalette(
    id: AppThemeId.darkRed,
    title: 'Тёмно-красная',
    isDark: true,
    background: 0xFF0E0708,
    surface: 0xFF170D0F,
    divider: 0xFF2A1619,
    accent: 0xFFA32F35,
    accentPressed: 0xFFC7454A,
    onAccent: 0xFFFFFFFF,
    accentText: 0xFFD2565B,
    text: 0xFFE8DCD8,
    textSecondary: 0xFFB9A6A2,
  ),
  AppThemeId.nightRed: AppPalette(
    id: AppThemeId.nightRed,
    title: 'Ночная красная',
    isDark: true,
    background: 0xFF000000,
    surface: 0xFF0B0303,
    divider: 0xFF2B0E0E,
    accent: 0xFFC43A3A,
    accentPressed: 0xFFE05555,
    onAccent: 0xFFFFFFFF,
    accentText: 0xFFF0A8A8,
    text: 0xFFF0A8A8,
    textSecondary: 0xFFC88686,
  ),
  AppThemeId.neutralDark: AppPalette(
    id: AppThemeId.neutralDark,
    title: 'Нейтральная тёмная',
    isDark: true,
    background: 0xFF101012,
    surface: 0xFF17171A,
    divider: 0xFF2A2A2E,
    accent: 0xFF7C8CE8,
    accentPressed: 0xFF98A5F0,
    onAccent: 0xFF101012,
    accentText: 0xFF98A5F0,
    text: 0xFFE6E6E9,
    textSecondary: 0xFFB0B0B8,
  ),
  AppThemeId.sepia: AppPalette(
    id: AppThemeId.sepia,
    title: 'Сепия',
    isDark: false,
    background: 0xFFF4ECD8,
    surface: 0xFFEDE3CA,
    divider: 0xFFD8C9A6,
    accent: 0xFF8B5E34,
    accentPressed: 0xFF6E4926,
    onAccent: 0xFFF4ECD8,
    accentText: 0xFF6E4926,
    text: 0xFF3A2F1B,
    textSecondary: 0xFF5C4B2E,
  ),
  AppThemeId.light: AppPalette(
    id: AppThemeId.light,
    title: 'Светлая',
    isDark: false,
    background: 0xFFFFFFFF,
    surface: 0xFFF5F5F7,
    divider: 0xFFE0E0E4,
    accent: 0xFFA32F35,
    accentPressed: 0xFF8A2027,
    onAccent: 0xFFFFFFFF,
    accentText: 0xFF8A2027,
    text: 0xFF1A1A1C,
    textSecondary: 0xFF4A4A52,
  ),
};

/// Тема, с которой приложение стартует при первом запуске.
const AppThemeId defaultThemeId = AppThemeId.darkRed;

/// Тема по сохранённому имени.
///
/// Неизвестное имя не считается ошибкой: файл настроек мог приехать
/// с устройства, где стоит более новая версия приложения. Лучше открыться
/// с темой по умолчанию, чем не открыться вовсе.
AppThemeId themeIdFromName(String? name) {
  for (final AppThemeId id in AppThemeId.values) {
    if (id.name == name) {
      return id;
    }
  }
  return defaultThemeId;
}
