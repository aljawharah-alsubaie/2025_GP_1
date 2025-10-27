import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ColorCameraPage extends StatefulWidget {
  const ColorCameraPage({Key? key}) : super(key: key);

  @override
  State<ColorCameraPage> createState() => _ColorCameraPageState();
}

class _ColorCameraPageState extends State<ColorCameraPage> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  String _descriptionText = '';

  // IBM Watson TTS Credentials 
  final String _ibmApiKey = 'Ibvg1Q2qca9ALJa1JCZVp09gFJMstnyeAXaOWKNrq6o-';
  final String _ibmUrl = "https://api.au-syd.text-to-speech.watson.cloud.ibm.com/instances/892ef34b-36b6-4ba6-b29c-d4a55108f114";

  final AudioPlayer _audioPlayer = AudioPlayer();

  // OpenAI API Key (from .env)
  String get _openAIApiKey => dotenv.env['OPENAI_API_KEY'] ?? '';
  final String _openAIUrl = 'https://api.openai.com/v1/chat/completions';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: false,
        );

        await _cameraController!.initialize();

        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      _speakIBM('Failed to initialize camera');
    }
  }

  // ✅ IBM Watson TTS Function
  Future<void> _speakIBM(String text) async {
    try {
      final response = await http.post(
        Uri.parse('$_ibmUrl/v1/synthesize'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic ${base64Encode(utf8.encode('apikey:$_ibmApiKey'))}',
        },
        body: jsonEncode({
          'text': text,
          'voice': 'en-US_AllisonV3Voice',
          'accept': 'audio/mp3',
        }),
      );

      if (response.statusCode == 200) {
        final tempDir = await Directory.systemTemp.createTemp();
        final tempFile = File('${tempDir.path}/tts_audio.mp3');
        await tempFile.writeAsBytes(response.bodyBytes);
        await _audioPlayer.play(DeviceFileSource(tempFile.path));
      } else {
        debugPrint('IBM TTS Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('IBM TTS Exception: $e');
    }
  }

  // ✅ OpenAI Vision API Function
  Future<String> _describeImageWithOpenAI(File imageFile) async {
    if (_openAIApiKey.isEmpty) {
      return 'OpenAI API key not configured. Please check your .env file.';
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse(_openAIUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_openAIApiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o',
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': 'Describe this image in 1-2 short sentences for a blind user. Identify the main object and describe its colors precisely. Be specific about color patterns (stripes, solid, etc.) but keep it brief and useful. Example: "A striped shirt with black and white horizontal stripes".',
                },
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,$base64Image',
                  },
                },
              ],
            },
          ],
          'max_tokens': 100,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        debugPrint('OpenAI Error: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return 'Sorry, I could not analyze the image. Please try again.';
      }
    } catch (e) {
      debugPrint('OpenAI Exception: $e');
      return 'An error occurred while analyzing the image.';
    }
  }

  // ✅ Main Capture and Describe Function
  Future<void> _captureAndDescribe() async {
    if (_cameraController == null || 
        !_cameraController!.value.isInitialized || 
        _isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _descriptionText = 'Analyzing image...';
    });

    // Speak feedback
    await _speakIBM('Taking picture');

    try {
      // Capture the image
      final XFile imageFile = await _cameraController!.takePicture();
      final File file = File(imageFile.path);

      // Notify user
      await _speakIBM('Processing image');

      // Get description from OpenAI
      final description = await _describeImageWithOpenAI(file);

      setState(() {
        _descriptionText = description;
        _isProcessing = false;
      });

      // Speak the description
      await _speakIBM(description);

      // Delete temporary file
      try {
        await file.delete();
      } catch (e) {
        debugPrint('Error deleting temp file: $e');
      }

    } catch (e) {
      debugPrint('Error capturing/describing image: $e');
      
      setState(() {
        _descriptionText = 'Error processing image';
        _isProcessing = false;
      });
      
      await _speakIBM('Error processing image. Please try again.');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _cameraController == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Color Camera'),
          backgroundColor: Colors.purple,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Color Camera'),
        backgroundColor: Colors.purple,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Column(
        children: [
          // Camera Preview
          Expanded(
            flex: 3,
            child: CameraPreview(_cameraController!),
          ),

          // Description Display
          Expanded(
            flex: 1,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.purple.shade900,
                    Colors.purple.shade700,
                  ],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _descriptionText.isEmpty
                        ? 'Press the button to capture and describe'
                        : _descriptionText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_isProcessing)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),

      // Capture Button
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isProcessing ? null : _captureAndDescribe,
        backgroundColor: _isProcessing ? Colors.grey : Colors.purple,
        icon: _isProcessing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.camera_alt, size: 28),
        label: Text(
          _isProcessing ? 'Processing...' : 'Capture & Describe',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}