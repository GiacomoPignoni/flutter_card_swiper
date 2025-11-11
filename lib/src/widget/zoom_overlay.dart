import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart';

class ZoomOverlay extends StatefulWidget {
  const ZoomOverlay({
    required this.child,
    this.childForZoom,
    this.buildContextOverlayState,
    this.minScale,
    this.maxScale,
    this.animationDuration = const Duration(milliseconds: 100),
    this.animationCurve = Curves.fastOutSlowIn,
    this.modalBarrierColor,
    this.onScaleStart,
    this.onScaleStop,
    this.onTap,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    super.key,
  });

  final Widget child;
  final WidgetBuilder? childForZoom;
  final BuildContext? buildContextOverlayState;
  final double? minScale;
  final double? maxScale;
  final Duration animationDuration;
  final Curve animationCurve;
  final Color? modalBarrierColor;

  final VoidCallback? onScaleStart;
  final VoidCallback? onScaleStop;

  final VoidCallback? onTap;
  final GestureScaleStartCallback? onPanStart;
  final GestureScaleUpdateCallback? onPanUpdate;
  final GestureScaleEndCallback? onPanEnd;

  @override
  State<ZoomOverlay> createState() => _ZoomOverlayState();
}

class _ZoomOverlayState extends State<ZoomOverlay> with TickerProviderStateMixin {
  Matrix4? _matrix = Matrix4.identity();
  late Offset _startFocalPoint;
  late Animation<Matrix4> _animationReset;
  late AnimationController _controllerReset;
  OverlayEntry? _overlayEntry;
  bool _isZooming = false;
  Matrix4 _transformMatrix = Matrix4.identity();

  final _transformWidget = GlobalKey<_TransformWidgetState>();

  @override
  void initState() {
    super.initState();

    _controllerReset = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    _controllerReset
      ..addListener(() {
        _transformWidget.currentState?.setMatrix(_animationReset.value);
      })
      ..addStatusListener(
        (status) {
          if (status == AnimationStatus.completed) hide();
        },
      );
  }

  @override
  void dispose() {
    _controllerReset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: onScaleStart,
      onScaleUpdate: onScaleUpdate,
      onScaleEnd: onScaleEnd,
      onTap: widget.onTap,
      child: Opacity(opacity: _isZooming ? 0 : 1, child: widget.child),
    );
  }

  void onScaleStart(ScaleStartDetails details) {
    if (details.pointerCount < 2) {
      widget.onPanStart?.call(details);
      return;
    }

    // call start callback before everything else
    widget.onScaleStart?.call();
    _startFocalPoint = details.focalPoint;

    _matrix = Matrix4.identity();

    // create an matrix of where the image is on the screen for the overlay
    final renderObject = context.findRenderObject();
    if (renderObject == null) {
      return;
    }

    _transformMatrix = Matrix4.identity();

    show();

    if (mounted) {
      setState(() {
        _isZooming = true;
      });
    }
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      widget.onPanUpdate?.call(details);
      return;
    }
    if (!_isZooming || _controllerReset.isAnimating) return;

    final translationDelta = details.focalPoint - _startFocalPoint;

    final translate = Matrix4.translation(
      Vector3(translationDelta.dx, translationDelta.dy, 0),
    );

    final renderObject = context.findRenderObject();
    if (renderObject == null) {
      return;
    }
    final renderBox = renderObject as RenderBox;
    final focalPoint = renderBox.globalToLocal(
      details.focalPoint - translationDelta,
    );

    var scaleby = details.scale;
    if (widget.minScale != null && scaleby < widget.minScale!) {
      scaleby = widget.minScale ?? 0;
    }

    if (widget.maxScale != null && scaleby > widget.maxScale!) {
      scaleby = widget.maxScale ?? 0;
    }

    final dx = (1 - scaleby) * focalPoint.dx;
    final dy = (1 - scaleby) * focalPoint.dy;

    final scale = Matrix4(scaleby, 0, 0, 0, 0, scaleby, 0, 0, 0, 0, 1, 0, dx, dy, 0, 1);

    _matrix = (translate * scale) as Matrix4;

    if (_transformWidget.currentState != null) {
      _transformWidget.currentState!.setMatrix(_matrix);
    }
  }

  void onScaleEnd(ScaleEndDetails details) {
    if (details.pointerCount < 2) {
      widget.onPanEnd?.call(details);
    }
    if (!_isZooming || _controllerReset.isAnimating) return;
    _animationReset = Matrix4Tween(
      begin: _matrix,
      end: Matrix4.identity(),
    ).animate(
      CurvedAnimation(
        parent: _controllerReset,
        curve: widget.animationCurve,
      ),
    );
    _controllerReset
      ..reset()
      ..forward();

    // call end callback function when scale ends
    widget.onScaleStop?.call();
  }

  Widget _build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          ModalBarrier(
            color: widget.modalBarrierColor,
          ),
          _TransformWidget(
            key: _transformWidget,
            matrix: _transformMatrix,
            child: widget.childForZoom?.call(context) ?? widget.child,
          ),
        ],
      ),
    );
  }

  Future<void> show() async {
    if (!_isZooming) {
      final overlayState = Overlay.of(
        widget.buildContextOverlayState ?? context,
      );
      _overlayEntry = OverlayEntry(builder: _build);
      overlayState.insert(_overlayEntry!);
    }
  }

  Future<void> hide() async {
    setState(() {
      _isZooming = false;
    });

    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

class _TransformWidget extends StatefulWidget {
  const _TransformWidget({
    required this.child,
    required this.matrix,
    super.key,
  });

  final Widget child;
  final Matrix4 matrix;

  @override
  _TransformWidgetState createState() => _TransformWidgetState();
}

class _TransformWidgetState extends State<_TransformWidget> {
  Matrix4? _matrix = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    return Transform(
      transform: widget.matrix * (_matrix ?? Matrix4.identity()) as Matrix4,
      child: widget.child,
    );
  }

  void setMatrix(Matrix4? matrix) {
    setState(() {
      _matrix = matrix;
    });
  }
}
