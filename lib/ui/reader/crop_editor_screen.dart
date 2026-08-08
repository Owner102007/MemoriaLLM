import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/reading/reader_document.dart';
import '../../domain/reading/reading.dart';

/// Ручная правка рамки обрезки.
///
/// Автообрезка ошибается на нетипичных макетах — на полях с пометками, на
/// сканах с загнутым углом, на книгах, свёрстанных «в край». Здесь рамку
/// можно подвинуть руками, и она применится **ко всей книге**: править её
/// на каждой странице по отдельности никто не станет.
class CropEditorScreen extends StatefulWidget {
  /// Создаёт экран.
  const CropEditorScreen({
    required this.document,
    required this.pageNumber,
    required this.initial,
    super.key,
  });

  /// Открытая книга.
  final ReaderDocument document;

  /// Страница, на которой удобно править: обычно текущая.
  final int pageNumber;

  /// Рамка, с которой начинаем.
  final CropBox initial;

  @override
  State<CropEditorScreen> createState() => _CropEditorScreenState();
}

class _CropEditorScreenState extends State<CropEditorScreen> {
  /// Наименьшая сторона рамки при перетаскивании.
  static const double _minSide = 0.1;

  ui.Image? _preview;
  late CropBox _box;
  double _aspect = 0.7;

  @override
  void initState() {
    super.initState();
    _box = widget.initial.isValid ? widget.initial : CropBox.full;
    final PageGeometry geometry = widget.document.geometry(widget.pageNumber);
    if (geometry.width > 0 && geometry.height > 0) {
      _aspect = geometry.width / geometry.height;
    }
    unawaited(_loadPreview());
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    // Превью намеренно небольшое: рамку двигают по контуру текста, а не
    // по засечкам, и полноразмерный рендер здесь только тормозил бы.
    const int width = 700;
    final int height = (width / _aspect).round().clamp(64, 4000);
    PageRaster? raster;
    try {
      raster = await widget.document.renderPage(
        widget.pageNumber,
        width: width,
        height: height,
      );
    } on Object {
      raster = null;
    }
    if (raster == null || !raster.isConsistent || !mounted) {
      return;
    }
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      raster.pixels,
      raster.width,
      raster.height,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );
    final ui.Image image = await completer.future;
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() => _preview = image);
  }

  void _drag(_Edge edge, Offset delta, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final double dx = delta.dx / size.width;
    final double dy = delta.dy / size.height;
    setState(() {
      switch (edge) {
        case _Edge.left:
          _box = _withLeft(_box.left + dx);
        case _Edge.right:
          _box = _withRight(_box.right + dx);
        case _Edge.top:
          _box = _withTop(_box.top + dy);
        case _Edge.bottom:
          _box = _withBottom(_box.bottom + dy);
      }
    });
  }

  CropBox _withLeft(double value) {
    final double left = value.clamp(0.0, _box.right - _minSide);
    return CropBox(
      left: left,
      top: _box.top,
      right: _box.right,
      bottom: _box.bottom,
    );
  }

  CropBox _withRight(double value) {
    final double right = value.clamp(_box.left + _minSide, 1.0);
    return CropBox(
      left: _box.left,
      top: _box.top,
      right: right,
      bottom: _box.bottom,
    );
  }

  CropBox _withTop(double value) {
    final double top = value.clamp(0.0, _box.bottom - _minSide);
    return CropBox(
      left: _box.left,
      top: top,
      right: _box.right,
      bottom: _box.bottom,
    );
  }

  CropBox _withBottom(double value) {
    final double bottom = value.clamp(_box.top + _minSide, 1.0);
    return CropBox(
      left: _box.left,
      top: _box.top,
      right: _box.right,
      bottom: bottom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Рамка страницы'),
        actions: <Widget>[
          TextButton(
            key: const Key('crop-reset'),
            onPressed: () => setState(() => _box = CropBox.full),
            child: const Text('Сброс'),
          ),
          TextButton(
            key: const Key('crop-apply'),
            onPressed: () => Navigator.of(context).pop(_box),
            child: const Text('Применить'),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Рамка применится ко всей книге и заменит автообрезку.',
              key: const Key('crop-hint'),
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: AspectRatio(
                  aspectRatio: _aspect,
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints limits) {
                      final Size size = Size(limits.maxWidth, limits.maxHeight);
                      return Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: ColoredBox(
                              color: theme.colorScheme.surface,
                              child: _preview == null
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                        key: Key('crop-loading'),
                                      ),
                                    )
                                  : RawImage(image: _preview, fit: BoxFit.fill),
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _CropPainter(
                                  box: _box,
                                  line: theme.colorScheme.primary,
                                  shade: theme.colorScheme.surface.withValues(
                                    alpha: 0.72,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _Handle(
                            edgeKey: const Key('crop-left'),
                            edge: _Edge.left,
                            box: _box,
                            size: size,
                            onDrag: _drag,
                          ),
                          _Handle(
                            edgeKey: const Key('crop-right'),
                            edge: _Edge.right,
                            box: _box,
                            size: size,
                            onDrag: _drag,
                          ),
                          _Handle(
                            edgeKey: const Key('crop-top'),
                            edge: _Edge.top,
                            box: _box,
                            size: size,
                            onDrag: _drag,
                          ),
                          _Handle(
                            edgeKey: const Key('crop-bottom'),
                            edge: _Edge.bottom,
                            box: _box,
                            size: size,
                            onDrag: _drag,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Edge { left, top, right, bottom }

class _Handle extends StatelessWidget {
  const _Handle({
    required this.edgeKey,
    required this.edge,
    required this.box,
    required this.size,
    required this.onDrag,
  });

  /// Ширина полосы, за которую тянут край.
  static const double _thickness = 36;

  final Key edgeKey;
  final _Edge edge;
  final CropBox box;
  final Size size;
  final void Function(_Edge edge, Offset delta, Size size) onDrag;

  @override
  Widget build(BuildContext context) {
    final bool vertical = edge == _Edge.left || edge == _Edge.right;
    final double along = vertical
        ? (edge == _Edge.left ? box.left : box.right) * size.width
        : (edge == _Edge.top ? box.top : box.bottom) * size.height;
    return Positioned(
      left: vertical ? along - _thickness / 2 : box.left * size.width,
      top: vertical ? box.top * size.height : along - _thickness / 2,
      width: vertical ? _thickness : box.width * size.width,
      height: vertical ? box.height * size.height : _thickness,
      child: GestureDetector(
        key: edgeKey,
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (DragUpdateDetails details) =>
            onDrag(edge, details.delta, size),
        child: Center(
          child: Container(
            width: vertical ? 4 : 32,
            height: vertical ? 32 : 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter({
    required this.box,
    required this.line,
    required this.shade,
  });

  final CropBox box;
  final Color line;
  final Color shade;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect inner = Rect.fromLTRB(
      box.left * size.width,
      box.top * size.height,
      box.right * size.width,
      box.bottom * size.height,
    );
    final Path outside = Path()
      ..addRect(Offset.zero & size)
      ..addRect(inner)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = shade);
    canvas.drawRect(
      inner,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.box != box ||
      oldDelegate.line != line ||
      oldDelegate.shade != shade;
}
