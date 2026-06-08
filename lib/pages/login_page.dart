import 'dart:io' show Platform;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_service.dart';
import '../utils/firebase_utils.dart';
import '../widgets/face_painter.dart';
import 'emotion_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  late CameraController _cameraController;
  late FaceDetector _faceDetector;
  late AnimationController _scanAnim;
  late AnimationController _successAnim;

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isSearching = false;
  bool _loginSuccess = false;

  Face? _currentFace;
  Size _imageSize = Size.zero;
  String _statusMsg = 'Coloca tu rostro en el círculo';
  int _stableFrames = 0;
  InputImageRotation _currentRotation = InputImageRotation.rotation270deg;

  // ✅ FIX: Flag para saber si el stream está activo
  bool _streamActive = false;

  @override
  void initState() {
    super.initState();
    _scanAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _successAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: true,
        enableClassification: true,
      ),
    );

    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        debugPrint('❌ Camera permission denied');
        if (mounted) {
          setState(() => _statusMsg = 'Permiso de cámara requerido');
        }
        return;
      }

      final cameras = await availableCameras();
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

      if (!mounted) return;

      setState(() => _isInitialized = true);

      // ✅ FIX: Marcar stream como activo
      _streamActive = true;
      await _cameraController.startImageStream(_processFrame);
    } catch (e) {
      debugPrint('❌ Error inicializando cámara: $e');
      if (mounted) {
        setState(() => _statusMsg = 'Error al iniciar la cámara');
      }
    }
  }

  void _processFrame(CameraImage image) async {
    if (_isProcessing || _isSearching || _loginSuccess) return;
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
          _stableFrames = 0;
          _statusMsg = 'No se detecta ningún rostro';
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
        });
        return;
      }

      final face = faces.first;
      final eulerY = face.headEulerAngleY ?? 0;
      final eulerX = face.headEulerAngleX ?? 0;
      final boxWidth = face.boundingBox.width;

      setState(() {
        _currentFace = face;
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      });

      // ✅ Verificar orientación
      if (eulerY.abs() > 15 || eulerX.abs() > 15) {
        setState(() {
          _stableFrames = 0;
          _statusMsg = 'Mira directo a la cámara';
        });
        return;
      }

      // ✅ Verificar distancia mínima
      if (boxWidth < 80) {
        setState(() {
          _stableFrames = 0;
          _statusMsg = 'Acércate más a la cámara';
        });
        return;
      }

      // ✅ Verificar distancia máxima
      if (boxWidth > 400) {
        setState(() {
          _stableFrames = 0;
          _statusMsg = 'Aléjate un poco de la cámara';
        });
        return;
      }

      setState(() {
        _stableFrames++;
        _statusMsg = 'Reconociendo... mantén la posición';
      });

      if (_stableFrames >= 10) {
        _stableFrames = 0;
        await _attemptLogin(face);
      }
    } catch (e) {
      debugPrint('❌ Error procesando frame: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _attemptLogin(Face face) async {
    _isSearching = true;

    // ✅ FIX: Detener stream de forma segura
    if (_streamActive) {
      _streamActive = false;
      await _cameraController.stopImageStream();
    }

    if (!mounted) return;
    setState(() => _statusMsg = 'Verificando identidad...');

    try {
      // ✅ Extraer vector usando MISMO método que en registro
      final features = <double>[];

      // Landmarks normalizados 0..1 (IGUAL que en register)
      for (final lm in face.landmarks.values) {
        if (lm != null) {
          features.add(lm.position.x / 480.0);
          features.add(lm.position.y / 640.0);
        }
      }

      // Ángulos normalizados (IGUAL que en register)
      features.add((face.headEulerAngleY ?? 0) / 90.0);
      features.add((face.headEulerAngleX ?? 0) / 90.0);
      features.add((face.headEulerAngleZ ?? 0) / 90.0);

      // Clasificadores (IGUAL que en register)
      features.add(face.smilingProbability ?? 0.0);
      features.add(face.leftEyeOpenProbability ?? 1.0);
      features.add(face.rightEyeOpenProbability ?? 1.0);

      final faceVector = features;

      // ✅ Buscar usuario con timeout
      final user = await findUserByFace(faceVector).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⏱️ Timeout en login');
          return null;
        },
      );

      if (!mounted) return;

      if (user != null) {
        // ✅ LOGIN EXITOSO
        debugPrint('✅ Login exitoso: ${user.name}');

        await NotificationService.setUserId(user.id!);

        setState(() {
          _loginSuccess = true;
          _isSearching = false; // ✅ FIX: resetear flag
          _statusMsg = '¡Bienvenido, ${user.name}!';
        });

        await _successAnim.forward();

        if (!mounted) return;

        // ✅ Detener cámara ANTES de navegar
        if (_cameraController.value.isStreamingImages) {
          await _cameraController.stopImageStream();
        }
        _cameraController.dispose();

        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => EmotionPage(userName: user.name),
              transitionsBuilder: (_, anim, __, child) =>
                  FadeTransition(opacity: anim, child: child),
              transitionDuration: const Duration(milliseconds: 500),
            ),
          );
        }
      } else {
        // ❌ ROSTRO NO RECONOCIDO
        debugPrint('❌ Rostro no reconocido');

        if (!mounted) return;

        setState(() {
          _statusMsg = 'Rostro no reconocido. Inténtalo de nuevo.';
          _isSearching = false;
        });

        // ✅ FIX: Reanudar stream de forma segura
        if (!_streamActive && _cameraController.value.isInitialized) {
          _streamActive = true;
          await _cameraController.startImageStream(_processFrame);
        }
      }
    } catch (e) {
      debugPrint('❌ Error en _attemptLogin: $e');

      if (!mounted) return;

      setState(() {
        _statusMsg = 'Error al verificar. Inténtalo de nuevo.';
        _isSearching = false;
      });

      // ✅ FIX: Reanudar stream de forma segura
      if (!_streamActive && _cameraController.value.isInitialized) {
        _streamActive = true;
        await _cameraController.startImageStream(_processFrame);
      }
    }
  }

  @override
  void dispose() {
    // ✅ FIX: Dispose seguro y ordenado
    _streamActive = false;
    _cameraController.dispose();
    _faceDetector.close();
    _scanAnim.dispose();
    _successAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E27),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF4F8EF7)),
        ),
      );
    }

    // ✅ FIX: Null safety en previewSize
    final previewSize = _cameraController.value.previewSize;
    if (previewSize == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E27),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF4F8EF7)),
        ),
      );
    }

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
              // ── Header ──
              Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        // ✅ FIX: withOpacity en lugar de withValues
                        color: Colors.white.withValues(alpha:0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha:0.1),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Iniciar sesión',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Mira directo a la cámara',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),

            const SizedBox(height: 8),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _statusMsg,
                key: ValueKey(_statusMsg),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _loginSuccess
                      ? const Color(0xFF4CAF50)
                      : (_statusMsg.contains('no reconocido') ||
                      _statusMsg.contains('Error'))
                      ? Colors.redAccent
                      : Colors.white.withValues(alpha:0.5),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // ── Visor cámara ──
            Expanded(
                child: Center(
                  child: Stack(
                      alignment: Alignment.center,
                      children: [
                      // ✅ Anillo de progreso / búsqueda
                      if (!_loginSuccess)
                  SizedBox(
                  width: 310,
                  height: 310,
                  child: AnimatedBuilder(
                    animation: _scanAnim,
                    builder: (_, __) => CircularProgressIndicator(
                      value: _isSearching
                          ? null
                          : (_stableFrames / 20).clamp(0.0, 1.0),
                      strokeWidth: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      valueColor: AlwaysStoppedAnimation(
                        _currentFace != null
                            ? const Color(0xFF4F8EF7)
                            : Colors.white.withValues(alpha:0.2),
                      ),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                ),

                // ✅ Anillo de éxito
                if (_loginSuccess)
            ScaleTransition(
        scale: Tween<double>(begin: 0.85, end: 1.0).animate(
          CurvedAnimation(
            parent: _successAnim,
            curve: Curves.elasticOut,
          ),
        ),
        child: Container(
            width: 316,
            height: 316,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // ✅ FIX: Border.all en lugar de Border.fromBorderSide
              border: Border.all(
                color: const Color(0xFF4CAF50),
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4CAF50).withValues(alpha:0.35),
                  blurRadius: 30,
                  spreadRadius: 6,
                ),
              ],
            ),
        ),
            ),

                        // ✅ Vista previa de la cámara circular
                        Container(
                          width: 286,
                          height: 286,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha:0.08),
                              width: 2,
                            ),
                          ),
                          child: ClipOval(
                            child: SizedBox(
                              width: 286,
                              height: 286,
                              child: OverflowBox(
                                maxWidth: double.infinity,
                                maxHeight: double.infinity,
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    // ✅ FIX: Usar previewSize ya validado
                                    width: previewSize.height,
                                    height: previewSize.width,
                                    child: Stack(
                                      children: [
                                        CameraPreview(_cameraController),
                                        if (_currentFace != null &&
                                            _imageSize != Size.zero)
                                          CustomPaint(
                                            painter: FacePainter(
                                              face: _currentFace,
                                              imageSize: _imageSize,
                                              color: _loginSuccess
                                                  ? const Color(0xFF4CAF50)
                                                  : const Color(0xFF4F8EF7),
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

                        // ✅ Check animado de éxito
                        if (_loginSuccess)
                          ScaleTransition(
                            scale: Tween<double>(begin: 0, end: 1).animate(
                              CurvedAnimation(
                                parent: _successAnim,
                                curve: const Interval(
                                  0.4,
                                  1.0,
                                  curve: Curves.elasticOut,
                                ),
                              ),
                            ),
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF4CAF50),
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                          ),

                        // ✅ Spinner mientras verifica
                        if (_isSearching && !_loginSuccess)
                          Positioned(
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: Colors.black.withValues(alpha:0.6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF4F8EF7),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Verificando...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                  ),
                ),
            ),

                    // ── Botón de prueba Firebase ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              final snapshot = await FirebaseFirestore.instance
                                  .collection('users')
                                  .get();
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '📦 Usuarios en BD: ${snapshot.docs.length}\n'
                                        '${snapshot.docs.map((d) => d.data().keys.join(", ")).join("\n")}',
                                  ),
                                  duration: const Duration(seconds: 5),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('❌ Error al consultar Firebase: $e'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            '🔍 Verificar Firebase',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ── Chips de estado ──
                    Padding(
                      padding: const EdgeInsets.all(28),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _StatusChip(
                            icon: Icons.center_focus_strong_rounded,
                            label: 'Detectado',
                            active: _currentFace != null,
                          ),
                          const SizedBox(width: 10),
                          _StatusChip(
                            icon: Icons.straighten_rounded,
                            label: 'Distancia',
                            active: _stableFrames > 5,
                          ),
                          const SizedBox(width: 10),
                          _StatusChip(
                            icon: Icons.verified_rounded,
                            label: 'Verificado',
                            active: _loginSuccess,
                          ),
                        ],
                      ),
                    ),
                  ],
              ),
            ),
        ),
    );
  }
}

// ── Widget StatusChip ──
class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: active
            ? const Color(0xFF4F8EF7).withValues(alpha:0.15)
            : Colors.white.withValues(alpha:0.04),
        border: Border.all(
          color: active
              ? const Color(0xFF4F8EF7).withValues(alpha:0.4)
              : Colors.white.withValues(alpha:0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: active
                ? const Color(0xFF4F8EF7)
                : Colors.white.withValues(alpha:0.25),
            size: 15,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: active
                  ? const Color(0xFF4F8EF7)
                  : Colors.white.withValues(alpha:0.25),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}