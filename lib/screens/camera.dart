import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'dart:convert';
import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../services/face_recognition_api.dart';

class CameraScreen extends StatefulWidget {
  final String mode; // 'text', 'color', or 'face'

  const CameraScreen({super.key, required this.mode});

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
  String _detectedColor = "";
  RecognitionResult? _faceResult;

  String? _selectedImagePath;
  String _processingMode = 'text';

  // IBM Watson TTS credentials
  static const String IBM_TTS_API_KEY =
      "Ibvg1Q2qca9ALJa1JCZVp09gFJMstnyeAXaOWKNrq6o-";
  static const String IBM_TTS_URL =
      "https://api.au-syd.text-to-speech.watson.cloud.ibm.com/instances/892ef34b-36b6-4ba6-b29c-d4a55108f114";

  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  static const Map<String, List<int>> _colorNames = {
    'red': [255, 0, 0],
    'green': [0, 128, 0],
    'blue': [0, 0, 255],
    'yellow': [255, 255, 0],
    'orange': [255, 165, 0],
    'purple': [128, 0, 128],
    'pink': [255, 192, 203],
    'brown': [165, 42, 42],
    'black': [0, 0, 0],
    'white': [255, 255, 255],
    'gray': [128, 128, 128],
    'grey': [128, 128, 128],
    'cyan': [0, 255, 255],
    'magenta': [255, 0, 255],
    'lime': [0, 255, 0],
    'maroon': [128, 0, 0],
    'navy': [0, 0, 128],
    'olive': [128, 128, 0],
    'silver': [192, 192, 192],
    'teal': [0, 128, 128],
    'aqua': [0, 255, 255],
    'fuchsia': [255, 0, 255],
    'gold': [255, 215, 0],
    'indigo': [75, 0, 130],
    'khaki': [240, 230, 140],
    'lavender': [230, 230, 250],
    'salmon': [250, 128, 114],
    'turquoise': [64, 224, 208],
    'violet': [238, 130, 238],
  };

  @override
  void initState() {
    super.initState();
    _processingMode = widget.mode;
    _initCamera();
    if (_processingMode == 'face') {
      _initFaceRecognition();
    }
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      // Use front camera for face recognition, back camera for others
      final cameraIndex = _processingMode == 'face' ? 1 : 0;
      _controller = CameraController(
        _cameras![cameraIndex < _cameras!.length ? cameraIndex : 0],
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (mounted) setState(() {});
    }
  }

