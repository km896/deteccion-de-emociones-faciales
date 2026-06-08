import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../services/camera_service.dart';
import '../services/emotion_analyzer.dart';
import '../services/fer_classifier.dart';
import '../storage/emotion_history_repository.dart';
import '../models/emotion_entry.dart';

// ─── Camera ────────────────────────────────────────────────────

final cameraServiceProvider = Provider<CameraService>((ref) {
  final service = CameraService();
  ref.onDispose(() => service.dispose());
  return service;
});

final cameraInitializedProvider = FutureProvider<bool>((ref) async {
  final service = ref.read(cameraServiceProvider);
  return service.initialize();
});

// ─── Detector ───────────────────────────────────────────────────

final emotionAnalyzerProvider = Provider<EmotionAnalyzer>((ref) {
  final analyzer = EmotionAnalyzer();
  ref.onDispose(() => analyzer.close());
  return analyzer;
});

// ─── FER Classifier ──────────────────────────────────────────────

final ferClassifierProvider = FutureProvider<FerClassifier>((ref) async {
  final classifier = FerClassifier();
  await classifier.load();
  ref.onDispose(() => classifier.dispose());
  return classifier;
});

// ─── Emotion Analysis State ─────────────────────────────────────

class EmotionAnalysisState {
  final EmotionResult? current;
  final List<Emotion> smoothingBuffer;
  final List<({Emotion emotion, DateTime time})> history;
  final Map<Emotion, int> counts;
  final int totalFrames;
  final DateTime sessionStart;

  const EmotionAnalysisState({
    this.current,
    required this.smoothingBuffer,
    required this.history,
    required this.counts,
    required this.totalFrames,
    required this.sessionStart,
  });

  EmotionAnalysisState.initial()
      : current = null,
        smoothingBuffer = const [],
        history = const [],
        counts = {for (final e in Emotion.values) e: 0},
        totalFrames = 0,
        sessionStart = DateTime.now();

  Emotion get dominant {
    if (totalFrames == 0) return Emotion.neutral;
    return counts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  String get sessionDuration {
    final diff = DateTime.now().difference(sessionStart);
    final m = diff.inMinutes.toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class EmotionAnalysisNotifier extends Notifier<EmotionAnalysisState> {
  @override
  EmotionAnalysisState build() => EmotionAnalysisState.initial();

  void processFrame(CameraImage image, Face face, InputImageRotation rotation) {
    final heuristic = EmotionAnalyzer.analyze(face);

    EmotionResult result;
    if (heuristic.emotion == Emotion.sleepy || heuristic.emotion == Emotion.thinking) {
      result = heuristic;
    } else {
      final classifier = ref.read(ferClassifierProvider).valueOrNull;
      if (classifier != null && classifier.isLoaded) {
        final fer = classifier.classify(image, face, rotation);

        final useTflite = fer.emotion != Emotion.neutral &&
            (fer.emotion != Emotion.surprised || fer.confidence > 0.7);
        result = useTflite ? _tfliteResult(fer.emotion, heuristic) : heuristic;
      } else {
        result = heuristic;
      }
    }

    final newBuffer = [...state.smoothingBuffer, result.emotion];
    if (newBuffer.length > 5) newBuffer.removeAt(0);

    final smoothed = EmotionAnalyzer.mostFrequent(newBuffer);

    final now = DateTime.now();
    final newHistory = [...state.history];
    if (newHistory.isEmpty ||
        now.difference(newHistory.last.time).inSeconds >= 2) {
      newHistory.add((emotion: smoothed, time: now));
      if (newHistory.length > 20) newHistory.removeAt(0);
    }

    final newCounts = Map<Emotion, int>.from(state.counts);
    newCounts[smoothed] = (newCounts[smoothed] ?? 0) + 1;

    state = EmotionAnalysisState(
      current: (result.emotion == smoothed) ? result : state.current,
      smoothingBuffer: newBuffer,
      history: newHistory,
      counts: newCounts,
      totalFrames: state.totalFrames + 1,
      sessionStart: state.sessionStart,
    );
  }

  static EmotionResult _tfliteResult(Emotion tfliteEmotion, EmotionResult heuristic) {
    return EmotionResult(
      emotion: tfliteEmotion,
      confidence: heuristic.confidence.clamp(0.5, 1.0),
      smilingProbability: heuristic.smilingProbability,
      leftEyeOpen: heuristic.leftEyeOpen,
      rightEyeOpen: heuristic.rightEyeOpen,
    );
  }

  void reset() {
    state = EmotionAnalysisState.initial();
  }
}

final emotionAnalysisProvider =
    NotifierProvider<EmotionAnalysisNotifier, EmotionAnalysisState>(
  EmotionAnalysisNotifier.new,
);

// ─── History Persistence ────────────────────────────────────────

final emotionHistoryRepoProvider = Provider<EmotionHistoryRepository>((ref) {
  return EmotionHistoryRepository();
});

final todayEmotionsProvider = FutureProvider<List<EmotionEntry>>((ref) async {
  final repo = ref.watch(emotionHistoryRepoProvider);
  return repo.getToday();
});
