import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../core/services/camera_service.dart';
import '../core/services/emotion_analyzer.dart';
import '../core/providers/emotion_providers.dart';
import '../core/providers/reminder_providers.dart';
import '../core/models/emotion_entry.dart';
import 'history_page.dart';
import '../widgets/face_painter.dart';

class EmotionPage extends ConsumerStatefulWidget {
  final String? userName;
  const EmotionPage({super.key, this.userName});

  @override
  ConsumerState<EmotionPage> createState() => _EmotionPageState();
}

class _EmotionPageState extends ConsumerState<EmotionPage>
    with TickerProviderStateMixin {
  AnimationController? _pulseAnim;
  AnimationController? _emotionAnim;

  bool _isDetecting = false;
  bool _showStats = false;
  bool _hasFace = false;
  Face? _currentFace;
  Size _imageSize = Size.zero;
  DateTime _lastProcessed = DateTime.now();

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _emotionAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    Future.microtask(_initCamera);
  }

  Future<void> _initCamera() async {
    final cameraService = ref.read(cameraServiceProvider);
    final ok = await cameraService.initialize();
    if (!mounted || !ok) return;
    await cameraService.startStream(_onCameraImage);
    ref.read(reminderProvider.notifier).start();
    if (mounted) setState(() {});
  }

  void _onCameraImage(CameraImage image) {
    final now = DateTime.now();
    if (now.difference(_lastProcessed).inMilliseconds < 1000) return;
    if (_isDetecting) return;
    _lastProcessed = now;
    _processImage(image);
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isDetecting) return;
    if (ref.read(reminderProvider).phase == ReminderPhase.resting) return;
    _isDetecting = true;

    try {
      final cameraService = ref.read(cameraServiceProvider);
      final analyzer = ref.read(emotionAnalyzerProvider);

      final inputImage = cameraService.buildInputImage(image);
      final faces = await analyzer.detector.processImage(inputImage);
      if (!mounted) return;

      if (faces.isEmpty) {
        setState(() {
          _hasFace = false;
          _currentFace = null;
        });
        return;
      }

      final face = faces.first;
      setState(() {
        _hasFace = true;
        _currentFace = face;
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      });

      ref.read(emotionAnalysisProvider.notifier).processFrame(image, face, cameraService.rotation);
    } catch (e) {
      debugPrint('❌ Process error: $e');
    } finally {
      _isDetecting = false;
    }
  }

  @override
  void dispose() {
    _pulseAnim?.dispose();
    _emotionAnim?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(emotionAnalysisProvider, (prev, next) {
      if (prev != null && next.history.length > prev.history.length) {
        final repo = ref.read(emotionHistoryRepoProvider);
        final last = next.history.last;
        final confidence = next.current?.confidence ?? 0.7;
        repo.saveEntry(EmotionEntry(
          emotion: last.emotion.name,
          confidence: confidence,
          timestamp: last.time,
          userName: widget.userName,
        ));
      }
    });
    final cameraService = ref.watch(cameraServiceProvider);
    final state = ref.watch(emotionAnalysisProvider);
    final reminderState = ref.watch(reminderProvider);

    if (!cameraService.isInitialized || cameraService.controller == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF060810),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: Color(0xFF4F8EF7)),
            SizedBox(height: 16),
            Text('Iniciando cámara...',
                style: TextStyle(color: Colors.white54, fontSize: 14)),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: _showStats
          ? _buildStatsView(state)
          : _buildCameraView(cameraService, state, reminderState),
    );
  }

  Widget _buildCameraView(CameraService cameraService, EmotionAnalysisState state, ReminderState reminderState) {
    final currentEmotion = state.current?.emotion ?? Emotion.neutral;
    final dColor = Color(EmotionAnalyzer.colorFor(currentEmotion));
    final dName = EmotionAnalyzer.nameFor(currentEmotion);
    final dEmoji = EmotionAnalyzer.emojiFor(currentEmotion);
    final previewSize = cameraService.controller!.value.previewSize!;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: previewSize.height,
              height: previewSize.width,
              child: Stack(
                children: [
                  CameraPreview(cameraService.controller!),
                  if (_currentFace != null && _imageSize != Size.zero)
                    CustomPaint(
                      painter: FacePainter(
                        face: _currentFace,
                        imageSize: _imageSize,
                        color: dColor,
                        isFrontCamera: cameraService.description?.lensDirection == CameraLensDirection.front,
                        rotation: cameraService.rotation,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        AnimatedContainer(
          duration: const Duration(milliseconds: 700),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withValues(alpha: 0.45),
                Colors.transparent,
                Color(EmotionAnalyzer.bgColorFor(currentEmotion)).withValues(alpha: 0.7),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.4, 1.0],
            ),
          ),
        ),

        SafeArea(
          child: Column(children: [
            _buildHeader(state),
            const Spacer(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _hasFace
                  ? _EmotionBadge(
                      key: ValueKey('${currentEmotion}_${state.current?.confidence}'),
                      emoji: dEmoji,
                      name: dName,
                      color: dColor,
                      confidence: state.current?.confidence ?? 0.7,
                      pulseAnim: _pulseAnim,
                    )
                  : _SearchingBadge(),
            ),
            const SizedBox(height: 16),
            _buildBottomPanel(state, currentEmotion, dColor),
            const SizedBox(height: 16),
          ]),
        ),

        if (reminderState.phase == ReminderPhase.resting)
          _RestOverlay(
            secondsLeft: reminderState.secondsLeft,
            onSkip: () => ref.read(reminderProvider.notifier).skipRest(),
          ),
      ],
    );
  }

  Widget _buildHeader(EmotionAnalysisState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              widget.userName != null && widget.userName!.isNotEmpty
                  ? 'Hola, ${widget.userName}'
                  : 'Análisis Facial',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4)),
          Row(children: [
            AnimatedBuilder(
              animation: _pulseAnim!,
              builder: (_, __) => Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hasFace
                      ? Color.lerp(
                          const Color(0xFF4CAF50),
                          const Color(0xFF8BC34A),
                          _pulseAnim!.value)!
                      : Colors.white24,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(state.sessionDuration,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12)),
            const SizedBox(width: 6),
            Text('· ${state.totalFrames} análisis',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 12)),
          ]),
        ]),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.bar_chart_rounded, color: Colors.white38, size: 20),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => HistoryPage(userName: widget.userName),
            ),
          ),
        ),
        Consumer(builder: (_, ref, __) {
          final rState = ref.watch(reminderProvider);
          final active = rState.phase != ReminderPhase.off;
          return GestureDetector(
            onTap: () => ref.read(reminderProvider.notifier).toggle(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: active
                    ? const Color(0xFF26C6DA).withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.08),
                border: Border.all(
                  color: active
                      ? const Color(0xFF26C6DA).withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  active ? Icons.visibility : Icons.visibility_off,
                  size: 14,
                  color: active ? const Color(0xFF26C6DA) : Colors.white38,
                ),
                const SizedBox(width: 4),
                Text(
                  active ? '20-20-20' : 'Apagado',
                  style: TextStyle(
                    color: active ? const Color(0xFF26C6DA) : Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ),
          );
        }),
      ]),
    );
  }

  Widget _buildBottomPanel(EmotionAnalysisState state, Emotion currentEmotion, Color dColor) {
    final result = state.current;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        if (_hasFace && result != null)
          Row(children: [
            _MetricCard(
                label: 'Sonrisa',
                value: result.smilingProbability,
                icon: '😊',
                color: const Color(0xFFFFD93D)),
            const SizedBox(width: 8),
            _MetricCard(
                label: 'Ojo izq',
                value: result.leftEyeOpen,
                icon: '👁',
                color: const Color(0xFF4F8EF7)),
            const SizedBox(width: 8),
            _MetricCard(
                label: 'Ojo der',
                value: result.rightEyeOpen,
                icon: '👁',
                color: const Color(0xFF7B5EA7)),
          ]),
        if (_hasFace && result != null) const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: state.history.isEmpty
                ? const SizedBox()
                : SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: state.history.length,
                      itemBuilder: (_, i) {
                        final entry = state.history[state.history.length - 1 - i];
                        final edColor = Color(EmotionAnalyzer.colorFor(entry.emotion));
                        final edEmoji = EmotionAnalyzer.emojiFor(entry.emotion);
                        final isLatest = i == 0;
                        return Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: isLatest
                                ? edColor.withValues(alpha: 0.25)
                                : Colors.black.withValues(alpha: 0.4),
                            border: Border.all(
                                color: isLatest
                                    ? edColor.withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Row(children: [
                            Text(edEmoji,
                                style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 4),
                            Text(_timeAgo(entry.time),
                                style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.4),
                                    fontSize: 9)),
                          ]),
                        );
                      },
                    ),
                  ),
          ),
          GestureDetector(
            onTap: () => setState(() => _showStats = true),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.black.withValues(alpha: 0.55),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Row(children: [
                const Icon(Icons.bar_chart_rounded,
                    color: Colors.white60, size: 16),
                const SizedBox(width: 6),
                Text('Stats',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildStatsView(EmotionAnalysisState state) {
    final domData = EmotionAnalyzer.nameFor(state.dominant);
    final domEmoji = EmotionAnalyzer.emojiFor(state.dominant);
    final domColor = Color(EmotionAnalyzer.colorFor(state.dominant));
    final domBg = Color(EmotionAnalyzer.bgColorFor(state.dominant));

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF060810), domBg],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(children: [
              GestureDetector(
                onTap: () => setState(() => _showStats = false),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 16),
                ),
              ),
              const SizedBox(width: 14),
              const Text('Estadísticas',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5)),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: Colors.white.withValues(alpha: 0.05),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Row(children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sesión activa',
                              style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.4),
                                  fontSize: 11)),
                          Text(state.sessionDuration,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1.5)),
                          Text('${state.totalFrames} análisis',
                              style: TextStyle(
                                  color: Colors.white
                                      .withValues(alpha: 0.35),
                                  fontSize: 12)),
                        ]),
                    const Spacer(),
                    Column(children: [
                      Text(domEmoji,
                          style: const TextStyle(fontSize: 64)),
                      Text('Dominante',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 12)),
                      Text(domData,
                          style: TextStyle(
                              color: domColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w800)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: Colors.white.withValues(alpha: 0.04),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Distribución emocional',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      ...Emotion.values.map((e) {
                        final count = state.counts[e] ?? 0;
                        final pct = state.totalFrames > 0 ? count / state.totalFrames : 0.0;
                        final edColor = Color(EmotionAnalyzer.colorFor(e));
                        final edEmoji = EmotionAnalyzer.emojiFor(e);
                        final edName = EmotionAnalyzer.nameFor(e);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(children: [
                            Text(edEmoji,
                                style: const TextStyle(fontSize: 24)),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 82,
                              child: Text(edName,
                                  style: TextStyle(
                                      color: Colors.white
                                          .withValues(alpha: 0.65),
                                      fontSize: 12)),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: pct,
                                  minHeight: 10,
                                  backgroundColor: Colors.white
                                      .withValues(alpha: 0.06),
                                  valueColor:
                                      AlwaysStoppedAnimation(edColor),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 36,
                              child: Text('${(pct * 100).toInt()}%',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      color: pct > 0
                                          ? edColor
                                          : Colors.white24,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ]),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (state.history.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Historial',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: state.history.reversed.map((entry) {
                            final edColor = Color(EmotionAnalyzer.colorFor(entry.emotion));
                            final edEmoji = EmotionAnalyzer.emojiFor(entry.emotion);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: edColor.withValues(alpha: 0.12),
                                border: Border.all(
                                    color:
                                        edColor.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(edEmoji,
                                        style:
                                            const TextStyle(fontSize: 18)),
                                    const SizedBox(width: 5),
                                    Text(_timeAgo(entry.time),
                                        style: TextStyle(
                                            color: edColor
                                                .withValues(alpha: 0.8),
                                            fontSize: 11)),
                                  ]),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t).inSeconds;
    if (diff < 5) return 'ahora';
    if (diff < 60) return '${diff}s';
    return '${diff ~/ 60}m';
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────

class _EmotionBadge extends StatelessWidget {
  final String emoji, name;
  final Color color;
  final double confidence;
  final AnimationController? pulseAnim;

  const _EmotionBadge({
    super.key,
    required this.emoji,
    required this.name,
    required this.color,
    required this.confidence,
    this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnim!,
      builder: (_, child) => Transform.scale(
        scale: 1.0 + pulseAnim!.value * 0.03,
        child: child,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          color: Colors.black.withValues(alpha: 0.6),
          border: Border.all(color: color.withValues(alpha: 0.7), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 42)),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5)),
            Text('${(confidence * 100).toInt()}% confianza',
                style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }
}

class _SearchingBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('searching'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        color: Colors.black.withValues(alpha: 0.5),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(width: 10),
        Text('Buscando rostro...',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
      ]),
    );
  }
}

class _RestOverlay extends StatelessWidget {
  final int secondsLeft;
  final VoidCallback onSkip;
  const _RestOverlay({required this.secondsLeft, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF060810).withValues(alpha: 0.92),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🌿', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 24),
          const Text(
            'Descansa tu vista',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Mira a lo lejos durante 20 segundos',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: secondsLeft / 20,
                  strokeWidth: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor:
                      const AlwaysStoppedAnimation(Color(0xFF4F8EF7)),
                ),
                Center(
                  child: Text(
                    '$secondsLeft',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          TextButton.icon(
            onPressed: onSkip,
            icon: const Icon(Icons.close, size: 16, color: Colors.white38),
            label: const Text('Saltar',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),
        ]),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final double value;
  final String icon;
  final Color color;
  const _MetricCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.black.withValues(alpha: 0.55),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 3),
          Text('${(value * 100).toInt()}%',
              style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 10)),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ]),
      ),
    );
  }
}
