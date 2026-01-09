import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';

class CurrencyCameraScreen extends StatefulWidget {
  const CurrencyCameraScreen({super.key});

  @override
  State<CurrencyCameraScreen> createState() => _CurrencyCameraScreenState();
}

class _CurrencyCameraScreenState extends State<CurrencyCameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  final picker = ImagePicker();

  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();

  Interpreter? _interpreter;
  bool _modelLoaded = false;
  bool _busy = false;

  String _detectedCurrency = "";
  String? _selectedImagePath;

  static const List<String> CURRENCY_LABELS = [
    '10 SR',
    '100 SR',
    '200 SR',
    '5 SR',
    '50 SR',
    '500 SR',
  ];

  String _effectiveTtsLang = 'en-US';

  @override
  void initState() {
    super.initState();
    _initTts();
    _initializeApp();
  }

  Future<void> _initTts() async {
    final languageCode = Provider.of<LanguageProvider>(context, listen: false).languageCode;
    
    _tts.setStartHandler(() => print('🔊 TTS start'));
    _tts.setCompletionHandler(() => print('🔊 TTS complete'));
    _tts.setErrorHandler((msg) => print('🔊 TTS error: $msg'));

    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);

    await _ensureTtsLanguage(languageCode);
  }

  Future<void> _ensureTtsLanguage(String languageCode) async {
    if (languageCode == 'ar') {
      final candidates = ['ar-SA', 'ar'];
      for (final lang in candidates) {
        try {
          final ok = await _tts.isLanguageAvailable(lang);
          print('🌐 Check TTS "$lang": $ok');
          if (ok == true) {
            await _tts.setLanguage(lang);
            _effectiveTtsLang = lang;
            print('✅ Using TTS language: $_effectiveTtsLang');
            return;
          }
        } catch (_) {}
      }
      await _tts.setLanguage('ar-SA');
      _effectiveTtsLang = 'ar-SA';
    } else {
      final candidates = ['en-US', 'en-GB', 'en'];
      for (final lang in candidates) {
        try {
          final ok = await _tts.isLanguageAvailable(lang);
          print('🌐 Check TTS "$lang": $ok');
          if (ok == true) {
            await _tts.setLanguage(lang);
            _effectiveTtsLang = lang;
            print('✅ Using TTS language: $_effectiveTtsLang');
            return;
          }
        } catch (_) {}
      }
      await _tts.setLanguage('en-US');
      _effectiveTtsLang = 'en-US';
    }
    print('⚠️ Falling back to $_effectiveTtsLang for TTS');
  }

  Future<void> _initializeApp() async {
    try {
      await _loadModel();
      await _initCamera();
    } catch (e) {
      print('❌ Init error: $e');
      if (mounted) {
        final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(languageProvider.isArabic ? 'خطأ: $e' : 'Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/banknote_model.tflite',
      );
      setState(() {
        _modelLoaded = true;
      });
      print('✅ Currency model loaded');
    } catch (e) {
      print('❌ Model load error: $e');
      rethrow;
    }
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      _controller = CameraController(
        _cameras![0],
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (mounted) setState(() {});
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;
    final newIndex = _controller!.description == _cameras![0] ? 1 : 0;
    _controller = CameraController(
      _cameras![newIndex],
      ResolutionPreset.high,
      enableAudio: false,
    );
    await _controller!.initialize();
    if (mounted) setState(() {});
  }

  Future<List<List<List<List<double>>>>> _preprocessImage(
    String imagePath,
  ) async {
    final imageFile = File(imagePath);
    final bytes = await imageFile.readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image');

    image = img.copyResize(image, width: 224, height: 224);
    const gamma = 1.2;

    List<List<List<List<double>>>> input = [];
    List<List<List<double>>> batchData = [];

    for (int y = 0; y < 224; y++) {
      List<List<double>> row = [];
      for (int x = 0; x < 224; x++) {
        final pixel = image.getPixel(x, y);
        double r = pow(pixel.r / 255.0, 1 / gamma).toDouble();
        double g = pow(pixel.g / 255.0, 1 / gamma).toDouble();
        double b = pow(pixel.b / 255.0, 1 / gamma).toDouble();
        r = r.clamp(0.0, 1.0);
        g = g.clamp(0.0, 1.0);
        b = b.clamp(0.0, 1.0);
        row.add([r, g, b]);
      }
      batchData.add(row);
    }
    input.add(batchData);
    return input;
  }

  Future<Map<String, dynamic>> _predictCurrency(String imagePath) async {
    if (_interpreter == null) throw Exception('Model is not ready!');
    final input = await _preprocessImage(imagePath);
    List<List<double>> output = [List.filled(CURRENCY_LABELS.length, 0.0)];
    _interpreter!.run(input, output);

    List<double> predictions = output[0];
    int maxIndex = 0;
    double maxVal = -1;
    for (int i = 0; i < predictions.length; i++) {
      if (predictions[i] > maxVal) {
        maxVal = predictions[i];
        maxIndex = i;
      }
    }

    return {'currency': CURRENCY_LABELS[maxIndex], 'confidence': maxVal};
  }

  Future<void> _announceResult(String currency, double confidence) async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final number = currency.split(' ').first.trim();

    String phrase;
    
    if (languageProvider.isArabic) {
      final Map<String, String> arNames = {
        '5': 'خمسة ريالات',
        '10': 'عشرة ريالات',
        '50': 'خمسون ريالاً',
        '100': 'مئة ريال',
        '200': 'مئتا ريال',
        '500': 'خمسمئة ريال',
      };
      
      final spoken = arNames[number] ?? '$number ريال';
      phrase = 'هذه $spoken.';
    } else {
      final Map<String, String> enNames = {
        '5': 'five riyals',
        '10': 'ten riyals',
        '50': 'fifty riyals',
        '100': 'one hundred riyals',
        '200': 'two hundred riyals',
        '500': 'five hundred riyals',
      };

      final spoken = enNames[number] ?? '$number riyals';
      phrase = 'This is $spoken.';
    }

    try {
      await _tts.stop();
      await _tts.speak(phrase);
    } catch (e) {
      print('⚠️ TTS speak error: $e');
    }
  }

  Future<void> _recognizeCurrency(String path) async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    if (!_modelLoaded) return;
    setState(() => _busy = true);

    try {
      final result = await _predictCurrency(path);
      final currency = result['currency'] as String;
      final confidence = result['confidence'] as double;

      setState(() {
        _detectedCurrency = currency;
      });

      await _playSound(volume: 0.35);
      await Future.delayed(const Duration(milliseconds: 300));
      await _announceResult(currency, confidence);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(languageProvider.isArabic
                ? 'العملة المكتشفة: $currency'
                : 'Detected Currency: $currency'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Recognition error: $e');
      setState(() => _detectedCurrency = (languageProvider.isArabic
          ? 'خطأ: ${e.toString()}'
          : 'Error: ${e.toString()}'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(languageProvider.isArabic ? 'خطأ: $e' : 'Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _playSound({double volume = 0.5}) async {
    try {
      await _player.setVolume(volume);
      await _player.play(AssetSource('sounds/beep.wav'));
    } catch (e) {
      print('⚠️ Missing beep sound: $e');
    }
  }

  Future<void> _captureImage() async {
    if (_controller?.value.isInitialized != true) return;
    final file = await _controller!.takePicture();

    setState(() {
      _selectedImagePath = file.path;
    });

    await _recognizeCurrency(file.path);
  }

  Future<void> _pickImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _selectedImagePath = pickedFile.path);
      await _recognizeCurrency(pickedFile.path);
    }
  }

  void _returnToCamera() {
    setState(() {
      _selectedImagePath = null;
      _detectedCurrency = '';
    });
  }

  String get _modeDescription {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    return languageProvider.isArabic ? 'وضع اكتشاف العملات' : 'Currency Detection Mode';
  }

  IconData get _modeIcon => Icons.payments;

  @override
  void dispose() {
    _controller?.dispose();
    _player.dispose();
    _interpreter?.close();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      body: _controller == null || !_controller!.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(
                  child: _selectedImagePath != null
                      ? Image.file(File(_selectedImagePath!), fit: BoxFit.cover)
                      : ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.center,
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: size.width,
                                height:
                                    size.width * _controller!.value.aspectRatio,
                                child: CameraPreview(_controller!),
                              ),
                            ),
                          ),
                        ),
                ),

                // Back button
                Positioned(
                  top: 40,
                  left: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        languageProvider.isArabic
                            ? Icons.arrow_forward
                            : Icons.arrow_back,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),

                // Mode info
                Positioned(
                  top: 40,
                  right: 16,
                  left: 80,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_modeIcon, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _modeDescription,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Return to camera button
                if (_selectedImagePath != null)
                  Positioned(
                    top: 100,
                    right: 16,
                    child: GestureDetector(
                      onTap: _returnToCamera,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              languageProvider.isArabic ? 'صورة جديدة' : 'New Photo',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Result display
                if (_detectedCurrency.isNotEmpty)
                  Positioned(
                    top: 140,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            languageProvider.isArabic ? 'العملة المكتشفة:' : 'Detected Currency:',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _detectedCurrency,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Bottom controls
                Positioned(
                  bottom: 40,
                  left: 32,
                  right: 32,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Gallery picker
                        GestureDetector(
                          onTap: _busy ? null : _pickImage,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.photo,
                              size: 28,
                              color: Colors.white,
                            ),
                          ),
                        ),

                        // Capture button
                        GestureDetector(
                          onTap: _busy ? null : _captureImage,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              color: Colors.white.withOpacity(0.1),
                            ),
                            child: Center(
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: _busy ? Colors.orange : Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: _busy
                                    ? const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        Icons.camera_alt,
                                        color: Colors.grey[800],
                                        size: 24,
                                      ),
                              ),
                            ),
                          ),
                        ),

                        // Camera switch
                        GestureDetector(
                          onTap: _busy || _selectedImagePath != null
                              ? null
                              : _switchCamera,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(
                                _selectedImagePath != null ? 0.1 : 0.2,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.cameraswitch,
                              size: 28,
                              color: _selectedImagePath != null
                                  ? Colors.white38
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Busy overlay
                if (_busy)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.25),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              languageProvider.isArabic
                                  ? 'التعرف على العملة...'
                                  : 'Recognizing currency...',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}