import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'emotion_analyzer.dart';

class FerResult {
  final Emotion emotion;
  final double confidence;
  const FerResult(this.emotion, this.confidence);
}

class FerClassifier {
  static const int _inputSize = 48;
  Interpreter? _interpreter;

  static const ferLabels = [
    'angry', 'disgust', 'fear', 'happy', 'sad', 'surprise', 'neutral',
  ];

  bool get isLoaded => _interpreter != null;

  Future<void> load() async {
    try {
      _interpreter = await Interpreter.fromAsset('emotion_model.tflite');
      debugPrint('FER model loaded');
    } catch (e) {
      debugPrint('FER load failed: $e — heuristic fallback');
      _interpreter = null;
    }
  }

  FerResult classify(CameraImage image, Face face, InputImageRotation rotation) {
    if (_interpreter == null) return const FerResult(Emotion.neutral, 0.0);

    try {
      final flat = _preprocess(image, face, rotation);
      if (flat == null) return const FerResult(Emotion.neutral, 0.0);

      final input = flat.reshape([1, _inputSize, _inputSize, 1]);
      final output = List.filled(ferLabels.length, 0.0).reshape([1, ferLabels.length]);
      _interpreter!.run(input, output);

      final probs = output[0] as List<double>;
      final maxIdx = probs.indexOf(probs.reduce((a, b) => a > b ? a : b));
      final maxProb = probs[maxIdx];

      if (maxProb < 0.5) return const FerResult(Emotion.neutral, 0.0);

      return FerResult(_mapFerToEmotion(maxIdx), maxProb);
    } catch (e) {
      debugPrint('TFLite inference error: $e');
      return const FerResult(Emotion.neutral, 0.0);
    }
  }

  Float32List? _preprocess(CameraImage image, Face face, InputImageRotation rotation) {
    final plane = image.planes.first;
    final srcW = image.width;
    final srcH = image.height;

    final box = face.boundingBox;
    double cropLeft = box.left;
    double cropRight = box.right;

    if (Platform.isAndroid) {
      final ml = cropLeft;
      final mr = cropRight;
      cropLeft = srcW - mr;
      cropRight = srcW - ml;
    }

    final cropT = box.top.toDouble().clamp(0, srcH.toDouble());
    final cropB = box.bottom.toDouble().clamp(0, srcH.toDouble());
    final cropL = cropLeft.clamp(0, srcW.toDouble()).toInt();
    final cropR = cropRight.clamp(0, srcW.toDouble()).toInt();
    final cropT2 = cropT.toInt();
    final cropB2 = cropB.toInt();
    final cropW = (cropR - cropL).clamp(1, srcW);
    final cropH = (cropB2 - cropT2).clamp(1, srcH);

    final yBytes = plane.bytes;
    final facePixels = Uint8List(cropW * cropH);
    for (int y = 0; y < cropH; y++) {
      final srcRow = (cropT2 + y) * srcW;
      final dstRow = y * cropW;
      for (int x = 0; x < cropW; x++) {
        facePixels[dstRow + x] = yBytes[srcRow + cropL + x];
      }
    }

    return _resizeAndNormalize(facePixels, cropW, cropH);
  }

  Float32List _resizeAndNormalize(Uint8List src, int srcW, int srcH) {
    final dst = Float32List(_inputSize * _inputSize);
    const dstW = _inputSize;
    const dstH = _inputSize;

    for (int dy = 0; dy < dstH; dy++) {
      for (int dx = 0; dx < dstW; dx++) {
        final gx = dx * srcW / dstW;
        final gy = dy * srcH / dstH;
        final x1 = gx.floor();
        final y1 = gy.floor();
        final x2 = (x1 + 1).clamp(0, srcW - 1);
        final y2 = (y1 + 1).clamp(0, srcH - 1);
        final xFrac = gx - x1;
        final yFrac = gy - y1;

        final tl = src[y1 * srcW + x1];
        final tr = src[y1 * srcW + x2];
        final bl = src[y2 * srcW + x1];
        final br = src[y2 * srcW + x2];

        final top = tl + (tr - tl) * xFrac;
        final bot = bl + (br - bl) * xFrac;
        final val = top + (bot - top) * yFrac;

        dst[dy * dstW + dx] = val / 255.0;
      }
    }

    return dst;
  }

  Emotion _mapFerToEmotion(int idx) {
    switch (idx) {
      case 0: return Emotion.angry;
      case 1: return Emotion.angry;
      case 2: return Emotion.neutral;
      case 3: return Emotion.happy;
      case 4: return Emotion.sad;
      case 5: return Emotion.surprised;
      case 6: return Emotion.neutral;
      default: return Emotion.neutral;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
