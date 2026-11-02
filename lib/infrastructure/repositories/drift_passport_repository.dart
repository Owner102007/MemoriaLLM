import 'package:drift/drift.dart';

import '../../domain/map/book_passport.dart';
import '../../domain/map/file_passport.dart';
import '../../domain/map/text_trust.dart';
import '../database/app_database.dart';

/// Паспорт файла и доверие тексту поверх drift (F-MAP-18, схема 14).
///
/// Меток HLC нет намеренно: это производное по отпечатку файла (D-010)
/// и в слияние не идёт. Перечисления хранятся номерами — порядок их
/// значений в домене менять нельзя без новой версии правила.
class DriftPassportRepository implements PassportRepository {
  /// Создаёт хранилище.
  DriftPassportRepository(this._db);

  final AppDatabase _db;

  @override
  Future<PassportRecord?> load(String fingerprint) async {
    final FilePassportRow? row =
        await (_db.select(_db.filePassports)..where(
              ($FilePassportsTable t) => t.fingerprint.equals(fingerprint),
            ))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return PassportRecord(
      fingerprint: row.fingerprint,
      version: row.algorithmVersion,
      passport: row.hasPassport
          ? FilePassport(
              pageKinds: <PageKind>[
                for (final int unit in row.pageKinds.codeUnits)
                  PageKind.values[unit - 0x30],
              ],
              kind: BookKind.values[row.kind],
              dpiMedian: row.dpiMedian,
              color: row.color == null ? null : ScanColor.values[row.color!],
              producer: row.producer,
              creator: row.creator,
              bookmarks: row.bookmarks,
            )
          : null,
      trustTextVersion: row.trustTextVersion,
      trustPages: row.trustPages,
      trustKind: TrustKind.values[row.trustKind],
      trust: row.trust,
      pageTrust: <PageTrust>[
        for (final int unit in row.pageTrust.codeUnits)
          PageTrust.values[unit - 0x30],
      ],
    );
  }

  @override
  Future<void> save(PassportRecord record) async {
    final FilePassport? passport = record.passport;
    await _db
        .into(_db.filePassports)
        .insertOnConflictUpdate(
          FilePassportsCompanion(
            fingerprint: Value<String>(record.fingerprint),
            algorithmVersion: Value<int>(record.version),
            hasPassport: Value<bool>(passport != null),
            kind: Value<int>(passport?.kind.index ?? 0),
            pageKinds: Value<String>(
              passport == null
                  ? ''
                  : String.fromCharCodes(<int>[
                      for (final PageKind kind in passport.pageKinds)
                        0x30 + kind.index,
                    ]),
            ),
            dpiMedian: Value<double?>(passport?.dpiMedian),
            color: Value<int?>(passport?.color?.index),
            producer: Value<String>(passport?.producer ?? ''),
            creator: Value<String>(passport?.creator ?? ''),
            bookmarks: Value<int>(passport?.bookmarks ?? 0),
            trustTextVersion: Value<int?>(record.trustTextVersion),
            trustPages: Value<int>(record.trustPages),
            trustKind: Value<int>(record.trustKind.index),
            trust: Value<double?>(record.trust),
            pageTrust: Value<String>(
              String.fromCharCodes(<int>[
                for (final PageTrust state in record.pageTrust)
                  0x30 + state.index,
              ]),
            ),
          ),
        );
  }
}
