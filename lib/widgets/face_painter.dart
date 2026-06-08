import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FacePainter extends CustomPainter {
  final Face? face;
  final Size imageSize;
  final Color color;
  final bool isFrontCamera;
  final InputImageRotation rotation;

  FacePainter({
    required this.face,
    required this.imageSize,
    required this.color,
    this.isFrontCamera = true,
    this.rotation = InputImageRotation.rotation270deg,
  });

  Offset transform(
      double x,
      double y,
      Size size,
      ) {
    double nx = x;
    double ny = y;

    // Rotar coordenadas según orientación
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        final tx = y;
        final ty = imageSize.width - x;
        nx = tx;
        ny = ty;
        break;
      case InputImageRotation.rotation270deg:
        final tx = imageSize.height - y;
        final ty = x;
        nx = tx;
        ny = ty;
        break;
      case InputImageRotation.rotation180deg:
        nx = imageSize.width - x;
        ny = imageSize.height - y;
        break;
      case InputImageRotation.rotation0deg:
        break;
    }

    // Calcular dimensiones de la imagen ROTADA para escala y espejo
    final rotated = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final srcWidth = rotated ? imageSize.height : imageSize.width;
    final srcHeight = rotated ? imageSize.width : imageSize.height;

    // Espejo horizontal si es cámara frontal
    if (isFrontCamera) {
      nx = srcWidth - nx;
    }

    final scaleX = size.width / srcWidth;
    final scaleY = size.height / srcHeight;
    final scale = scaleX > scaleY ? scaleX : scaleY;

    final dx = (size.width - srcWidth * scale) / 2;
    final dy = (size.height - srcHeight * scale) / 2;

    return Offset(nx * scale + dx, ny * scale + dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (face == null || imageSize == Size.zero) return;

    final paintBox = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.8);

    final paintPoint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    final paintLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.6);

    // Caja de rostro
    final box = face!.boundingBox;
    final tl = transform(box.left.toDouble(), box.top.toDouble(), size);
    final tr = transform(box.right.toDouble(), box.top.toDouble(), size);
    final bl = transform(box.left.toDouble(), box.bottom.toDouble(), size);
    final br = transform(box.right.toDouble(), box.bottom.toDouble(), size);

    final rect = Rect.fromPoints(
      Offset(
        [tl.dx, tr.dx, bl.dx, br.dx].reduce((a, b) => a < b ? a : b),
        [tl.dy, tr.dy, bl.dy, br.dy].reduce((a, b) => a < b ? a : b),
      ),
      Offset(
        [tl.dx, tr.dx, bl.dx, br.dx].reduce((a, b) => a > b ? a : b),
        [tl.dy, tr.dy, bl.dy, br.dy].reduce((a, b) => a > b ? a : b),
      ),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      paintBox,
    );

    // Landmarks
    final landmarkTypes = [
      FaceLandmarkType.leftEye,
      FaceLandmarkType.rightEye,
      FaceLandmarkType.noseBase,
      FaceLandmarkType.leftCheek,
      FaceLandmarkType.rightCheek,
      FaceLandmarkType.leftEar,
      FaceLandmarkType.rightEar,
      FaceLandmarkType.bottomMouth,
      FaceLandmarkType.leftMouth,
      FaceLandmarkType.rightMouth,
    ];

    final points = <FaceLandmarkType, Offset>{};
    for (final type in landmarkTypes) {
      final lm = face!.landmarks[type];
      if (lm != null) {
        final p = transform(
          lm.position.x.toDouble(),
          lm.position.y.toDouble(),
          size,
        );
        points[type] = p;
        canvas.drawCircle(p, 3.5, paintPoint);
      }
    }

    // Líneas entre landmarks (malla básica)
    void drawLine(FaceLandmarkType a, FaceLandmarkType b) {
      final pa = points[a];
      final pb = points[b];
      if (pa != null && pb != null) {
        canvas.drawLine(pa, pb, paintLine);
      }
    }

    drawLine(FaceLandmarkType.leftEye, FaceLandmarkType.rightEye);
    drawLine(FaceLandmarkType.leftEye, FaceLandmarkType.noseBase);
    drawLine(FaceLandmarkType.rightEye, FaceLandmarkType.noseBase);
    drawLine(FaceLandmarkType.noseBase, FaceLandmarkType.bottomMouth);
    drawLine(FaceLandmarkType.leftMouth, FaceLandmarkType.bottomMouth);
    drawLine(FaceLandmarkType.rightMouth, FaceLandmarkType.bottomMouth);
    drawLine(FaceLandmarkType.leftMouth, FaceLandmarkType.rightMouth);
    drawLine(FaceLandmarkType.leftCheek, FaceLandmarkType.leftMouth);
    drawLine(FaceLandmarkType.rightCheek, FaceLandmarkType.rightMouth);
    drawLine(FaceLandmarkType.leftEar, FaceLandmarkType.leftCheek);
    drawLine(FaceLandmarkType.rightEar, FaceLandmarkType.rightCheek);

    // Contornos (si están disponibles)
    final contours = [
      FaceContourType.face,
      FaceContourType.leftEyebrowTop,
      FaceContourType.rightEyebrowTop,
      FaceContourType.leftEye,
      FaceContourType.rightEye,
      FaceContourType.upperLipTop,
      FaceContourType.lowerLipBottom,
      FaceContourType.noseBridge,
    ];

    final contourPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: 0.7);

    for (final type in contours) {
      final contour = face!.contours[type];
      if (contour == null || contour.points.isEmpty) continue;
      final path = Path();
      final first = transform(
        contour.points.first.x.toDouble(),
        contour.points.first.y.toDouble(),
        size,
      );
      path.moveTo(first.dx, first.dy);
      for (int i = 1; i < contour.points.length; i++) {
        final p = transform(
          contour.points[i].x.toDouble(),
          contour.points[i].y.toDouble(),
          size,
        );
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, contourPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FacePainter old) {
    if (old.imageSize != imageSize ||
        old.color != color ||
        old.rotation != rotation ||
        old.isFrontCamera != isFrontCamera) {
      return true;
    }
    if (face == null && old.face == null) return false;
    if (face == null || old.face == null) return true;
    return face!.boundingBox != old.face!.boundingBox;
  }
}