  Future<void> _initFaceRecognition() async {
    print('🚀 Initializing Face Recognition API...');
    try {
      final apiConnected = await FaceRecognitionAPI.testConnection();
      if (apiConnected) {
        print('✅ Face Recognition API connected successfully');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Face recognition API connected'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print('❌ Failed to connect to Face Recognition API');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to connect to face recognition API'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ API initialization error: $e');
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

  Future<String> _extractTextFromImage(String imagePath) async {
    try {
      final InputImage inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );
      return recognizedText.text;
    } catch (e) {
      print('OCR Error: $e');
      return "";
    }
  }

  double _colorDistance(List<int> color1, List<int> color2) {
    double rDiff = (color1[0] - color2[0]).toDouble();
    double gDiff = (color1[1] - color2[1]).toDouble();
    double bDiff = (color1[2] - color2[2]).toDouble();
    return math.sqrt(rDiff * rDiff + gDiff * gDiff + bDiff * bDiff);
  }

  String _rgbToColorName(List<int> rgb) {
    String closestColor = 'unknown';
    double minDistance = double.infinity;

    _colorNames.forEach((name, colorRgb) {
      double distance = _colorDistance(rgb, colorRgb);
      if (distance < minDistance) {
        minDistance = distance;
        closestColor = name;
      }
    });

    return closestColor;
  }

  Future<List<int>> _getDominantColor(String imagePath) async {
    try {
      final File imageFile = File(imagePath);
      final Uint8List imageBytes = await imageFile.readAsBytes();

      final ui.Image image = await decodeImageFromList(imageBytes);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      if (byteData == null) return [128, 128, 128];

      final Uint8List pixels = byteData.buffer.asUint8List();

      final int width = image.width;
      final int height = image.height;
      final int cropWidth = (width * 0.6).round();
      final int cropHeight = (height * 0.6).round();
      final int startX = (width - cropWidth) ~/ 2;
      final int startY = (height - cropHeight) ~/ 2;

      Map<String, int> colorFrequency = {};

      for (int y = startY; y < startY + cropHeight; y += 3) {
        for (int x = startX; x < startX + cropWidth; x += 3) {
          final int pixelIndex = (y * width + x) * 4;

          if (pixelIndex + 2 < pixels.length) {
            final int r = pixels[pixelIndex];
            final int g = pixels[pixelIndex + 1];
            final int b = pixels[pixelIndex + 2];

            final double brightness = (r + g + b) / 3.0;
            final int maxRgb = math.max(r, math.max(g, b));
            final int minRgb = math.min(r, math.min(g, b));
            final double saturation = maxRgb == 0
                ? 0
                : (maxRgb - minRgb) / maxRgb;

            if (brightness > 40 && brightness < 245 && saturation > 0.15) {
              final String colorKey = '$r,$g,$b';
              colorFrequency[colorKey] = (colorFrequency[colorKey] ?? 0) + 1;
            }
          }
        }
      }

      if (colorFrequency.isEmpty) {
        return [128, 128, 128];
      }

      String mostFrequentColor = colorFrequency.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;

      List<String> rgbStrings = mostFrequentColor.split(',');
      return [
        int.parse(rgbStrings[0]),
        int.parse(rgbStrings[1]),
        int.parse(rgbStrings[2]),
      ];
    } catch (e) {
      print('Color detection error: $e');
      return [128, 128, 128];
    }
  }

  Future<String> _detectColorFromImage(String imagePath) async {
    try {
      List<int> dominantRgb = await _getDominantColor(imagePath);
      String colorName = _rgbToColorName(dominantRgb);
      return "The color is $colorName";
    } catch (e) {
      print('Color detection error: $e');
      return "Could not detect color";
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
      } else {
        print('TTS Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('TTS Exception: $e');
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

      String textToSpeak = "";

      if (_processingMode == 'text') {
        String extractedText = await _extractTextFromImage(imagePath);
        setState(() {
          _extractedText = extractedText;
          _detectedColor = "";
          _faceResult = null;
        });

        if (extractedText.trim().isNotEmpty) {
          textToSpeak = extractedText;
        } else {
          textToSpeak = "No text detected in the image";
        }
      } else if (_processingMode == 'color') {
        String detectedColor = await _detectColorFromImage(imagePath);
        setState(() {
          _detectedColor = detectedColor;
          _extractedText = "";
          _faceResult = null;
        });
        textToSpeak = detectedColor;
      } else if (_processingMode == 'face') {
        // Face Recognition using API
        print('🔍 Starting face recognition with API...');

        try {
          // قراءة bytes الصورة
          final imageBytes = await File(imagePath).readAsBytes();

          // استخدام الـ API للتعرف على الوجه
          final result = await FaceRecognitionAPI.recognizeFace(imageBytes);

          setState(() {
            _faceResult = result;
            _extractedText = "";
            _detectedColor = "";
          });

          if (result.isMatch) {
            textToSpeak = "Face recognized. This is ${result.personId}";
            print(
              '✅ Match found: ${result.personId} with ${result.confidence}% confidence',
            );
          } else {
            textToSpeak = "Face detected but not recognized. Unknown person";
            print('⚠️ No match found');
          }

          // Show result dialog
          _showFaceResultDialog(result, imagePath);
        } catch (e) {
          print('❌ Face recognition error: $e');
          textToSpeak = "Error recognizing face. Please try again";

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Face recognition error: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }

      print("==== Processing Result (Mode: $_processingMode) ====");
      if (_processingMode == 'text' && _extractedText.isNotEmpty) {
        print("Text: $_extractedText");
      } else if (_processingMode == 'color' && _detectedColor.isNotEmpty) {
        print("Color: $_detectedColor");
      } else if (_processingMode == 'face' && _faceResult != null) {
        print("Face: $_faceResult");
      }

      if (textToSpeak.trim().isNotEmpty) {
        String? audioPath = await _convertTextToSpeech(textToSpeak);

        if (audioPath != null) {
          await _player.stop();
          await _player.play(DeviceFileSource(audioPath));

          if (mounted) {
            String successMessage;
            switch (_processingMode) {
              case 'color':
                successMessage = 'Color detected and playing audio!';
                break;
              case 'face':
                successMessage = 'Face processed and playing audio!';
                break;
              default:
                successMessage = 'Text extracted and playing audio!';
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(successMessage),
                backgroundColor: Colors.green,
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

  void _showFaceResultDialog(RecognitionResult result, String imagePath) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              result.isMatch ? Icons.check_circle : Icons.cancel,
              color: result.isMatch ? Colors.green : Colors.red,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                result.isMatch ? 'Face Recognized!' : 'Unknown Face',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(imagePath),
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            if (result.isMatch) ...[
              _buildInfoRow('Name', result.personId, Icons.person),
              _buildInfoRow(
                'Confidence',
                '${result.confidence.toStringAsFixed(1)}%',
                Icons.analytics,
              ),
              _buildInfoRow(
                'Similarity',
                '${result.similarity.toStringAsFixed(1)}%',
                Icons.percent,
              ),
            ] else ...[
              _buildInfoRow('Status', 'Not in database', Icons.person_outline),
              _buildInfoRow(
                'Best Match',
                result.personId != 'Unknown' ? result.personId : 'None',
                Icons.search,
              ),
              _buildInfoRow(
                'Confidence',
                '${result.confidence.toStringAsFixed(1)}%',
                Icons.analytics,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Person not found in database',
                        style: TextStyle(fontSize: 13, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (result.isMatch)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Done'),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFFB14ABA)),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _captureImage() async {
    if (_controller?.value.isInitialized != true) return;
    final file = await _controller!.takePicture();

    setState(() {
      _selectedImagePath = null;
    });

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
      _detectedColor = "";
      _faceResult = null;
    });
  }

  String get _getModeDescription {
    switch (_processingMode) {
      case 'text':
        return 'Text Reading Mode';
      case 'color':
        return 'Color Detection Mode';
      case 'face':
        return 'Face Recognition Mode';
      default:
        return 'Unknown mode';
    }
  }

  IconData get _getModeIcon {
    switch (_processingMode) {
      case 'text':
        return Icons.text_fields;
      case 'color':
        return Icons.color_lens;
      case 'face':
        return Icons.face;
      default:
        return Icons.help;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _player.dispose();
    _textRecognizer.close();
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
                                height:
                                    size.width * _controller!.value.aspectRatio,
                                child: CameraPreview(_controller!),
                              ),
                            ),
                          ),
                        ),
                ),

                // Face Detection Frame (only for face mode)
                if (_processingMode == 'face' && _selectedImagePath == null)
                  Center(
                    child: Container(
                      width: 280,
                      height: 350,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _busy
                              ? Colors.orange
                              : (_faceResult != null
                                    ? (_faceResult!.isMatch
                                          ? Colors.green
                                          : Colors.red)
                                    : Colors.white),
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Stack(
                        children: [
                          // Corner indicators
                          Positioned(
                            top: -2,
                            left: -2,
                            child: _buildCornerIndicator(),
                          ),
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Transform.rotate(
                              angle: 1.5708,
                              child: _buildCornerIndicator(),
                            ),
                          ),
                          Positioned(
                            bottom: -2,
                            left: -2,
                            child: Transform.rotate(
                              angle: -1.5708,
                              child: _buildCornerIndicator(),
                            ),
                          ),
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: Transform.rotate(
                              angle: 3.14159,
                              child: _buildCornerIndicator(),
                            ),
                          ),
                        ],
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
                        Icon(_getModeIcon, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _getModeDescription,
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

                // Results display
                if ((_processingMode == 'text' && _extractedText.isNotEmpty) ||
                    (_processingMode == 'color' && _detectedColor.isNotEmpty) ||
                    (_processingMode == 'face' && _faceResult != null))
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
                          if (_processingMode == 'text' &&
                              _extractedText.isNotEmpty) ...[
                            const Text(
                              'Extracted Text:',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _extractedText,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (_processingMode == 'color' &&
                              _detectedColor.isNotEmpty) ...[
                            const Text(
                              'Detected Color:',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _detectedColor,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                          if (_processingMode == 'face' &&
                              _faceResult != null) ...[
                            Text(
                              _faceResult!.isMatch ? 'Recognized:' : 'Status:',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _faceResult!.isMatch
                                  ? _faceResult!.personId
                                  : 'Unknown Person',
                              style: TextStyle(
                                color: _faceResult!.isMatch
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Confidence: ${_faceResult!.confidence.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
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

                // Processing overlay
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
                              _processingMode == 'color'
                                  ? 'Detecting color...'
                                  : _processingMode == 'face'
                                  ? 'Recognizing face...'
                                  : 'Processing text...',
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

  Widget _buildCornerIndicator() {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: _busy
                ? Colors.orange
                : (_faceResult != null
                      ? (_faceResult!.isMatch ? Colors.green : Colors.red)
                      : Colors.white),
            width: 4,
          ),
          left: BorderSide(
            color: _busy
                ? Colors.orange
                : (_faceResult != null
                      ? (_faceResult!.isMatch ? Colors.green : Colors.red)
                      : Colors.white),
            width: 4,
          ),
        ),
      ),
    );
  }
}
