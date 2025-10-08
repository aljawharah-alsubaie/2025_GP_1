import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'dart:math' as math;
import '../services/api_service.dart';

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
  final CurrencyApiService _apiService = CurrencyApiService();
  
  bool _busy = false;
  String _detectedCurrency = "";
  String? _selectedImagePath;
  bool _isApiConnected = false;

  // IBM Watson TTS credentials
  static const String IBM_TTS_API_KEY = "Ibvg1Q2qca9ALJa1JCZVp09gFJMstnyeAXaOWKNrq6o-";
  static const String IBM_TTS_URL = "https://api.au-syd.text-to-speech.watson.cloud.ibm.com/instances/892ef34b-36b6-4ba6-b29c-d4a55108f114";

  @override
  void initState() {
    super.initState();
    _initCamera();
    _checkApiConnection();
  }

  Future<void> _checkApiConnection() async {
    final isConnected = await _apiService.checkHealth();
    setState(() {
      _isApiConnected = isConnected;
    });
    
    if (!isConnected && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Warning: Currency recognition service is offline'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
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

  // استخراج الـ 19 feature من الصورة
  Future<List<double>> _extractFeatures(String imagePath) async {
    try {
      // قراءة الصورة
      final imageFile = File(imagePath);
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // تجميع قيم RGB لكل بكسل
      List<int> redValues = [];
      List<int> greenValues = [];
      List<int> blueValues = [];
      
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          redValues.add(pixel.r.toInt());
          greenValues.add(pixel.g.toInt());
          blueValues.add(pixel.b.toInt());
        }
      }
      
      int pixelCount = redValues.length;
      
      // 1. Red Mean
      double redMean = redValues.reduce((a, b) => a + b) / pixelCount;
      
      // 2. Green Mean
      double greenMean = greenValues.reduce((a, b) => a + b) / pixelCount;
      
      // 3. Blue Mean
      double blueMean = blueValues.reduce((a, b) => a + b) / pixelCount;
      
      // 4. Red Standard Deviation
      double redVariance = 0;
      for (var val in redValues) {
        redVariance += math.pow(val - redMean, 2);
      }
      double redStd = math.sqrt(redVariance / pixelCount);
      
      // 5. Green Standard Deviation
      double greenVariance = 0;
      for (var val in greenValues) {
        greenVariance += math.pow(val - greenMean, 2);
      }
      double greenStd = math.sqrt(greenVariance / pixelCount);
      
      // 6. Blue Standard Deviation
      double blueVariance = 0;
      for (var val in blueValues) {
        blueVariance += math.pow(val - blueMean, 2);
      }
      double blueStd = math.sqrt(blueVariance / pixelCount);
      
      // 7. Brightness (متوسط السطوع)
      double brightness = (redMean + greenMean + blueMean) / 3.0;
      
      // 8. Contrast (Standard Deviation of Brightness)
      List<double> brightnessValues = [];
      for (int i = 0; i < pixelCount; i++) {
        double pixelBrightness = (redValues[i] + greenValues[i] + blueValues[i]) / 3.0;
        brightnessValues.add(pixelBrightness);
      }
      double brightnessVariance = 0;
      for (var val in brightnessValues) {
        brightnessVariance += math.pow(val - brightness, 2);
      }
      double contrast = math.sqrt(brightnessVariance / pixelCount);
      
      // 9. Red Max
      double redMax = redValues.reduce(math.max).toDouble();
      
      // 10. Green Max
      double greenMax = greenValues.reduce(math.max).toDouble();
      
      // 11. Blue Max
      double blueMax = blueValues.reduce(math.max).toDouble();
      
      // 12. Red Min
      double redMin = redValues.reduce(math.min).toDouble();
      
      // 13. Green Min
      double greenMin = greenValues.reduce(math.min).toDouble();
      
      // 14. Blue Min
      double blueMin = blueValues.reduce(math.min).toDouble();
      
      // 15. Aspect Ratio
      double aspectRatio = image.width / image.height;
      
      // 16. Red Range
      double redRange = redMax - redMin;
      
      // 17. Green Range
      double greenRange = greenMax - greenMin;
      
      // 18. Blue Range
      double blueRange = blueMax - blueMin;
      
      // 19. Color Variance
      double colorVariance = ((redVariance + greenVariance + blueVariance) / 3.0);
      
      // إرجاع Features بنفس الترتيب المطلوب
      List<double> features = [
        redMean,        // 1
        greenMean,      // 2
        blueMean,       // 3
        redStd,         // 4
        greenStd,       // 5
        blueStd,        // 6
        brightness,     // 7
        contrast,       // 8
        redMax,         // 9
        greenMax,       // 10
        blueMax,        // 11
        redMin,         // 12
        greenMin,       // 13
        blueMin,        // 14
        aspectRatio,    // 15
        redRange,       // 16
        greenRange,     // 17
        blueRange,      // 18
        colorVariance,  // 19
      ];
      
      print("Extracted features: $features");
      return features;
      
    } catch (e) {
      print('Feature extraction error: $e');
      rethrow;
    }
  }

  Future<String?> _convertTextToSpeech(String text) async {
    try {
      final String auth = base64Encode(utf8.encode('apikey:$IBM_TTS_API_KEY'));

      final response = await http.post(
        Uri.parse('$IBM_TTS_URL/v1/synthesize'),
        headers: {
          'Authorization': 'Basic $auth',
          'Content-Type': 'application/json',
          'Accept': 'audio/mp3',
        },
        body: jsonEncode({
          'text': text,
          'voice': 'en-US_AllisonV3Voice',
          'accept': 'audio/mp3',
        }),
      );

      if (response.statusCode == 200) {
        final Directory tempDir = await getTemporaryDirectory();
        final String audioPath = '${tempDir.path}/currency_${DateTime.now().millisecondsSinceEpoch}.mp3';
        final File audioFile = File(audioPath);
        await audioFile.writeAsBytes(response.bodyBytes);
        return audioPath;
      }
      return null;
    } catch (e) {
      print('TTS Error: $e');
      return null;
    }
  }

  Future<void> _processImage(String imagePath, {bool fromGallery = false}) async {
    print("===== STARTING PROCESSING =====");
  print("Image path: $imagePath");
  print("API connected: $_isApiConnected");
    if (!_isApiConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Currency service is offline. Please try again later.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _busy = true);

    try {
      if (fromGallery) {
        _selectedImagePath = imagePath;
      }

 print("Step 1: Extracting features...");
    List<double> features = await _extractFeatures(imagePath);
    print("Features extracted: ${features.length} features");
    
    print("Step 2: Sending to API...");
    final result = await _apiService.predictCurrency(features);
    print("API Response: $result");
      // استخراج النتيجة
      String currencyText = _parsePredictionResult(result);

      setState(() {
        _detectedCurrency = currencyText;
      });

      // تحويل لصوت
      String? audioPath = await _convertTextToSpeech(currencyText);
      
      if (audioPath != null) {
        await _player.stop();
        await _player.play(DeviceFileSource(audioPath));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Currency detected: $currencyText'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _parsePredictionResult(Map<String, dynamic> result) {
    try {
      print("Full prediction result: $result");
      
      // استخراج النتيجة من IBM Watson response
      if (result['success'] == true) {
        final prediction = result['prediction'];
        
        // IBM Watson format
        if (prediction != null && prediction['predictions'] != null) {
          final predictions = prediction['predictions'];
          if (predictions.isNotEmpty && predictions[0]['values'] != null) {
            final values = predictions[0]['values'];
            if (values.isNotEmpty && values[0].isNotEmpty) {
              String currency = values[0][0].toString();
              
              // تحويل من صيغة CSV إلى نص واضح
              Map<String, String> currencyNames = {
                '5_riyal': '5 Riyal',
                '10_riyal': '10 Riyal',
                '50_riyal': '50 Riyal',
                '100_riyal': '100 Riyal',
                '200_riyal': '200 Riyal',
                '500_riyal': '500 Riyal',
              };
              
              String displayName = currencyNames[currency] ?? currency;
              return 'This is $displayName Saudi currency';
            }
          }
        }
      }
      
      return 'Currency detected';
    } catch (e) {
      print('Parse error: $e');
      return 'Currency detected';
    }
  }

  Future<void> _captureImage() async {
    if (_controller?.value.isInitialized != true) return;
    final file = await _controller!.takePicture();
    setState(() => _selectedImagePath = null);
    await _processImage(file.path, fromGallery: false);
  }

  Future<void> _pickImage() async {
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    await _processImage(file.path, fromGallery: true);
  }

  void _returnToCamera() {
    setState(() {
      _selectedImagePath = null;
      _detectedCurrency = "";
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: _controller == null || !_controller!.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Camera Preview or Selected Image
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
                                height: size.width * _controller!.value.aspectRatio,
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
                      child: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                    ),
                  ),
                ),

                // Mode indicator
                Positioned(
                  top: 40,
                  right: 16,
                  left: 80,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isApiConnected 
                          ? Colors.green.withOpacity(0.7)
                          : Colors.red.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.attach_money, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Currency Recognition ${_isApiConnected ? "Active" : "Offline"}',
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

                // Return to camera
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
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.camera_alt, color: Colors.white, size: 20),
                            SizedBox(width: 4),
                            Text('New Photo', style: TextStyle(color: Colors.white, fontSize: 12)),
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
                          const Text(
                            'Detected Currency:',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _detectedCurrency,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
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
                        // Gallery
                        GestureDetector(
                          onTap: _busy ? null : _pickImage,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.photo, size: 28, color: Colors.white),
                          ),
                        ),

                        // Capture
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
                                    : Icon(Icons.camera_alt, color: Colors.grey[800], size: 24),
                              ),
                            ),
                          ),
                        ),

                        // Switch camera
                        GestureDetector(
                          onTap: _busy || _selectedImagePath != null ? null : _switchCamera,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(_selectedImagePath != null ? 0.1 : 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.cameraswitch,
                              size: 28,
                              color: _selectedImagePath != null ? Colors.white38 : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Processing overlay
                if (_busy)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.25),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                            SizedBox(height: 16),
                            Text(
                              'Recognizing currency...',
                              style: TextStyle(
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