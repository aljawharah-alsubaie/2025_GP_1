import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';

class FaceRotationCaptureScreen extends StatefulWidget {
  const FaceRotationCaptureScreen({super.key});

  @override
  State<FaceRotationCaptureScreen> createState() =>
      _FaceRotationCaptureScreenState();
}

class _FaceRotationCaptureScreenState
    extends State<FaceRotationCaptureScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  final FlutterTts _tts = FlutterTts();

  List<File> _capturedImages = [];
  int _currentStep = 0;
  bool _isCapturing = false;
  
  late FaceDetector _faceDetector;
  Timer? _detectionTimer;
  bool _isDetecting = false;
  bool _faceDetected = false;
  String _statusMessage = 'Position your face';
  Color _statusColor = const Color(0xFF8E3A95);
  int _stableFrames = 0;
  
  String _lastSpokenMessage = '';

  final List<Map<String, String>> _instructions = [
    {'en': 'Look straight at the camera', 'ar': 'انظر مباشرة للكاميرا'},
    {'en': 'Turn your face to the left', 'ar': 'لف وجهك لليسار'},
    {'en': 'Turn your face to the right', 'ar': 'لف وجهك لليمين'},
    {'en': 'Look up slightly', 'ar': 'انظر للأعلى قليلاً'},
    {'en': 'Look down slightly', 'ar': 'انظر للأسفل قليلاً'},
  ];

  final List<IconData> _icons = [
    Icons.face,
    Icons.arrow_back,
    Icons.arrow_forward,
    Icons.arrow_upward,
    Icons.arrow_downward,
  ];

  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);

  @override
  void initState() {
    super.initState();
    _initTts();
    _initFaceDetector();
    _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _tts.stop();
    _detectionTimer?.cancel();
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _initTts() async {
    final languageCode = Provider.of<LanguageProvider>(context, listen: false).languageCode;
    await _tts.setLanguage(languageCode == 'ar' ? 'ar-SA' : 'en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }
  
  Future<void> _speakIfDifferent(String text) async {
    if (_lastSpokenMessage != text) {
      _lastSpokenMessage = text;
      await _speak(text);
    }
  }

  void _initFaceDetector() {
    final options = FaceDetectorOptions(
      enableLandmarks: false,
      enableClassification: true,
      minFaceSize: 0.2,
      performanceMode: FaceDetectorMode.accurate,
    );
    _faceDetector = FaceDetector(options: options);
  }

  Future<void> _initCamera() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      final frontCameraIndex = _cameras!
          .indexWhere((cam) => cam.lensDirection == CameraLensDirection.front);

      _controller = CameraController(
        _cameras![frontCameraIndex >= 0 ? frontCameraIndex : 0],
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {});
        await Future.delayed(const Duration(milliseconds: 500));
        _speak(_instructions[0][languageProvider.languageCode]!);
        _startFaceDetection();
      }
    }
  }

  void _startFaceDetection() {
    _detectionTimer = Timer.periodic(
      const Duration(milliseconds: 400),
      (timer) async {
        if (!_isDetecting && !_isCapturing && mounted) {
          await _checkForFace();
        }
      },
    );
  }

  Future<void> _checkForFace() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    if (_controller?.value.isInitialized != true) return;
    
    _isDetecting = true;

    try {
      final image = await _controller!.takePicture();
      
      final brightness = await _checkBrightness(image.path);
      
      if (brightness < 50) {
        await File(image.path).delete();
        
        if (!mounted) return;
        
        setState(() {
          _faceDetected = false;
          _statusMessage = languageProvider.isArabic
              ? 'مظلم جداً - شغّل الإضاءة'
              : 'Too dark - Turn on lights';
          _statusColor = Colors.red;
          _stableFrames = 0;
        });
        await _speakIfDifferent(languageProvider.isArabic
            ? 'مظلم جداً. شغّل الإضاءة'
            : 'Too dark. Turn on lights');
        return;
      }
      
      final inputImage = InputImage.fromFilePath(image.path);
      final faces = await _faceDetector.processImage(inputImage);
      
      await File(image.path).delete();

      if (!mounted) return;

      if (faces.isEmpty) {
        setState(() {
          _faceDetected = false;
          _statusMessage = languageProvider.isArabic
              ? 'لم يتم اكتشاف وجه'
              : 'No face detected';
          _statusColor = Colors.red;
          _stableFrames = 0;
        });
        await _speakIfDifferent(languageProvider.isArabic
            ? 'لم يتم اكتشاف وجه'
            : 'No face detected');
      } else {
        final face = faces.first;
        final faceWidth = face.boundingBox.width;
        
        if (faceWidth < 200) {
          setState(() {
            _faceDetected = true;
            _statusMessage = languageProvider.isArabic
                ? 'اقترب أكثر'
                : 'Move closer';
            _statusColor = Colors.orange;
            _stableFrames = 0;
          });
          await _speakIfDifferent(languageProvider.isArabic
              ? 'اقترب أكثر'
              : 'Move closer');
        } else if (faceWidth > 500) {
          setState(() {
            _faceDetected = true;
            _statusMessage = languageProvider.isArabic
                ? 'ابتعد قليلاً'
                : 'Move back';
            _statusColor = Colors.orange;
            _stableFrames = 0;
          });
          await _speakIfDifferent(languageProvider.isArabic
              ? 'ابتعد قليلاً'
              : 'Move back');
        } else {
          final headYaw = face.headEulerAngleY ?? 0;
          final headPitch = face.headEulerAngleX ?? 0;
          
          bool correctPosition = _checkFacePosition(headYaw, headPitch);
          
          if (!correctPosition) {
            setState(() {
              _faceDetected = true;
              _statusMessage = _getPositionMessage(headYaw, headPitch);
              _statusColor = Colors.orange;
              _stableFrames = 0;
            });
            await _speakIfDifferent(_statusMessage);
          } else {
            setState(() {
              _faceDetected = true;
              _statusMessage = languageProvider.isArabic
                  ? 'ممتاز! اثبت...'
                  : 'Perfect! Hold still...';
              _statusColor = Colors.green;
              _stableFrames++;
            });

            if (_stableFrames == 1) {
              await _speak(languageProvider.isArabic ? 'ممتاز' : 'Perfect');
            }

            if (_stableFrames >= 3) {
              _detectionTimer?.cancel();
              await _capturePhoto();
            }
          }
        }
      }
    } catch (e) {
      print('Face detection error: $e');
    } finally {
      _isDetecting = false;
    }
  }
  
  bool _checkFacePosition(double yaw, double pitch) {
    switch (_currentStep) {
      case 0:
        return yaw.abs() < 15 && pitch.abs() < 15;
      
      case 1:
        return yaw > 20 && yaw < 50 && pitch.abs() < 15;
      
      case 2:
        return yaw < -20 && yaw > -50 && pitch.abs() < 15;
      
      case 3:
       return pitch > 10 && pitch < 35 && yaw.abs() < 20; 
      
      case 4:
        return pitch < -10 && pitch > -35 && yaw.abs() < 20;
      
      default:
        return true;
    }
  }
  
  String _getPositionMessage(double yaw, double pitch) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    switch (_currentStep) {
      case 0:
        return languageProvider.isArabic
            ? 'انظر مباشرة للأمام'
            : 'Look straight ahead';
      
      case 1:
        if (yaw < 10) {
          return languageProvider.isArabic
              ? 'لف أكثر لليسار'
              : 'Turn more to your left';
        } else if (yaw > 50) {
          return languageProvider.isArabic
              ? 'لف أقل لليسار'
              : 'Turn less to the left';
        }
        return languageProvider.isArabic
            ? 'تقريباً، لف لليسار'
            : 'Almost there, turn left';
      
      case 2:
        if (yaw > -10) {
          return languageProvider.isArabic
              ? 'لف أكثر لليمين'
              : 'Turn more to your right';
        } else if (yaw < -50) {
          return languageProvider.isArabic
              ? 'لف أقل لليمين'
              : 'Turn less to the right';
        }
        return languageProvider.isArabic
            ? 'تقريباً، لف لليمين'
            : 'Almost there, turn right';
      
      case 3:
        if (pitch < 10) {
          return languageProvider.isArabic
              ? 'انظر للأعلى أكثر'
              : 'Look up more';
        }
        return languageProvider.isArabic
            ? 'تقريباً، انظر للأعلى'
            : 'Almost there, look up';

      case 4:
        if (pitch > -10) {
          return languageProvider.isArabic
              ? 'انظر للأسفل أكثر'
              : 'Look down more';
        }
        return languageProvider.isArabic
            ? 'تقريباً، انظر للأسفل'
            : 'Almost there, look down';
      
      default:
        return languageProvider.isArabic
            ? 'اضبط وضعك'
            : 'Adjust your position';
    }
  }

  Future<double> _checkBrightness(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      
      final Completer<ui.Image> completer = Completer();
      ui.decodeImageFromList(Uint8List.fromList(bytes), (ui.Image img) {
        completer.complete(img);
      });
      final image = await completer.future;
      
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return 0;
      
      final pixels = byteData.buffer.asUint8List();
      int totalBrightness = 0;
      int pixelCount = 0;
      
      for (int i = 0; i < pixels.length; i += 400) {
        if (i + 2 < pixels.length) {
          final r = pixels[i];
          final g = pixels[i + 1];
          final b = pixels[i + 2];
          
          totalBrightness += ((r + g + b) / 3).round();
          pixelCount++;
        }
      }
      
      return pixelCount > 0 ? totalBrightness / pixelCount : 0;
    } catch (e) {
      print('Brightness check error: $e');
      return 100;
    }
  }

  Future<void> _capturePhoto() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    if (_controller?.value.isInitialized != true || _isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      HapticFeedback.mediumImpact();
      await _speak(languageProvider.isArabic ? 'تم التقاط الصورة' : 'Captured');
      
      final image = await _controller!.takePicture();
      final directory = await getTemporaryDirectory();
      final targetPath =
          '${directory.path}/face_${_currentStep}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await File(image.path).copy(targetPath);
      _capturedImages.add(File(targetPath));

      if (_capturedImages.length >= 5) {
        await _speak(languageProvider.isArabic
            ? 'تم التقاط جميع الصور بنجاح. جاري المعالجة الآن'
            : 'All photos captured successfully. Processing now.');
        await Future.delayed(const Duration(milliseconds: 1000));
        
        if (mounted) {
          Navigator.pop(context, _capturedImages);
        }
        return;
      }

      setState(() {
        _currentStep++;
        _stableFrames = 0;
        _lastSpokenMessage = '';
      });

      await Future.delayed(const Duration(milliseconds: 500));
      await _speak(_instructions[_currentStep][languageProvider.languageCode]!);
      
      setState(() {
        _statusMessage = languageProvider.isArabic
            ? 'ضع وجهك في الإطار'
            : 'Position your face';
        _statusColor = vibrantPurple;
      });
      
      _startFaceDetection();
      
    } catch (e) {
      print('Error capturing photo: $e');
      await _speak(languageProvider.isArabic
          ? 'فشل التقاط الصورة. حاول مرة أخرى'
          : 'Failed to capture photo. Please try again.');
      _startFaceDetection();
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: vibrantPurple),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final safePadding = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: size.width,
                      height: size.width * _controller!.value.aspectRatio,
                      child: CameraPreview(_controller!),
                    ),
                  ),
                ),
              ),
            ),

            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                child: CustomPaint(
                  size: Size(
                    size.width * 0.7,
                    size.height * 0.5,
                  ),
                  painter: OvalFaceGuidePainter(
                    color: _statusColor,
                    isAnimating: _stableFrames > 0,
                  ),
                ),
              ),
            ),

            Positioned(
              top: safePadding.top + 10,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      languageProvider.isArabic
                          ? 'الخطوة ${_currentStep + 1}/${_instructions.length}'
                          : 'Step ${_currentStep + 1}/${_instructions.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _instructions.length,
                        (index) => Container(
                          width: 35,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: index < _currentStep
                                ? Colors.green
                                : index == _currentStep
                                    ? vibrantPurple
                                    : Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    
                    Icon(
                      _icons[_currentStep],
                      color: vibrantPurple,
                      size: 32,
                    ),
                    const SizedBox(height: 6),
                    
                    Text(
                      _instructions[_currentStep][languageProvider.languageCode]!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _statusColor, width: 2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _statusColor == Colors.green
                                ? Icons.check_circle
                                : (_statusColor == Colors.orange
                                      ? Icons.warning
                                      : Icons.cancel),
                            color: _statusColor,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _statusMessage,
                              style: TextStyle(
                                color: _statusColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_isCapturing)
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.9),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.check,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            Positioned(
              top: safePadding.top + 10,
              left: 12,
              child: GestureDetector(
                onTap: () {
                  _detectionTimer?.cancel();
                  _speak(languageProvider.isArabic ? 'تم الإلغاء' : 'Cancelled');
                  Navigator.pop(context);
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OvalFaceGuidePainter extends CustomPainter {
  final Color color;
  final bool isAnimating;

  OvalFaceGuidePainter({
    required this.color,
    required this.isAnimating,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = isAnimating ? 4 : 3;

    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.9,
      height: size.height * 0.95,
    );

    canvas.drawOval(rect, paint);

    final cornerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final cornerLength = size.width * 0.12;

    _drawCorner(canvas, cornerPaint, rect.topLeft, cornerLength, true, true);
    _drawCorner(canvas, cornerPaint, rect.topRight, cornerLength, false, true);
    _drawCorner(canvas, cornerPaint, rect.bottomLeft, cornerLength, true, false);
    _drawCorner(canvas, cornerPaint, rect.bottomRight, cornerLength, false, false);
  }

  void _drawCorner(Canvas canvas, Paint paint, Offset corner,
      double length, bool isLeft, bool isTop) {
    final xDir = isLeft ? 1 : -1;
    final yDir = isTop ? 1 : -1;

    canvas.drawLine(
      corner,
      Offset(corner.dx + length * xDir, corner.dy),
      paint,
    );
    canvas.drawLine(
      corner,
      Offset(corner.dx, corner.dy + length * yDir),
      paint,
    );
  }

  @override
  bool shouldRepaint(OvalFaceGuidePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isAnimating != isAnimating;
  }
}