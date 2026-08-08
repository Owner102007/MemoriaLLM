import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/reading/reading_filter.dart';

/// Кладёт светофильтр на страницу и только на неё.
///
/// Оборачивать надо просмотрщик, а не весь экран: панели, оглавление и
/// поиск должны оставаться в обычных цветах, иначе ночью читатель не
/// найдёт кнопку выхода.
///
/// Работают два пути. Основной — фрагментный шейдер: он один умеет гамму
/// и двойную инверсию картинок. Запасной — цветовая матрица движка: она
/// есть везде, но гамму берёт приближённо, а картинки при инверсии
/// превращает в негативы. Запасной путь включается сам там, где
/// шейдерных фильтров нет (им нужен Impeller), и в тестах, где шейдеры
/// не собираются вовсе.
class ReadingFilterLayer extends StatefulWidget {
  /// Создаёт слой.
  const ReadingFilterLayer({
    required this.filter,
    required this.child,
    super.key,
  });

  /// Путь к скомпилированному шейдеру.
  static const String shaderAsset = 'shaders/reading_filter.frag';

  /// Настроенный фильтр.
  final ReadingFilterPipeline filter;

  /// Страница.
  final Widget child;

  @override
  State<ReadingFilterLayer> createState() => _ReadingFilterLayerState();
}

class _ReadingFilterLayerState extends State<ReadingFilterLayer> {
  static Future<void>? _programRequest;
  static ui.FragmentProgram? _program;

  ui.FragmentShader? _shader;
  ui.ImageFilter? _imageFilter;
  ReadingFilterPipeline? _builtFor;

  @override
  void initState() {
    super.initState();
    unawaited(_requestProgram());
  }

  @override
  void dispose() {
    _imageFilter = null;
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }

  Future<void> _requestProgram() async {
    if (_program != null || !ui.ImageFilter.isShaderFilterSupported) {
      return;
    }
    await (_programRequest ??= _loadProgram());
    if (mounted && _program != null) {
      setState(() {});
    }
  }

  static Future<void> _loadProgram() async {
    try {
      _program = await ui.FragmentProgram.fromAsset(
        ReadingFilterLayer.shaderAsset,
      );
    } on Object {
      // Шейдер не собран (так бывает в тестах) или движок его не принял.
      // Это не повод оставить читателя без фильтра — есть запасной путь.
      _program = null;
    }
  }

  /// Готовит фильтр-шейдер, пересобирая его только при смене настроек.
  ///
  /// Шейдер живёт один на слой: создавать его в каждом кадре — значит
  /// плодить объекты движка на каждое движение пальца.
  ui.ImageFilter? _shaderFilter() {
    final ui.FragmentProgram? program = _program;
    if (program == null || !ui.ImageFilter.isShaderFilterSupported) {
      return null;
    }
    if (_imageFilter != null && _builtFor == widget.filter) {
      return _imageFilter;
    }
    final ui.FragmentShader shader = _shader ??= program.fragmentShader();
    final List<double> values = widget.filter.uniformValues();
    // Первые две ячейки — `uSize`, их заполняет сам движок размером
    // текстуры; наши значения идут следом, в порядке `uniformNames`.
    for (int i = 0; i < values.length; i++) {
      shader.setFloat(2 + i, values[i]);
    }
    try {
      _imageFilter = ui.ImageFilter.shader(shader);
      _builtFor = widget.filter;
    } on Object {
      _imageFilter = null;
      _builtFor = null;
    }
    return _imageFilter;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.filter.isIdentity) {
      return widget.child;
    }
    final ui.ImageFilter? shaderFilter = _shaderFilter();
    if (shaderFilter != null) {
      return ImageFiltered(imageFilter: shaderFilter, child: widget.child);
    }
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(widget.filter.colorMatrix()),
      child: widget.child,
    );
  }
}
