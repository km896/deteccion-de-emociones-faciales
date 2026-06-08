import 'dart:io' show Platform;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/user_model.dart';
import '../services/notification_service.dart';
import '../utils/firebase_utils.dart';
import '../widgets/face_painter.dart';
import 'emotion_page.dart';

enum RegisterStep {
  center,
  turnLeft,
  turnRight,
  tiltUp,
  tiltDown,
  smile,
  done,
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with TickerProviderStateMixin {
  late CameraController _cameraController;
  late FaceDetector _faceDetector;
  late AnimationController _stepAnim;

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isSaving = false;
  bool _nameEntered = false;
  InputImageRotation _currentRotation = InputImageRotation.rotation270deg;

  RegisterStep _currentStep = RegisterStep.center;
  Face? _currentFace;
  Size _imageSize = Size.zero;

  // Guarda el vector de cada paso por separado
  final Map<String, List<double>> _stepVectors = {};
  int _stepHoldFrames = 0;
  static const _framesNeeded = 15;
  double _stepProgress = 0.0;

  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _stepAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: false,
      ),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      debugPrint('❌ Camera permission denied');
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      debugPrint('No cameras available');
      return;
    }
    final frontCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await _cameraController.initialize();
    
    if (Platform.isAndroid) {
      _currentRotation = InputImageRotationValue.fromRawValue(frontCamera.sensorOrientation) 
          ?? InputImageRotation.rotation270deg;
    } else {
      _currentRotation = InputImageRotation.rotation90deg;
    }
    
    if (mounted) setState(() => _isInitialized = true);
    _cameraController.startImageStream(_processFrame);
  }

  void _processFrame(CameraImage image) async {
    if (!_nameEntered) return;
    if (_isProcessing || _isSaving || _currentStep == RegisterStep.done) return;
    _isProcessing = true;

    try {
      final plane = image.planes.first;

      final inputImage = InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: _currentRotation,
          format: InputImageFormat.nv21,
          bytesPerRow: plane.bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted) return;

      if (faces.isEmpty) {
        setState(() {
          _currentFace = null;
          _stepHoldFrames = 0;
          _stepProgress = 0.0;
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
        });
        return;
      }

      final face = faces.first;
      setState(() {
        _currentFace = face;
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      });

      _evaluateStep(face);
    } catch (e) {
      debugPrint('Error frame: $e');
    } finally {
      _isProcessing = false;
    }
  }

  void _evaluateStep(Face face) {
    final eulerY = face.headEulerAngleY ?? 0;
    final eulerX = face.headEulerAngleX ?? 0;
    final smiling = face.smilingProbability ?? 0;

    bool isCorrect = false;
    switch (_currentStep) {
      case RegisterStep.center:
        isCorrect = eulerY.abs() < 10 && eulerX.abs() < 10;
        break;
      case RegisterStep.turnLeft:
        isCorrect = eulerY > 20;
        break;
      case RegisterStep.turnRight:
        isCorrect = eulerY < -20;
        break;
      case RegisterStep.tiltUp:
        isCorrect = eulerX > 12;
        break;
      case RegisterStep.tiltDown:
        isCorrect = eulerX < -12;
        break;
      case RegisterStep.smile:
        isCorrect = smiling > 0.7;
        break;
      case RegisterStep.done:
        return;
    }

    if (isCorrect) {
      _stepHoldFrames++;
      setState(() {
        _stepProgress = (_stepHoldFrames / _framesNeeded).clamp(0.0, 1.0);
      });
      if (_stepHoldFrames >= _framesNeeded) {
        _captureStepData(face);
        _advanceStep();
      }
    } else {
      setState(() {
        _stepHoldFrames = 0;
        _stepProgress = 0.0;
      });
    }
  }

  // ✅ Extrae vector de landmarks normalizado — MISMO método que en login
  List<double> _extractVector(Face face) {
    final features = <double>[];

    // Landmarks normalizados 0..1
    for (final lm in face.landmarks.values) {
      if (lm != null) {
        features.add(lm.position.x / 480.0);
        features.add(lm.position.y / 640.0);
      }
    }

    // Ángulos normalizados
    features.add((face.headEulerAngleY ?? 0) / 90.0);
    features.add((face.headEulerAngleX ?? 0) / 90.0);
    features.add((face.headEulerAngleZ ?? 0) / 90.0);

    // Clasificadores
    features.add(face.smilingProbability ?? 0.0);
    features.add(face.leftEyeOpenProbability ?? 1.0);
    features.add(face.rightEyeOpenProbability ?? 1.0);

    return features;
  }

  void _captureStepData(Face face) {
    final stepName = _currentStep.name;
    _stepVectors[stepName] = _extractVector(face);
    debugPrint('📸 Paso capturado: $stepName — ${_stepVectors[stepName]!.length} features');
  }

  void _advanceStep() {
    _stepHoldFrames = 0;
    _stepProgress = 0.0;
    _stepAnim.forward(from: 0);

    setState(() {
      switch (_currentStep) {
        case RegisterStep.center:
          _currentStep = RegisterStep.turnLeft;
          break;
        case RegisterStep.turnLeft:
          _currentStep = RegisterStep.turnRight;
          break;
        case RegisterStep.turnRight:
          _currentStep = RegisterStep.tiltUp;
          break;
        case RegisterStep.tiltUp:
          _currentStep = RegisterStep.tiltDown;
          break;
        case RegisterStep.tiltDown:
          _currentStep = RegisterStep.smile;
          break;
        case RegisterStep.smile:
          _currentStep = RegisterStep.done;
          _finishRegistration();
          break;
        case RegisterStep.done:
          break;
      }
    });
  }

  Future<void> _finishRegistration() async {
    setState(() => _isSaving = true);

    try {
      // Vector del centro como faceData principal
      final centerVector = _stepVectors['center'] ?? List.filled(30, 0.0);

      debugPrint('💾 Guardando ${_stepVectors.length} pasos: ${_stepVectors.keys.join(", ")}');

      final userName = _nameController.text.trim().isEmpty
          ? 'Usuario_${DateTime.now().millisecondsSinceEpoch}'
          : _nameController.text.trim();

      final user = UserModel(
        name: userName,
        faceData: centerVector,
        stepData: Map<String, List<double>>.from(_stepVectors),
        createdAt: DateTime.now(),
      );

      final success = await saveUser(user).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⏱️ Timeout guardando');
          return false;
        },
      );

      if (success && user.id != null) {
        await NotificationService.setUserId(user.id!);
      }

      if (mounted) {
        setState(() => _isSaving = false);
        _showResult(success);
      }
    } catch (e) {
      debugPrint('❌ Error _finishRegistration: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        _showResult(false);
      }
    }
  }

  void _showResult(bool success) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF1A1F45),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: success
                      ? const Color(0xFF4F8EF7).withValues(alpha: 0.15)
                      : Colors.red.withValues(alpha: 0.15),
                ),
                child: Icon(
                  success
                      ? Icons.check_circle_rounded
                      : Icons.error_rounded,
                  color:
                  success ? const Color(0xFF4F8EF7) : Colors.redAccent,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                success ? '¡Registro exitoso!' : 'Error al guardar',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800),
              ),
              if (success) ...[
                const SizedBox(height: 8),
                Text(
                  'Rostro registrado correctamente.\nYa puedes iniciar sesión.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 14,
                      height: 1.5),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    if (success) {
                      // ✅ Cerrar cámara y detector ANTES de navegar
                      if (_cameraController.value.isStreamingImages) {
                        _cameraController.stopImageStream();
                      }
                      _cameraController.dispose();
                      _faceDetector.close();
                      
                      Navigator.pushReplacement(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => EmotionPage(
                            userName: _nameController.text.trim().isNotEmpty
                                ? _nameController.text.trim()
                                : null,
                          ),
                          transitionsBuilder: (_, anim, __, child) =>
                              FadeTransition(opacity: anim, child: child),
                          transitionDuration: const Duration(milliseconds: 500),
                        ),
                      );
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F8EF7),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                      success ? 'Ir a análisis' : 'Continuar',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _StepInfo get _stepInfo {
    switch (_currentStep) {
      case RegisterStep.center:
        return _StepInfo(Icons.face_rounded, 'Mira al frente',
            'Centra tu rostro en el círculo', null);
      case RegisterStep.turnLeft:
        return _StepInfo(Icons.arrow_back_rounded, 'Gira a la izquierda',
            'Voltea lentamente hacia la izquierda', 'left');
      case RegisterStep.turnRight:
        return _StepInfo(Icons.arrow_forward_rounded, 'Gira a la derecha',
            'Voltea lentamente hacia la derecha', 'right');
      case RegisterStep.tiltUp:
        return _StepInfo(Icons.arrow_upward_rounded, 'Levanta la cara',
            'Inclina la cabeza hacia arriba', 'up');
      case RegisterStep.tiltDown:
        return _StepInfo(Icons.arrow_downward_rounded, 'Baja la cara',
            'Inclina la cabeza hacia abajo', 'down');
      case RegisterStep.smile:
        return _StepInfo(Icons.sentiment_very_satisfied_rounded,
            '¡Sonríe!', 'Muestra una sonrisa natural', null);
      case RegisterStep.done:
        return _StepInfo(Icons.check_circle_rounded, 'Guardando...',
            'Procesando datos faciales', null);
    }
  }

  int get _stepIndex => RegisterStep.values.indexOf(_currentStep);
  int get _totalSteps => RegisterStep.values.length - 1;

  @override
  void dispose() {
    _cameraController.dispose();
    _faceDetector.close();
    _stepAnim.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Widget _buildNameInput() {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0E27), Color(0xFF12183D)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4F8EF7).withValues(alpha: 0.15),
                    border: Border.all(
                      color: const Color(0xFF4F8EF7).withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Icon(
                    Icons.person_add_rounded,
                    color: Color(0xFF4F8EF7),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Ingresa tu nombre',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Este nombre aparecerá en el análisis de emociones',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Tu nombre',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF4F8EF7), width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _startRegistration(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _startRegistration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F8EF7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Continuar',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _startRegistration() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresa tu nombre'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() => _nameEntered = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_nameEntered) {
      return _buildNameInput();
    }

    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E27),
        body: Center(
            child:
            CircularProgressIndicator(color: Color(0xFF4F8EF7))),
      );
    }

    final info = _stepInfo;
    final ringColor = _currentFace != null
        ? const Color(0xFF4F8EF7)
        : Colors.white.withValues(alpha: 0.2);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0E27), Color(0xFF12183D)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color:
                              Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 17),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text('Registrar rostro',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5)),
                  ],
                ),
              ),

              // Barra de pasos
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: List.generate(_totalSteps, (i) {
                    final done = i < _stepIndex;
                    final active = i == _stepIndex;
                    return Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: done
                              ? const Color(0xFF4F8EF7)
                              : active
                              ? const Color(0xFF4F8EF7)
                              .withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 24),

              // Instrucción del paso
              SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.3, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                    parent: _stepAnim, curve: Curves.easeOut)),
                child: FadeTransition(
                  opacity: _stepAnim,
                  child: Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF4F8EF7)
                              .withValues(alpha: 0.12),
                          border: Border.all(
                              color: const Color(0xFF4F8EF7)
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Icon(info.icon,
                            color: const Color(0xFF4F8EF7), size: 26),
                      ),
                      const SizedBox(height: 10),
                      Text(info.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5)),
                      const SizedBox(height: 4),
                      Text(info.subtitle,
                          style: TextStyle(
                              color:
                              Colors.white.withValues(alpha: 0.45),
                              fontSize: 14)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Visor cámara
              Center(
                child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 300,
                        height: 300,
                        child: CircularProgressIndicator(
                          value: _stepProgress,
                          strokeWidth: 5,
                          backgroundColor:
                          Colors.white.withValues(alpha: 0.06),
                          valueColor:
                          AlwaysStoppedAnimation(ringColor),
                          strokeCap: StrokeCap.round,
                        ),
                      ),

                      // Cámara circular sin recorte
                      Container(
                        width: 276,
                        height: 276,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: SizedBox(
                            width: 276,
                            height: 276,
                            child: OverflowBox(
                              maxWidth: double.infinity,
                              maxHeight: double.infinity,
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _cameraController
                                      .value.previewSize!.height,
                                  height: _cameraController
                                      .value.previewSize!.width,
                                  child: Stack(
                                    children: [
                                      CameraPreview(_cameraController),
                                      if (_currentFace != null &&
                                          _imageSize != Size.zero)
                                        CustomPaint(
                                          painter: FacePainter(
                                            face: _currentFace,
                                            imageSize: _imageSize,
                                            color: const Color(0xFF4F8EF7),
                                            isFrontCamera: true,
                                            rotation: _currentRotation,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      if (info.arrow != null)
                        _ArrowGuide(direction: info.arrow!),
                    ]),
              ),

              const SizedBox(height: 20),

              // Estado
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Paso ${_stepIndex + 1} de $_totalSteps',
                        style: TextStyle(
                            color:
                            Colors.white.withValues(alpha: 0.4),
                            fontSize: 13)),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _currentFace == null
                            ? 'No se detecta rostro'
                            : _stepProgress > 0
                            ? '${(_stepProgress * 100).toInt()}%'
                            : 'Sigue la instrucción',
                        key: ValueKey(_currentFace == null),
                        style: TextStyle(
                            color: _currentFace == null
                                ? Colors.redAccent
                                : const Color(0xFF4F8EF7),
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              if (_isSaving)
                const Padding(
                  padding: EdgeInsets.only(bottom: 32),
                  child: Column(
                    children: [
                      CircularProgressIndicator(
                          color: Color(0xFF4F8EF7)),
                      SizedBox(height: 12),
                      Text('Guardando en Firebase...',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 13)),
                    ],
                  ),
                )
              else
                const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepInfo {
  final IconData icon;
  final String title, subtitle;
  final String? arrow;
  _StepInfo(this.icon, this.title, this.subtitle, this.arrow);
}

class _ArrowGuide extends StatefulWidget {
  final String direction;
  const _ArrowGuide({required this.direction});

  @override
  State<_ArrowGuide> createState() => _ArrowGuideState();
}

class _ArrowGuideState extends State<_ArrowGuide>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0, end: 14).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHoriz =
        widget.direction == 'left' || widget.direction == 'right';
    final isNeg =
        widget.direction == 'left' || widget.direction == 'up';

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) {
        final offset = isNeg ? -_anim.value : _anim.value;
        return Transform.translate(
          offset: isHoriz ? Offset(offset, 0) : Offset(0, offset),
          child: child,
        );
      },
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF4F8EF7).withValues(alpha: 0.25),
          border: Border.all(
              color: const Color(0xFF4F8EF7).withValues(alpha: 0.6),
              width: 2),
        ),
        child: Icon(
          widget.direction == 'left'
              ? Icons.arrow_back_rounded
              : widget.direction == 'right'
              ? Icons.arrow_forward_rounded
              : widget.direction == 'up'
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded,
          color: const Color(0xFF4F8EF7),
          size: 26,
        ),
      ),
    );
  }
}