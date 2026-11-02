/// Паспорт файла книги: один проход по объектам страниц PDFium, без
/// отрисовки (ALG-MAP-18, шаг S58, разведка RS-06).
///
/// Правило «что за файл» — в `domain/map/file_passport.dart`; здесь
/// только сбор фактов: сколько знаков в слое, есть ли невидимый текст,
/// какая доля страницы под самой большой картинкой, её разрешение и
/// цветность, сколько векторных объектов, кто сохранил файл и сколько
/// в нём закладок.
///
/// Почему напрямую через PDFium, а не через pdfrx: pdfrx отдаёт текст и
/// оглавление, но не объекты страницы, их режим вывода и картинки. Сам
/// PDFium уже в сборке — его привязки `pdfium_dart` (MIT) приходят
/// вместе с pdfrx, своей нативной сборки не нужно.
///
/// **PDFium не терпит одновременных вызовов.** Поэтому проход идёт в
/// фоновом потоке самого pdfrx (`PdfrxEntryFunctions.instance.compute`):
/// там же pdfrx зовёт PDFium для чтения, и вызовы встают в одну очередь.
///
/// Кто зовёт: подготовка книги для карты (F-MAP-18).
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium;
import 'package:pdfrx/pdfrx.dart'
    show Pdfrx, PdfrxEntryFunctions, pdfrxFlutterInitialize;

import '../../domain/library/book_source.dart';
import '../../domain/library/book_storage.dart';
import '../../domain/map/book_passport.dart';
import '../../domain/map/file_passport.dart';
import '../files/descriptor_book_handle.dart';

/// Больше этого числа закладок не считаем: защита от зацикленного
/// оглавления в битом файле.
const int kMaxBookmarks = 100000;

/// Глубже этого форма в форме не разбирается — как `get_objects` у
/// pypdfium2 в шаге 46.
const int kMaxFormDepth = 15;

/// Читает паспорт книги.
class PdfiumPassportReader implements PassportReader {
  /// Создаёт чтение паспорта.
  ///
  /// [initialize] — тот же инициализатор pdfrx, что у открывателя книги
  /// (`PdfrxDocumentOpener`): по умолчанию — Flutter, в тесте — свой.
  PdfiumPassportReader({
    required BookStorage storage,
    Future<void> Function()? initialize,
  }) : _storage = storage,
       _initialize = initialize ?? pdfrxFlutterInitialize;

  final BookStorage _storage;
  final Future<void> Function() _initialize;

  /// Паспорт книги из [source]; `null` — файл открыт, но PDFium его не
  /// разобрал (битый, пароль). Файла нет или до него нет пути —
  /// [PassportUnavailableException]: это может пройти, и паспорт
  /// прочитают в другой раз.
  @override
  Future<FilePassport?> read(BookSource source) async {
    final BookHandle book;
    try {
      book = await _storage.open(source);
    } on BookUnavailableException catch (error) {
      throw PassportUnavailableException(source, cause: error);
    }
    try {
      // Путь для PDFium. У документа Android его нет, но есть дескриптор:
      // `/proc/self/fd/N` — тот же открытый файл, видимый как путь.
      final String? path =
          book.path ??
          (book is DescriptorBookHandle
              ? '/proc/self/fd/${book.descriptor}'
              : null);
      if (path == null) {
        throw PassportUnavailableException(source);
      }
      await _initialize();
      // Инициализатор Flutter готовит только папки и шрифты; сам PDFium
      // запускает `init` (FPDF_InitLibrary), а pdfrx зовёт его лишь при
      // открытии книги. Без этого первый проход по незапущенному PDFium
      // уронил бы приложение — например, когда весь текст уже в базе и
      // ни одна книга до паспорта не открывалась. Повторный вызов ничего
      // не делает.
      await PdfrxEntryFunctions.instance.init();
      final _RawPassport? raw = await PdfrxEntryFunctions.instance.compute(
        _passOver,
        (path, Pdfrx.pdfiumModulePath),
      );
      if (raw == null) {
        return null;
      }
      return passportOf(
        raw.pages,
        producer: raw.producer,
        creator: raw.creator,
        bookmarks: raw.bookmarks,
      );
    } finally {
      await book.close();
    }
  }
}

