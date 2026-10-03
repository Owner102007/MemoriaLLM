import 'package:drift/drift.dart';

import '../../domain/reading/reading.dart';
import '../../domain/sync/hlc.dart';
import '../database/app_database.dart';
import '../database/enum_text.dart';

/// Прогресс и настройки чтения поверх drift.
class DriftReadingRepository implements ReadingRepository {
  /// Создаёт репозиторий.
  DriftReadingRepository(this._db, this._clock);

  final AppDatabase _db;
  final HlcClock _clock;

  @override
  Future<ReadingPosition?> position(String bookId) async {
    final query = _db.select(_db.readingProgress);
    query.where(
      (tbl) => tbl.bookId.equals(bookId) & tbl.isDeleted.equals(false),
    );
    final ReadingProgressRow? row = await query.getSingleOrNull();
    return row == null ? null : _toPosition(row);
  }

  @override
  Stream<ReadingPosition?> watchPosition(String bookId) {
    final query = _db.select(_db.readingProgress);
    query.where(
      (tbl) => tbl.bookId.equals(bookId) & tbl.isDeleted.equals(false),
    );
    return query.watchSingleOrNull().map(_toPositionOrNull);
  }

  @override
  Stream<Map<String, ReadingPosition>> watchPositions() {
    final query = _db.select(_db.readingProgress);
    query.where((tbl) => tbl.isDeleted.equals(false));
    return query.watch().map((List<ReadingProgressRow> rows) {
      return <String, ReadingPosition>{
        for (final ReadingProgressRow row in rows) row.bookId: _toPosition(row),
      };
    });
  }

  @override
  Future<void> savePosition(ReadingPosition position) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final ReadingProgressCompanion row = ReadingProgressCompanion(
      bookId: Value<String>(position.bookId),
      page: Value<int>(position.page),
      fragment: Value<int>(position.fragment),
      offsetInFragment: Value<double>(position.offset),
      progress: Value<double>(position.progress),
      updatedAt: Value<DateTime>(position.updatedAt ?? DateTime.now()),
      hlc: Value<String>(mark),
      nodeId: Value<String>(stamp.nodeId),
      modified: Value<String>(mark),
      isDeleted: const Value<bool>(false),
    );
    await _db.into(_db.readingProgress).insertOnConflictUpdate(row);
  }

  @override
  Future<BookReadingSettings> settings(
    String bookId,
    ScreenOrientation orientation,
  ) async {
    final query = _db.select(_db.bookSettings);
    query.where(
      (tbl) =>
          tbl.bookId.equals(bookId) &
          tbl.orientation.equals(orientation.name) &
          tbl.isDeleted.equals(false),
    );
    final BookSettingsRow? row = await query.getSingleOrNull();
    if (row == null) {
      return BookReadingSettings(bookId: bookId, orientation: orientation);
    }
    return _toSettings(row);
  }

  @override
  Future<void> saveSettings(BookReadingSettings settings) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final CropBox? crop = settings.manualCrop;
    final BookSettingsCompanion row = BookSettingsCompanion(
      bookId: Value<String>(settings.bookId),
      orientation: Value<String>(settings.orientation.name),
      displayMode: Value<String>(settings.displayMode.name),
      autoCrop: Value<bool>(settings.autoCrop),
      ignoreRunningHeads: Value<bool>(settings.ignoreRunningHeads),
      cropLeft: Value<double?>(crop?.left),
      cropTop: Value<double?>(crop?.top),
      cropRight: Value<double?>(crop?.right),
      cropBottom: Value<double?>(crop?.bottom),
      filter: Value<String>(settings.filter.name),
      filterIntensity: Value<double>(settings.filterIntensity),
      brightness: Value<double>(settings.brightness),
      contrast: Value<double>(settings.contrast),
      gamma: Value<double>(settings.gamma),
      stripFit: Value<double>(settings.stripFit),
      dimOutside: Value<double>(settings.dimOutside),
      stripOverlap: Value<double>(settings.stripOverlap),
      neighbourShare: Value<double>(settings.neighbourShare),
      hlc: Value<String>(mark),
      nodeId: Value<String>(stamp.nodeId),
      modified: Value<String>(mark),
      isDeleted: const Value<bool>(false),
    );
    await _db.into(_db.bookSettings).insertOnConflictUpdate(row);
  }

  @override
  Future<BookFrame?> bookFrame(String bookId) async {
    final query = _db.select(_db.bookFrames);
    query.where((tbl) => tbl.bookId.equals(bookId));
    final BookFrameRow? row = await query.getSingleOrNull();
    if (row == null) {
      return null;
    }
    return BookFrame(
      odd: CropBox(
        left: row.cropLeft,
        top: row.cropTop,
        right: row.cropRight,
        bottom: row.cropBottom,
      ),
      evenShift: row.evenShift,
      samples: row.samplePages,
      ignoreRunningHeads: row.ignoreRunningHeads,
      version: row.algorithmVersion,
    );
  }

  @override
  Future<void> saveBookFrame(String bookId, BookFrame frame) async {
    // Меток HLC нет намеренно: рамка книги — производное и в слияние не
    // идёт (F-READ-15).
    final BookFramesCompanion row = BookFramesCompanion(
      bookId: Value<String>(bookId),
      cropLeft: Value<double>(frame.odd.left),
      cropTop: Value<double>(frame.odd.top),
      cropRight: Value<double>(frame.odd.right),
      cropBottom: Value<double>(frame.odd.bottom),
      evenShift: Value<double>(frame.evenShift),
      samplePages: Value<int>(frame.samples),
      ignoreRunningHeads: Value<bool>(frame.ignoreRunningHeads),
      algorithmVersion: Value<int>(frame.version),
    );
    await _db.into(_db.bookFrames).insertOnConflictUpdate(row);
  }

  ReadingPosition? _toPositionOrNull(ReadingProgressRow? row) {
    return row == null ? null : _toPosition(row);
  }

  ReadingPosition _toPosition(ReadingProgressRow row) {
    return ReadingPosition(
      bookId: row.bookId,
      page: row.page,
      fragment: row.fragment,
      offset: row.offsetInFragment,
      progress: row.progress,
      updatedAt: row.updatedAt,
    );
  }

  BookReadingSettings _toSettings(BookSettingsRow row) {
    return BookReadingSettings(
      bookId: row.bookId,
      orientation: enumByName(
        ScreenOrientation.values,
        row.orientation,
        ScreenOrientation.portrait,
      ),
      displayMode: enumByName(
        PageDisplayMode.values,
        row.displayMode,
        PageDisplayMode.full,
      ),
      autoCrop: row.autoCrop,
      ignoreRunningHeads: row.ignoreRunningHeads,
      manualCrop: _toCrop(row),
      filter: enumByName(ReadingFilter.values, row.filter, ReadingFilter.none),
      filterIntensity: row.filterIntensity,
      brightness: row.brightness,
      contrast: row.contrast,
      gamma: row.gamma,
      stripFit: row.stripFit,
      dimOutside: row.dimOutside,
      stripOverlap: row.stripOverlap,
      neighbourShare: row.neighbourShare,
    );
  }

  CropBox? _toCrop(BookSettingsRow row) {
    final double? left = row.cropLeft;
    final double? top = row.cropTop;
    final double? right = row.cropRight;
    final double? bottom = row.cropBottom;
    if (left == null || top == null || right == null || bottom == null) {
      return null;
    }
    return CropBox(left: left, top: top, right: right, bottom: bottom);
  }
}
