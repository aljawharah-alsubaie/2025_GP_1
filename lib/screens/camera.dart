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

class CameraScreen extends StatefulWidget {
  final String mode; // 'text' or 'color' - passed from home page

  const CameraScreen({super.key, required this.mode});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  final picker = ImagePicker();

  // Audio player
  final AudioPlayer _player = AudioPlayer();
  bool _busy = false;
  String _extractedText = "";
  String _detectedColor = "";

  // Store the selected image path
  String? _selectedImagePath;

  // Processing mode: 'text', 'color', or 'both'
  String _processingMode = 'text';

  // IBM Watson TTS credentials
  static const String IBM_TTS_API_KEY =
      "Ibvg1Q2qca9ALJa1JCZVp09gFJMstnyeAXaOWKNrq6o-";
  static const String IBM_TTS_URL =
      "https://api.au-syd.text-to-speech.watson.cloud.ibm.com/instances/892ef34b-36b6-4ba6-b29c-d4a55108f114";

  // OCR service
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  // Color names mapping (basic CSS3 colors)
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
    _processingMode =
        widget.mode; // Set the processing mode from the widget parameter
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      _controller = CameraController(
        _cameras![0],
        ResolutionPreset.max,
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
      ResolutionPreset.max,
      enableAudio: false,
    );
    await _controller!.initialize();
    if (mounted) setState(() {});
  }

  // OCR function
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

  // Color detection functions
  double _colorDistance(List<int> color1, List<int> color2) {
    // Calculate Euclidean distance between two RGB colors
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

      // Decode image
      final ui.Image image = await decodeImageFromList(imageBytes);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      if (byteData == null) return [128, 128, 128]; // Default gray

      final Uint8List pixels = byteData.buffer.asUint8List();

      // Get center crop (60% of image)
      final int width = image.width;
      final int height = image.height;
      final int cropWidth = (width * 0.6).round();
      final int cropHeight = (height * 0.6).round();
      final int startX = (width - cropWidth) ~/ 2;
      final int startY = (height - cropHeight) ~/ 2;

      Map<String, int> colorFrequency = {};
      int totalValidPixels = 0;

      // Sample pixels from center crop
      for (int y = startY; y < startY + cropHeight; y += 3) {
        // Sample every 3rd pixel for performance
        for (int x = startX; x < startX + cropWidth; x += 3) {
          final int pixelIndex = (y * width + x) * 4; // RGBA format

          if (pixelIndex + 2 < pixels.length) {
            final int r = pixels[pixelIndex];
            final int g = pixels[pixelIndex + 1];
            final int b = pixels[pixelIndex + 2];

            // Filter out very dark, very bright, or very desaturated colors
            final double brightness = (r + g + b) / 3.0;
            final int maxRgb = math.max(r, math.max(g, b));
            final int minRgb = math.min(r, math.min(g, b));
            final double saturation = maxRgb == 0
                ? 0
                : (maxRgb - minRgb) / maxRgb;

            if (brightness > 40 && brightness < 245 && saturation > 0.15) {
              final String colorKey = '$r,$g,$b';
              colorFrequency[colorKey] = (colorFrequency[colorKey] ?? 0) + 1;
              totalValidPixels++;
            }
          }
        }
      }

      if (colorFrequency.isEmpty) {
        return [128, 128, 128]; // Default gray if no valid colors found
      }

      // Find the most frequent color
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
      return [128, 128, 128]; // Default gray on error
    }
  }

  Future<String> _detectColorFromImage(String imagePath) async {
    try {
      List<int> dominantRgb = await _getDominantColor(imagePath);
      String colorName = _rgbToColorName(dominantRgb);
      return "The  color is $colorName ";
    } catch (e) {
      print('Color detection error: $e');
      return "Could not detect color";
    }
  }

  // TTS function
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

  // Process image based on selected mode (STRICT - no mixing)
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

      // STRICT MODE SEPARATION - only process what was selected from home page
      if (_processingMode == 'text') {
        // ONLY extract text, ignore color completely
        String extractedText = await _extractTextFromImage(imagePath);
        setState(() {
          _extractedText = extractedText;
          _detectedColor = ""; // Clear color info
        });

        if (extractedText.trim().isNotEmpty) {
          textToSpeak = extractedText;
        } else {
          textToSpeak = "No text detected in the image";
        }
      } else if (_processingMode == 'color') {
        // ONLY detect color, ignore text completely
        String detectedColor = await _detectColorFromImage(imagePath);
        setState(() {
          _detectedColor = detectedColor;
          _extractedText = ""; // Clear text info
        });
        textToSpeak = detectedColor;
      }

      print("==== Processing Result (Mode: $_processingMode) ====");
      if (_processingMode == 'text' && _extractedText.isNotEmpty) {
        print("Text: $_extractedText");
      } else if (_processingMode == 'color' && _detectedColor.isNotEmpty) {
        print("Color: $_detectedColor");
      }

      if (textToSpeak.trim().isNotEmpty) {
        // Convert to speech and play
        String? audioPath = await _convertTextToSpeech(textToSpeak);

        if (audioPath != null) {
          await _player.stop();
          await _player.play(DeviceFileSource(audioPath));

          if (mounted) {
            String successMessage = _processingMode == 'color'
                ? 'Color detected and playing audio!'
                : 'Text extracted and playing audio!';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(successMessage),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Analysis complete but audio conversion failed'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          String errorMessage = _processingMode == 'color'
              ? 'Could not detect color in the image!'
              : 'No text detected in the image!';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
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
    });
  }

  String get _getModeDescription {
    switch (_processingMode) {
      case 'text':
        return 'Text Reading Mode';
      case 'color':
        return 'Color Detection Mode';
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
                // Show selected image or camera preview
                Positioned.fill(
                  child: _selectedImagePath != null
                      ? Image.file(File(_selectedImagePath!), fit: BoxFit.cover)
                      : Positioned.fill(
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

                // Mode info (no switch button - mode is fixed from home page)
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
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _getModeDescription,
                            style: TextStyle(
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

                // Return to camera button when image is selected
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

                // Results display - only show relevant result based on mode
                if ((_processingMode == 'text' && _extractedText.isNotEmpty) ||
                    (_processingMode == 'color' && _detectedColor.isNotEmpty))
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
                            Text(
                              'Extracted Text:',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              _extractedText,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (_processingMode == 'color' &&
                              _detectedColor.isNotEmpty) ...[
                            Text(
                              'Detected Color:',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              _detectedColor,
                              style: TextStyle(
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
                                    ? Padding(
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

                        // Camera switch (only show when in camera mode)
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
                            CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                            SizedBox(height: 16),
                            Text(
                              _processingMode == 'color'
                                  ? 'Detecting color...'
                                  : 'Processing text...',
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