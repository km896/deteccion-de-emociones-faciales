import 'dart:io' show Platform;
import 'dart:ui' show Size;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class CameraService {
  CameraController? _controller;
  CameraDescription? _description;
  InputImageRotation _rotation = InputImageRotation.rotation270deg;

  CameraController? get controller => _controller;
  CameraDescription? get description => _description;
  InputImageRotation get rotation => _rotation;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  Future<bool> initialize({ResolutionPreset preset = ResolutionPreset.medium}) async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return false;

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _description = front;

      if (Platform.isAndroid) {
        _rotation = InputImageRotationValue.fromRawValue(front.sensorOrientation)
            ?? InputImageRotation.rotation270deg;
      } else {
        _rotation = InputImageRotation.rotation90deg;
      }

      _controller = CameraController(
        front,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _controller!.initialize();
      return true;
    } catch (e) {
      debugPrint('❌ CameraService.init: $e');
      return false;
    }
  }

  bool get isStreaming => _controller?.value.isStreamingImages ?? false;

  Future<void> startStream(Function(CameraImage) onImage) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (isStreaming) await stopStream();
    await _controller!.startImageStream(onImage);
  }

  Future<void> stopStream() async {
    if (isStreaming) {
      await _controller!.stopImageStream();
    }
  }

  InputImage buildInputImage(CameraImage image) {
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotation,
        format: Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> dispose() async {
    await stopStream();
    _controller?.dispose();
    _controller = null;
    _description = null;
  }
}
