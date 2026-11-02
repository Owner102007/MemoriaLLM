/// Паспорт файла и доверие тексту, как они лежат на устройстве
/// (F-MAP-18, D-010; шаг S58).
///
/// Паспорт (ALG-MAP-18) — проход по объектам PDF: на толстой книге это
/// секунды, и повторять его при каждом расчёте карты незачем. Доверие
/// (ALG-MAP-19) — по запомненному тексту страниц: пересчитывается, когда
/// текст книги дочитан или извлечён заново. Оба — производное по
/// отпечатку файла: в облако не уходят.
library;

import '../library/book_source.dart';
import 'file_passport.dart';
import 'map_trusted.dart';
import 'text_trust.dart';

/// Версия правила паспорта и доверия. Поменялось правило — число
/// растёт, и записанное прежней версией считается заново.
const int kPassportVersion = 1;

/// Как судили текст книги.
enum TrustKind {
  /// Не судили: книга идёт в карту как есть (язык без словаря).
  asIs,

  /// Посчитано доверие T.
  measured,

  /// Надёжного текста нет.
  littleText,
}

/// Запись о файле книги.
class PassportRecord {
  /// Создаёт запись.
  const PassportRecord({
    required this.fingerprint,
    required this.version,
    this.passport,
    this.trustTextVersion,
    this.trustPages = 0,
    this.trustKind = TrustKind.asIs,
    this.trust,
    this.pageTrust = const <PageTrust>[],
  });

  /// Отпечаток файла.
  final String fingerprint;

  /// Версия правила ([kPassportVersion]).
  final int version;

  /// Паспорт; `null` — файл не открылся.
  final FilePassport? passport;

  /// Версия текста страниц, по которому считано доверие; `null` — ещё
  /// не считали.
  final int? trustTextVersion;

  /// Сколько страниц текста было, когда считали доверие.
  final int trustPages;

  /// Как судили текст.
  final TrustKind trustKind;

  /// Доверие T, если [trustKind] — [TrustKind.measured].
  final double? trust;

  /// Состояние каждой запомненной страницы, по порядку номеров; пусто —
  /// текст не судили.
  final List<PageTrust> pageTrust;

  /// Доверие — вход правила созвездий.
  BookTrust get bookTrust => switch (trustKind) {
    TrustKind.asIs => const BookTrust.asIs(),
    TrustKind.littleText => const BookTrust.littleText(),
    TrustKind.measured => BookTrust.of(trust ?? 0),
  };

  /// Годится ли доверие для текста версии [textVersion] из [pages]
  /// страниц.
  bool trustFits(int textVersion, int pages) =>
      version == kPassportVersion &&
      trustTextVersion == textVersion &&
      trustPages == pages;

  /// Та же запись с новым доверием.
  PassportRecord withTrust(
    TextTrust? value, {
    required int textVersion,
    required int pages,
  }) {
    final TrustKind kind = value == null
        ? TrustKind.asIs
        : value.noReliableText
        ? TrustKind.littleText
        : TrustKind.measured;
    return PassportRecord(
      fingerprint: fingerprint,
      version: version,
      passport: passport,
      trustTextVersion: textVersion,
      trustPages: pages,
      trustKind: kind,
      trust: value?.trust,
      pageTrust: value?.pages ?? const <PageTrust>[],
    );
  }
}

/// Хранилище записей. Реализация — в `infrastructure`.
abstract interface class PassportRepository {
  /// Запись о файле; `null` — нет.
  Future<PassportRecord?> load(String fingerprint);

  /// Кладёт запись вместо прежней.
  Future<void> save(PassportRecord record);
}

/// Читает паспорт файла. Реализация — `infrastructure/pdf/` (PDFium).
abstract interface class PassportReader {
  /// Паспорт книги из [source]; `null` — файл не открылся.
  Future<FilePassport?> read(BookSource source);
}
