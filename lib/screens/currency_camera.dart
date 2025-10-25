import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:math';

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
  
  Interpreter? _interpreter;
  bool _modelLoaded = false;
  String _loadingStatus = '📥 جاري تحميل الموديل...';
  
  bool _busy = false;
  String _detectedCurrency = "";
  double _confidence = 0.0;
  String? _selectedImagePath;
  int _waitingSeconds = 3;

  static const List<String> CURRENCY_LABELS = [
    '10 SR', '100 SR', '200 SR', '5 SR', '50 SR', '500 SR'
  ];

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await _loadModel();
      await _initCamera();
    } catch (e) {
      print('❌ خطأ في التهيئة: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadModel() async {
    try {
      setState(() => _loadingStatus = '📥 جاري تحميل الموديل...');
      print('📥 تحميل الموديل...\n');
      
      await Future.delayed(const Duration(seconds: 3));
      
      _interpreter = await Interpreter.fromAsset('assets/models/banknote_model.tflite');
      
      setState(() {
        _modelLoaded = true;
        _loadingStatus = '✅ تم تحميل الموديل!';
      });
      
      print('✅ تم تحميل الموديل بنجاح!\n');
      await Future.delayed(const Duration(seconds: 1));
      
    } catch (e) {
      print('❌ خطأ في تحميل الموديل: $e');
      setState(() => _loadingStatus = '❌ فشل تحميل الموديل\n$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في تحميل الموديل: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> _initCamera() async {
    try {
      setState(() => _loadingStatus = '📷 جاري تهيئة الكاميرة...');
      print('📷 تهيئة الكاميرة...\n');
      
      _cameras = await availableCameras();
      
      if (_cameras != null && _cameras!.isNotEmpty) {
        _controller = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: false,
        );
        
        await _controller!.initialize();
        
        if (mounted) {
          setState(() => _loadingStatus = '✅ جاهز!');
        }
        
        print('✅ تم تهيئة الكاميرة!\n');
        await Future.delayed(const Duration(seconds: 1));
        
        if (mounted) {
          setState(() => _modelLoaded = true);
        }
      }
    } catch (e) {
      print('❌ خطأ في الكاميرة: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ في الكاميرة: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;
    final newIndex = _controller!.description == _cameras![0] ? 1 : 0;
    _controller = CameraController(_cameras![newIndex], ResolutionPreset.high, enableAudio: false);
    await _controller!.initialize();
    if (mounted) setState(() {});
  }

  // معالجة الصورة - نفس طريقة Colab
  Future<List<List<List<List<double>>>>> _preprocessImage(String imagePath) async {
    try {
      final imageFile = File(imagePath);
      final bytes = await imageFile.readAsBytes();
      var image = img.decodeImage(bytes);
      
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      print('📊 حجم الصورة الأصلي: ${image.width}x${image.height}');

      // ⭐ تغيير حجم مع INTER_AREA (مثل Colab)
      image = img.copyResize(image, width: 224, height: 224);
      print('📊 حجم الصورة بعد التغيير: ${image.width}x${image.height}');

      // ⭐ تحويل لـ RGB (مثل Colab cv2.cvtColor BGR2RGB)
      // image package يستخدم RGB أصلاً، لكن تأكد

      // ⭐ تطبيق Gamma Correction (مثل Colab)
      double gamma = 1.2;
      
      List<List<List<List<double>>>> input = [];
      
      for (int batch = 0; batch < 1; batch++) {
        List<List<List<double>>> batchData = [];
        
        for (int y = 0; y < 224; y++) {
          List<List<double>> rowData = [];
          
          for (int x = 0; x < 224; x++) {
            final pixel = image.getPixel(x, y);
            
            // ⭐ استخراج RGB
            double r = pixel.r.toDouble() / 255.0;
            double g = pixel.g.toDouble() / 255.0;
            double b = pixel.b.toDouble() / 255.0;
            
            // ⭐ تطبيق Gamma Correction (مثل Colab)
            r = pow(r, 1.0 / gamma).toDouble();
            g = pow(g, 1.0 / gamma).toDouble();
            b = pow(b, 1.0 / gamma).toDouble();
            
            // تأكد من أن القيم بين 0 و 1
            r = r.clamp(0.0, 1.0);
            g = g.clamp(0.0, 1.0);
            b = b.clamp(0.0, 1.0);
            
            rowData.add([r, g, b]);
          }
          
          batchData.add(rowData);
        }
        
        input.add(batchData);
      }

      print('✅ Input shape: [1, 224, 224, 3]');
      return input;
    } catch (e) {
      print('❌ خطأ في معالجة الصورة: $e');
      rethrow;
    }
  }

  // 2️⃣ DEBUG
  void _debugModelInput(List<List<List<List<double>>>> input) {
    print('\n🔍 === DEBUG MODEL INPUT ===');
    print('📊 Shape: [${input.length}, ${input[0].length}, ${input[0][0].length}, ${input[0][0][0].length}]');
    
    print('\n📸 أول 3 pixels من الصف الأول:');
    for (int x = 0; x < 3; x++) {
      final rgb = input[0][0][x];
      print('  Pixel[$x]: R=${rgb[0].toStringAsFixed(3)}, G=${rgb[1].toStringAsFixed(3)}, B=${rgb[2].toStringAsFixed(3)}');
    }
    
    double minVal = 1.0, maxVal = 0.0, avgVal = 0.0;
    int count = 0;
    
    for (int y = 0; y < input[0].length; y++) {
      for (int x = 0; x < input[0][y].length; x++) {
        for (int c = 0; c < input[0][y][x].length; c++) {
          double val = input[0][y][x][c];
          minVal = val < minVal ? val : minVal;
          maxVal = val > maxVal ? val : maxVal;
          avgVal += val;
          count++;
        }
      }
    }
    avgVal /= count;
    
    print('\n📊 إحصائيات الـ Input:');
    print('  Min Value: ${minVal.toStringAsFixed(4)} (يجب ≈ 0.0)');
    print('  Max Value: ${maxVal.toStringAsFixed(4)} (يجب ≈ 1.0)');
    print('  Avg Value: ${avgVal.toStringAsFixed(4)} (يجب ≈ 0.5)');
    print('  Total pixels: $count');
    
    print('🔍 === END DEBUG ===\n');
  }

  // 3️⃣ التنبؤ
  Future<Map<String, dynamic>> _predictCurrency(String imagePath) async {
    try {
      if (_interpreter == null) {
        throw Exception('الموديل لم يحمل بعد! حاول لاحقاً');
      }

      print('🔄 معالجة الصورة...');
      final input = await _preprocessImage(imagePath);
      
      _debugModelInput(input);
      
      List<List<double>> output = [List.filled(CURRENCY_LABELS.length, 0.0)];
      
      print('🧠 جاري التنبؤ...');
      _interpreter!.run(input, output);
      
      List<double> predictions = output[0];
      
      print('📊 النتائج الخام: $predictions');
      
      print('\n📈 تحليل التنبؤات:');
      for (int i = 0; i < predictions.length; i++) {
        print('  ${CURRENCY_LABELS[i]}: ${(predictions[i] * 100).toStringAsFixed(2)}%');
      }
      
      double maxConfidence = 0;
      int maxIndex = 0;
      
      for (int i = 0; i < predictions.length; i++) {
        if (predictions[i] > maxConfidence) {
          maxConfidence = predictions[i];
          maxIndex = i;
        }
      }
      
      return {
        'currency': CURRENCY_LABELS[maxIndex],
        'confidence': maxConfidence,
        'all_predictions': predictions,
      };
    } catch (e) {
      print('❌ خطأ في التنبؤ: $e');
      rethrow;
    }
  }

  // 4️⃣ التعرف على العملة
  Future<void> _recognizeCurrency(String imagePath) async {
    if (!_modelLoaded || _interpreter == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ الموديل لم يحمل بعد... حاول بعد قليل'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() => _busy = true);
    try {
      print('🔄 جاري المعالجة...\n');
      
      final result = await _predictCurrency(imagePath);
      
      final currency = result['currency'] as String;
      final confidence = result['confidence'] as double;
      
      setState(() {
        _detectedCurrency = currency;
        _confidence = confidence;
      });

      print('✅ النتيجة: $currency (${(confidence * 100).toStringAsFixed(1)}%)\n');

      await _playSound();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $currency (${(confidence * 100).toStringAsFixed(1)}%)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ خطأ: $e');
      setState(() => _detectedCurrency = 'Error: ${e.toString()}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _playSound() async {
    try {
      await _player.play(AssetSource('sounds/beep.wav'));
    } catch (e) {
      print('⚠️ لا توجد ملف صوت');
    }
  }

  Future<void> _captureImage() async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) return;
      final image = await _controller!.takePicture();
      setState(() => _selectedImagePath = image.path);
      await _recognizeCurrency(image.path);
    } catch (e) {
      print('❌ خطأ: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() => _selectedImagePath = pickedFile.path);
        await _recognizeCurrency(pickedFile.path);
      }
    } catch (e) {
      print('❌ خطأ: $e');
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_modelLoaded || _controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.blue[900]!, Colors.blue[600]!],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.attach_money, size: 60, color: Colors.white),
                ),
                const SizedBox(height: 40),
                const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                const SizedBox(height: 30),
                Text(
                  _loadingStatus,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Please wait $_waitingSeconds seconds...',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          if (_selectedImagePath != null)
            Image.file(File(_selectedImagePath!), fit: BoxFit.cover)
          else
            CameraPreview(_controller!),

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

          // Status indicator
          Positioned(
            top: 40,
            right: 16,
            left: 80,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _modelLoaded ? Colors.green.withOpacity(0.7) : Colors.red.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _modelLoaded ? 'Model: Ready ✅' : 'Model: Loading',
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

          // Return button
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
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _confidence,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _confidence > 0.8 ? Colors.green : 
                        _confidence > 0.6 ? Colors.yellow : 
                        Colors.red
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Confidence: ${(_confidence * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
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