/// Что проход принёс из фонового потока: факты страниц и метаданные.
class _RawPassport {
  const _RawPassport(this.pages, this.producer, this.creator, this.bookmarks);

  final List<PageFacts> pages;
  final String producer;
  final String creator;
  final int bookmarks;
}

/// Привязки PDFium в фоновом потоке — одни на поток.
pdfium.PDFium? _library;

/// Проход по файлу. Работает в фоновом потоке pdfrx; [job] — путь к
/// файлу и путь к библиотеке PDFium, если pdfrx его задал (статические
/// поля у каждого потока свои, поэтому путь передаётся явно — иначе в
/// поток могла бы загрузиться вторая, другая библиотека).
_RawPassport? _passOver((String, String?) job) {
  final (String path, String? module) = job;
  final pdfium.PDFium lib = _library ??= pdfium.getPdfium(modulePath: module);
  return using((Arena arena) {
    // Память под рамку и сведения картинки — одна на весь проход: на
    // скане в тысячу страниц не тысяча мелких выделений.
    final _Scratch scratch = _Scratch(arena);
    final pdfium.FPDF_DOCUMENT document = lib.FPDF_LoadDocument(
      path.toNativeUtf8(allocator: arena).cast<Char>(),
      nullptr,
    );
    if (document == nullptr) {
      return null;
    }
    try {
      final int count = lib.FPDF_GetPageCount(document);
      final List<PageFacts> pages = <PageFacts>[
        for (int index = 0; index < count; index++)
          _pageFacts(lib, document, index, scratch),
      ];
      return _RawPassport(
        pages,
        _metaText(lib, document, 'Producer', arena),
        _metaText(lib, document, 'Creator', arena),
        _bookmarks(lib, document),
      );
    } finally {
      lib.FPDF_CloseDocument(document);
    }
  });
}

/// Память, которую проход переиспользует.
class _Scratch {
  _Scratch(Arena arena)
    : box = arena<Float>(4),
      meta = arena<pdfium.FPDF_IMAGEOBJ_METADATA>();

  final Pointer<Float> box;
  final Pointer<pdfium.FPDF_IMAGEOBJ_METADATA> meta;
}

/// Счётчики одной страницы по ходу прохода.
class _Tally {
  int textObjects = 0;
  int invisible = 0;
  int images = 0;
  int paths = 0;
  double imageArea = 0;
  double bestArea = 0;
  double? dpi;
  int? bitsPerPixel;
}

/// Факты страницы [index] (ALG-MAP-18, шаг 1).
PageFacts _pageFacts(
  pdfium.PDFium lib,
  pdfium.FPDF_DOCUMENT document,
  int index,
  _Scratch scratch,
) {
  final pdfium.FPDF_PAGE page = lib.FPDF_LoadPage(document, index);
  if (page == nullptr) {
    // Страница не загрузилась — для паспорта она «пустая».
    return const PageFacts(chars: 0, imageShare: 0);
  }
  try {
    final double width = lib.FPDF_GetPageWidthF(page);
    final double height = lib.FPDF_GetPageHeightF(page);
    final _Tally tally = _Tally();
    final int objects = lib.FPDFPage_CountObjects(page);
    for (int i = 0; i < objects; i++) {
      _visit(lib, page, lib.FPDFPage_GetObject(page, i), tally, scratch, 0);
    }
    final pdfium.FPDF_TEXTPAGE text = lib.FPDFText_LoadPage(page);
    int chars = 0;
    if (text != nullptr) {
      chars = lib.FPDFText_CountChars(text);
      lib.FPDFText_ClosePage(text);
    }
    final double area = width * height;
    final double share = area > 0 ? tally.imageArea / area : 0;
    final bool big = share >= kBigImageShare;
    return PageFacts(
      chars: chars < 0 ? 0 : chars,
      imageShare: share,
      textObjects: tally.textObjects,
      invisibleTextObjects: tally.invisible,
      images: tally.images,
      paths: tally.paths,
      // Как в шаге 46: качество картинки — только у листа-картинки.
      dpi: big ? tally.dpi : null,
      bitsPerPixel: big ? tally.bitsPerPixel : null,
    );
  } finally {
    lib.FPDF_ClosePage(page);
  }
}

