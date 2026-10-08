import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'avatar_image.dart';

/// Ingrandimento massimo nel ritaglio (spec K §10.3).
const maxCropZoom = 4.0;

/// Ingrandimento per uno scatto della rotella.
const _wheelStep = 1.1;

/// Opacità del velo fuori dal cerchio.
const _maskAlpha = 0.55;

/// L'ingrandimento letto dallo screen reader: una cifra decimale ("2,0×").
const _zoomPattern = '0.0';

/// La scala che fa riempire il riquadro all'immagine (zoom 1).
double cropBaseScale(Size image, double viewport) =>
    viewport / math.min(image.width, image.height);

/// L'immagine centrata nel riquadro, a zoom 1.
Offset centeredCropOffset(Size image, double viewport) {
  final scale = cropBaseScale(image, viewport);
  return Offset((viewport - image.width * scale) / 2,
      (viewport - image.height * scale) / 2);
}

/// Lo spostamento più vicino a [offset] con cui l'immagine copre ancora
/// tutto il riquadro.
Offset clampCropOffset(Offset offset, Size image, double viewport, double zoom) {
  final scale = cropBaseScale(image, viewport) * zoom;
  return Offset(
    offset.dx.clamp(math.min(viewport - image.width * scale, 0.0), 0.0),
    offset.dy.clamp(math.min(viewport - image.height * scale, 0.0), 0.0),
  );
}

/// La parte dell'immagine che si vede nel riquadro, in pixel dell'immagine.
CropArea cropAreaFor(Size image, double viewport, double zoom, Offset offset) {
  final scale = cropBaseScale(image, viewport) * zoom;
  return CropArea(-offset.dx / scale, -offset.dy / scale, viewport / scale);
}

/// La parte che si vede all'inizio: l'immagine centrata, a zoom 1.
CropArea initialCropArea(Size image, double viewport) =>
    cropAreaFor(image, viewport, 1, centeredCropOffset(image, viewport));

/// Il ritaglio quadrato (spec K §10.3): l'immagine si trascina e si
/// ingrandisce con la rotella o con il cursore, da "riempie il riquadro" a
/// [maxCropZoom]. A ogni cambio [onChanged] riceve la parte da tenere.
class AvatarCropper extends StatefulWidget {
  const AvatarCropper({
    super.key,
    required this.image,
    required this.viewport,
    required this.onChanged,
  });

  final WorkingImage image;

  /// Lato del riquadro.
  final double viewport;
  final ValueChanged<CropArea> onChanged;

  @override
  State<AvatarCropper> createState() => _AvatarCropperState();
}

class _AvatarCropperState extends State<AvatarCropper> {
  double _zoom = 1;
  late Offset _offset = centeredCropOffset(_size, widget.viewport);

  Size get _size =>
      Size(widget.image.width.toDouble(), widget.image.height.toDouble());

  void _update(double zoom, Offset offset) {
    setState(() {
      _zoom = zoom;
      _offset = clampCropOffset(offset, _size, widget.viewport, zoom);
    });
    widget.onChanged(cropAreaFor(_size, widget.viewport, _zoom, _offset));
  }

  /// Ingrandisce tenendo fermo il centro del riquadro.
  void _zoomTo(double zoom) {
    final next = zoom.clamp(1.0, maxCropZoom);
    final center = Offset(widget.viewport / 2, widget.viewport / 2);
    _update(next, center - (center - _offset) * (next / _zoom));
  }

  void _onPointerSignal(PointerSignalEvent event) {
    // Uno scorrimento solo orizzontale non è uno scatto della rotella.
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      _zoomTo(scroll.scrollDelta.dy < 0 ? _zoom * _wheelStep : _zoom / _wheelStep);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final zoomFormat =
        NumberFormat(_zoomPattern, Localizations.localeOf(context).toString());
    final scale = cropBaseScale(_size, widget.viewport) * _zoom;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            key: const Key('avatar-crop-area'),
            onPanUpdate: (details) => _update(_zoom, _offset + details.delta),
            child: SizedBox.square(
              dimension: widget.viewport,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Positioned(
                      left: _offset.dx,
                      top: _offset.dy,
                      width: _size.width * scale,
                      height: _size.height * scale,
                      child: Image.memory(widget.image.bytes,
                          fit: BoxFit.fill, gaplessPlayback: true),
                    ),
                    // Il cerchio che diventa l'avatar.
                    IgnorePointer(
                      child: CustomPaint(
                          size: Size.square(widget.viewport),
                          painter: _CircleMaskPainter()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: widget.viewport,
          // Un solo nodo: "Ingrandimento, 2,0×".
          child: MergeSemantics(
            child: Semantics(
              label: l.profileImageZoom,
              child: Slider(
                value: _zoom,
                min: 1,
                max: maxCropZoom,
                onChanged: _zoomTo,
                semanticFormatterCallback: (value) =>
                    '${zoomFormat.format(value)}×',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Il velo fuori dal cerchio, e il bordo del cerchio.
class _CircleMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = Path()..addOval(rect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(rect), circle),
      Paint()..color = WfColors.bg.withValues(alpha: _maskAlpha),
    );
    canvas.drawOval(
      rect.deflate(1),
      Paint()
        ..color = WfColors.cream
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CircleMaskPainter oldDelegate) => false;
}
