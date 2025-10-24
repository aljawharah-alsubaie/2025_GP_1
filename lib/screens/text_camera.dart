import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  final picker = ImagePicker();
  final AudioPlayer _player = AudioPlayer();

  bool _busy = false;
  String _extractedText = "";
  String? _selectedImagePath;

  // IBM Watson TTS
  static const String IBM_TTS_API_KEY =
      "Ibvg1Q2qca9ALJa1JCZVp09gFJMstnyeAXaOWKNrq6o-";
  static const String IBM_TTS_URL =
      "https://api.au-syd.text-to-speech.watson.cloud.ibm.com/instances/892ef34b-36b6-4ba6-b29c-d4a55108f114";

  @override
  void initState() {
    super.initState();
    _initCamera();
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

  // معالجة الصورة لتحسين OCR
  Future<File> _preprocessImage(File imageFile) async {
    print('🔧 Preprocessing image for better OCR...');

    try {
      final bytes = await imageFile.readAsBytes();
      img.Image? image = img.decodeImage(bytes);

      if (image != null) {
        // 1. تصغير الحجم إذا كانت كبيرة جداً (تسريع المعالجة)
        if (image.width > 2000) {
          image = img.copyResize(image, width: 2000);
        }

        // 2. تحويل لأبيض وأسود
        image = img.grayscale(image);

        // 3. زيادة التباين
        image = img.contrast(image, contrast: 150);

        // 4. إزالة الضوضاء
        image = img.gaussianBlur(image, radius: 1);

        // 5. Sharpen
        image = img.adjustColor(image, brightness: 1.05, contrast: 1.2);

        // حفظ مؤقت
        final tempDir = await getTemporaryDirectory();
        final processedPath =
            '${tempDir.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final processedFile = File(processedPath);
        await processedFile.writeAsBytes(img.encodeJpg(image, quality: 95));

        print('✅ Image preprocessed successfully');
        return processedFile;
      }
    } catch (e) {
      print('⚠️ Preprocessing failed, using original: $e');
    }

    return imageFile;
  }

  Future<String> _extractTextFromImage(File imageFile) async {
    try {
      print('📸 Starting advanced OCR...');

      // معالجة الصورة أولاً
      final processedImage = await _preprocessImage(imageFile);

      // Tesseract OCR مع إعدادات محسّنة
      String text = await FlutterTesseractOcr.extractText(
        processedImage.path,
        language: 'ara+eng', // عربي + إنجليزي
        args: {
          "psm": "3", // Fully automatic page segmentation
          "preserve_interword_spaces": "1",
        },
      );

      // تنظيف النص
      text = text.trim();

      // حذف الصورة المؤقتة
      if (processedImage.path != imageFile.path) {
        try {
          await processedImage.delete();
        } catch (e) {
          print('Could not delete temp file: $e');
        }
      }

      print('✅ OCR completed! Text length: ${text.length} chars');
      return text;
    } catch (e) {
      print('❌ OCR Error: $e');
      return "";
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
        final String audioPath =
            '${tempDir.path}/output_${DateTime.now().millisecondsSinceEpoch}.mp3';
        final File audioFile = File(audioPath);
        await audioFile.writeAsBytes(response.bodyBytes);
        return audioPath;
      }
      return null;
    } catch (e) {
      print('❌ TTS Error: $e');
      return null;
    }
  }

  Future<void> _processImage(
    String imagePath, {
    bool fromGallery = false,
  }) async {
    setState(() => _busy = true);

    try {
      if (fromGallery) {
        _selectedImagePath = imagePath;
      }

      // استخراج النص
      String extractedText = await _extractTextFromImage(File(imagePath));

      setState(() {
        _extractedText = extractedText;
      });

      String textToSpeak = "";
      if (extractedText.trim().isNotEmpty) {
        textToSpeak = extractedText;
        print("✅ Extracted: $extractedText");
      } else {
        textToSpeak = "No text detected in the image";
        print("⚠️ No text found");
      }

      // تحويل لصوت
      if (textToSpeak.trim().isNotEmpty) {
        String? audioPath = await _convertTextToSpeech(textToSpeak);

        if (audioPath != null) {
          await _player.stop();
          await _player.play(DeviceFileSource(audioPath));

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  extractedText.isNotEmpty
                      ? 'Text extracted successfully! 📄'
                      : 'No text found in image',
                ),
                backgroundColor: extractedText.isNotEmpty
                    ? Colors.green
                    : Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      print('❌ Processing error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
      _extractedText = "";
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
                // Camera Preview
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
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),

                // Title
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
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.text_fields, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Advanced Text Recognition',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
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
                            Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 20,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'New Photo',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Results Display
                if (_extractedText.isNotEmpty)
                  Positioned(
                    top: 140,
                    left: 16,
                    right: 16,
                    child: Container(
                      constraints: BoxConstraints(maxHeight: size.height * 0.5),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.greenAccent,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Extracted Text:',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white24, height: 20),
                            Text(
                              _extractedText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${_extractedText.split(' ').length} words',
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  '${_extractedText.length} characters',
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Bottom Controls
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
                            child: const Icon(
                              Icons.photo,
                              size: 28,
                              color: Colors.white,
                            ),
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
                                    : Icon(
                                        Icons.camera_alt,
                                        color: Colors.grey[800],
                                        size: 24,
                                      ),
                              ),
                            ),
                          ),
                        ),

                        // Switch Camera
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

                // Processing Overlay
                if (_busy)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.3),
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
                              'Processing image...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Enhancing & extracting text',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
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
