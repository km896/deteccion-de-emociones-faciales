import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum Emotion { happy, sad, surprised, angry, neutral, sleepy, thinking }

class EmotionResult {
  final Emotion emotion;
  final double confidence;
  final double smilingProbability;
  final double leftEyeOpen;
  final double rightEyeOpen;

  const EmotionResult({
    required this.emotion,
    required this.confidence,
    required this.smilingProbability,
    required this.leftEyeOpen,
    required this.rightEyeOpen,
  });
}

class EmotionAnalyzer {
  late final FaceDetector _detector;

  EmotionAnalyzer({FaceDetectorMode mode = FaceDetectorMode.accurate}) {
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: mode,
        enableLandmarks: true,
        enableClassification: true,
        enableContours: true,
        enableTracking: true,
      ),
    );
  }

  FaceDetector get detector => _detector;

  static const _emotionColors = {
    Emotion.happy: _EmotionColors(0xFFFFD93D, 0xFF3D2800),
    Emotion.sad: _EmotionColors(0xFF6C9BCF, 0xFF0A1929),
    Emotion.surprised: _EmotionColors(0xFFFF8C42, 0xFF2D1400),
    Emotion.angry: _EmotionColors(0xFFEF5350, 0xFF1A0000),
    Emotion.sleepy: _EmotionColors(0xFF7E57C2, 0xFF0D0020),
    Emotion.thinking: _EmotionColors(0xFF26C6DA, 0xFF001520),
    Emotion.neutral: _EmotionColors(0xFF4F8EF7, 0xFF050D1F),
  };

  static int colorFor(Emotion e) => _emotionColors[e]!.accent;
  static int bgColorFor(Emotion e) => _emotionColors[e]!.background;
  static String emojiFor(Emotion e) => _emojiMap[e]!;
  static String nameFor(Emotion e) => _nameMap[e]!;

  static const _emojiMap = {
    Emotion.happy: '😄',
    Emotion.sad: '😢',
    Emotion.surprised: '😮',
    Emotion.angry: '😠',
    Emotion.sleepy: '😴',
    Emotion.thinking: '🤔',
    Emotion.neutral: '😐',
  };

  static const _nameMap = {
    Emotion.happy: 'Feliz',
    Emotion.sad: 'Triste',
    Emotion.surprised: 'Sorprendido',
    Emotion.angry: 'Enojado',
    Emotion.sleepy: 'Somnoliento',
    Emotion.thinking: 'Pensativo',
    Emotion.neutral: 'Neutral',
  };

  static Emotion classify(Face face) {
    final s = face.smilingProbability ?? 0.0;
    final l = face.leftEyeOpenProbability ?? 1.0;
    final r = face.rightEyeOpenProbability ?? 1.0;
    final ey = (face.headEulerAngleY ?? 0).abs();
    final ez = face.headEulerAngleZ ?? 0;
    final avg = (l + r) / 2;

    if (s > 0.55 && avg > 0.5) return Emotion.happy;
    if (ez.abs() > 30 && s < 0.35) return Emotion.thinking;
    if (avg < 0.6 && avg > 0.25 && s < 0.1 && ey < 15) return Emotion.angry;
    if (s < 0.15 && avg < 0.5 && avg > 0.25) return Emotion.sad;
    if (avg < 0.3) return Emotion.sleepy;
    return Emotion.neutral;
  }

  static EmotionResult analyze(Face face) {
    final emotion = classify(face);
    final s = face.smilingProbability ?? 0.0;
    final eye = ((face.leftEyeOpenProbability ?? 1.0) +
        (face.rightEyeOpenProbability ?? 1.0)) / 2;

    double conf;
    switch (emotion) {
      case Emotion.happy:
        conf = s;
      case Emotion.surprised:
        conf = eye;
      case Emotion.sleepy:
        conf = (1 - eye).clamp(0.0, 1.0);
      case Emotion.angry:
        conf = (1 - s).clamp(0.0, 1.0);
      case Emotion.sad:
        conf = (1 - s).clamp(0.0, 1.0);
      default:
        conf = 0.72;
    }

    return EmotionResult(
      emotion: emotion,
      confidence: conf,
      smilingProbability: s,
      leftEyeOpen: face.leftEyeOpenProbability ?? 1.0,
      rightEyeOpen: face.rightEyeOpenProbability ?? 1.0,
    );
  }

  static Emotion mostFrequent(List<Emotion> list) {
    final c = <Emotion, int>{};
    for (final e in list) {
      c[e] = (c[e] ?? 0) + 1;
    }
    return c.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  void close() => _detector.close();
}

class _EmotionColors {
  final int accent;
  final int background;
  const _EmotionColors(this.accent, this.background);
}
