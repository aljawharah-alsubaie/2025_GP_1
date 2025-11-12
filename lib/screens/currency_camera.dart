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

  String _loadingStatus = '📥 Loading model...';
  String _detectedCurrency = "";
  double _confidence = 0.0;
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
    _tts.setStartHandler(() => print('🔊 TTS start'));
    _tts.setCompletionHandler(() => print('🔊 TTS complete'));
    _tts.setErrorHandler((msg) => print('🔊 TTS error: $msg'));

    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);

    await _ensureTtsLanguage();
  }

  Future<void> _ensureTtsLanguage() async {
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
    print('⚠️ Falling back to en-US for TTS');
  }

  Future<void> _initializeApp() async {
    try {
      await _loadModel();
      await _initCamera();
    } catch (e) {
      print('❌ Init error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadModel() async {
    try {
      setState(() => _loadingStatus = '📥 Loading model...');
      _interpreter = await Interpreter.fromAsset(
        'assets/models/banknote_model.tflite',
      );
      setState(() {
        _modelLoaded = true;
        _loadingStatus = '✅ Model loaded!';
      });
    } catch (e) {
      print('❌ Model load error: $e');
      setState(() => _loadingStatus = '❌ Failed to load model');
      rethrow;
    }
  }

  Future<void> _initCamera() async {
    try {
      setState(() => _loadingStatus = '📷 Initializing camera...');
      _cameras = await availableCameras();

      if (_cameras != null && _cameras!.isNotEmpty) {
        _controller = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _controller!.initialize();
        setState(() => _loadingStatus = '✅ Camera ready!');
      }
    } catch (e) {
      print('❌ Camera error: $e');
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
    setState(() {});
  }

  // ============ Preprocess ============
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

  // ============ Predict ============
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

  // ============ Speak result ============
  Future<void> _announceResult(String currency, double confidence) async {
    final number = currency.split(' ').first.trim();

    final Map<String, String> enNames = {
      '5': 'five riyals',
      '10': 'ten riyals',
      '50': 'fifty riyals',
      '100': 'one hundred riyals',
      '200': 'two hundred riyals',
      '500': 'five hundred riyals',
    };

    final spoken = enNames[number] ?? '$number riyals';
    final pct = (confidence * 100).round();

    String phrase;
    if (confidence >= 0.85) {
      phrase = 'Detected: $spoken.';
    } else if (confidence >= 0.65) {
      phrase = 'Likely $spoken, confidence $pct percent.';
    } else {
      phrase = 'Not sure. Maybe $spoken, confidence $pct percent.';
    }

    try {
      await _tts.stop();
      await _tts.speak(phrase);
    } catch (e) {
      print('⚠️ TTS speak error: $e');
    }
  }

  // ============ Full recognition flow ============
  Future<void> _recognizeCurrency(String path) async {
    if (!_modelLoaded) return;
    setState(() => _busy = true);
    try {
      final result = await _predictCurrency(path);
      final currency = result['currency'] as String;
      final confidence = result['confidence'] as double;

      setState(() {
        _detectedCurrency = currency;
        _confidence = confidence;
      });

      // Beep softly, delay a bit, then speak
      await _playSound(volume: 0.35);
      await Future.delayed(const Duration(milliseconds: 300));
      await _announceResult(currency, confidence);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ $currency (${(_confidence * 100).toStringAsFixed(1)}%)',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Recognition error: $e');
      setState(() => _detectedCurrency = 'Error: ${e.toString()}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() => _busy = false);
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
    if (_controller == null || !_controller!.value.isInitialized) return;
    final image = await _controller!.takePicture();
    setState(() => _selectedImagePath = image.path);
    await _recognizeCurrency(image.path);
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
      _confidence = 0.0;
    });
  }

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
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _selectedImagePath != null
                ? Image.file(File(_selectedImagePath!), fit: BoxFit.cover)
                : CameraPreview(_controller!),
          ),

          // Back
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
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),

          // Result
          if (_detectedCurrency.isNotEmpty)
            Positioned(
              top: 120,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Detected Currency:',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _detectedCurrency,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _confidence,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _confidence > 0.8
                            ? Colors.green
                            : _confidence > 0.6
                            ? Colors.yellow
                            : Colors.red,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Confidence: ${(_confidence * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                  onTap: _busy ? null : _pickImage,
                  child: const Icon(Icons.photo, color: Colors.white, size: 36),
                ),
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
                      child: _busy
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 30,
                            ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _busy ? null : _switchCamera,
                  child: const Icon(
                    Icons.cameraswitch,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ],
            ),
          ),

          // Busy overlay
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.25),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Recognizing currency...',
                        style: TextStyle(color: Colors.white, fontSize: 16),
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