/// Один объект страницы; форма разбирается вглубь (сканы часто кладут
/// картинку внутрь формы).
void _visit(
  pdfium.PDFium lib,
  pdfium.FPDF_PAGE page,
  pdfium.FPDF_PAGEOBJECT object,
  _Tally tally,
  _Scratch scratch,
  int depth,
) {
  if (object == nullptr) return;
  switch (lib.FPDFPageObj_GetType(object)) {
    case pdfium.FPDF_PAGEOBJ_FORM:
      if (depth >= kMaxFormDepth) return;
      final int inner = lib.FPDFFormObj_CountObjects(object);
      for (int i = 0; i < inner; i++) {
        _visit(
          lib,
          page,
          lib.FPDFFormObj_GetObject(object, i),
          tally,
          scratch,
          depth + 1,
        );
      }
    case pdfium.FPDF_PAGEOBJ_TEXT:
      tally.textObjects++;
      if (lib.FPDFTextObj_GetTextRenderMode(object) ==
          pdfium.FPDF_TEXT_RENDERMODE.FPDF_TEXTRENDERMODE_INVISIBLE) {
        tally.invisible++;
      }
    case pdfium.FPDF_PAGEOBJ_IMAGE:
      tally.images++;
      final Pointer<Float> box = scratch.box;
      if (lib.FPDFPageObj_GetBounds(object, box, box + 1, box + 2, box + 3) ==
          0) {
        return;
      }
      final double w = box[2] - box[0];
      final double h = box[3] - box[1];
      final double area = (w > 0 ? w : 0) * (h > 0 ? h : 0);
      if (area > tally.imageArea) tally.imageArea = area;
      if (area >= tally.bestArea) {
        tally.bestArea = area;
        final Pointer<pdfium.FPDF_IMAGEOBJ_METADATA> meta = scratch.meta;
        if (lib.FPDFImageObj_GetImageMetadata(object, page, meta) != 0) {
          tally.dpi = (meta.ref.horizontal_dpi + meta.ref.vertical_dpi) / 2;
          tally.bitsPerPixel = meta.ref.bits_per_pixel;
        } else {
          tally.dpi = null;
          tally.bitsPerPixel = null;
        }
      }
    case pdfium.FPDF_PAGEOBJ_PATH:
      tally.paths++;
    default:
      break;
  }
}

/// Строка метаданных [tag] (`Producer`, `Creator`); пусто — нет.
String _metaText(
  pdfium.PDFium lib,
  pdfium.FPDF_DOCUMENT document,
  String tag,
  Arena arena,
) {
  final Pointer<Char> name = tag.toNativeUtf8(allocator: arena).cast<Char>();
  // Первый вызов — сколько байт нужно (UTF-16LE с нулём в конце).
  final int size = lib.FPDF_GetMetaText(document, name, nullptr, 0);
  if (size <= 2) return '';
  final Pointer<Uint16> buffer = arena<Uint16>(size ~/ 2);
  lib.FPDF_GetMetaText(document, name, buffer.cast<Void>(), size);
  return String.fromCharCodes(buffer.asTypedList(size ~/ 2 - 1)).trim();
}

/// Сколько закладок в файле — на всех уровнях оглавления.
int _bookmarks(pdfium.PDFium lib, pdfium.FPDF_DOCUMENT document) {
  int total = 0;
  final List<pdfium.FPDF_BOOKMARK> stack = <pdfium.FPDF_BOOKMARK>[
    lib.FPDFBookmark_GetFirstChild(document, nullptr),
  ];
  while (stack.isNotEmpty && total < kMaxBookmarks) {
    pdfium.FPDF_BOOKMARK item = stack.removeLast();
    while (item != nullptr && total < kMaxBookmarks) {
      total++;
      stack.add(lib.FPDFBookmark_GetFirstChild(document, item));
      item = lib.FPDFBookmark_GetNextSibling(document, item);
    }
  }
  return total;
}
