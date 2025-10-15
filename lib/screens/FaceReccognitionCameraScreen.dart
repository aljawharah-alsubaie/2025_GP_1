import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/face_recognition_service.dart';

class FaceRecognitionCameraScreen extends StatefulWidget {
  const FaceRecognitionCameraScreen({super.key});

  @override
  State<FaceRecognitionCameraScreen> createState() => _FaceRecognitionCameraScreenState();
}

class _FaceRecognitionCameraScreenState extends State<FaceRecognitionCameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  final picker = ImagePicker();

  // Audio player
  final AudioPlayer _player = AudioPlayer();
  bool _busy = false;
  
  // Store the selected image and recognition result
  String? _selectedImagePath;
  RecognitionResult? _recognitionResult;
  String? _recognizedPersonName;
  List<Map<String, dynamic>> _people = [];

  // IBM Watson TTS credentials
  static const String IBM_TTS_API_KEY = "Ibvg1Q2qca9ALJa1JCZVp09gFJMstnyeAXaOWKNrq6o-";
  static const String IBM_TTS_URL = "https://api.au-syd.text-to-speech.watson.cloud.ibm.com/instances/892ef34b-36b6-4ba6-b29c-d4a55108f114";

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadPeople();
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

  Future<void> _loadPeople() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('people')
          .get();

      setState(() {
        _people = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      });
    } catch (e) {
      print('Error loading people: $e');
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
        final String audioPath = '${tempDir.path}/face_rec_${DateTime.now().millisecondsSinceEpoch}.mp3';
        final File audioFile = File(audioPath);
        await audioFile.writeAsBytes(response.bodyBytes);
        return audioPath;
      } else {
        print('TTS Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('TTS Exception: $e');
      return null;
    }
  }

  Future<void> _speakRecognitionResult(String personName, double accuracy) async {
    String textToSpeak = "Recognized. $personName. Accuracy ${(accuracy * 100).round()} percent";
    
    try {
      String? audioPath = await _convertTextToSpeech(textToSpeak);
      if (audioPath != null) {
        await _player.stop();
        await _player.play(DeviceFileSource(audioPath));
      }
    } catch (e) {
      print('Error playing audio: $e');
    }
  }

  Future<void> _speakNoMatch() async {
    String textToSpeak = "No match found. Face not recognized.";
    
    try {
      String? audioPath = await _convertTextToSpeech(textToSpeak);
      if (audioPath != null) {
        await _player.stop();
        await _player.play(DeviceFileSource(audioPath));
      }
    } catch (e) {
      print('Error playing audio: $e');
    }
  }

  // Face recognition function
  Future<void> _recognizeFace(String imagePath, {bool fromGallery = false}) async {
    setState(() {
      _busy = true;
      _recognitionResult = null;
      _recognizedPersonName = null;
      if (fromGallery) _selectedImagePath = imagePath;
    });

    try {
      final imageFile = File(imagePath);
      final result = await FaceRecognitionService.recognizeFace(
        imageFile,
        threshold: 0.25,
        normalizationType: 'arcface',
        useAdaptiveThreshold: true,
      );

      if (result != null) {
        if (result.isMatch) {
          // Find person name
          final person = _people.firstWhere(
            (p) => p['id'] == result.personId,
            orElse: () => {'name': 'Unknown'},
          );
          
          setState(() {
            _recognitionResult = result;
            _recognizedPersonName = person['name'] ?? 'Unknown';
          });

          // Speak the result
          await _speakRecognitionResult(_recognizedPersonName!, result.similarity);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Recognized: $_recognizedPersonName (${(result.similarity * 100).toStringAsFixed(1)}%)'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          setState(() {
            _recognitionResult = result;
            _recognizedPersonName = null;
          });

          // Speak no match
          await _speakNoMatch();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('No match found (${(result.similarity * 100).toStringAsFixed(1)}% similarity)'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No face detected in the image'),
              backgroundColor: Colors.red,
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

  Future<void> _captureImage() async {
    if (_controller?.value.isInitialized != true) return;
    final file = await _controller!.takePicture();

    setState(() {
      _selectedImagePath = null;
    });

    await _recognizeFace(file.path, fromGallery: false);
  }

  Future<void> _pickImage() async {
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    await _recognizeFace(file.path, fromGallery: true);
  }

  void _returnToCamera() {
    setState(() {
      _selectedImagePath = null;
      _recognitionResult = null;
      _recognizedPersonName = null;
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
                // Camera preview or selected image
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
                        color: Colors.black.withOpacity(0.5),
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

                // Mode indicator
                Positioned(
                  top: 40,
                  right: 16,
                  left: 80,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B1D73).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.face_retouching_natural, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Face Recognition Mode',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.camera_alt, color: Colors.white, size: 18),
                            SizedBox(width: 4),
                            Text(
                              'New Photo',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Recognition result display
                if (_recognitionResult != null)
                  Positioned(
                    top: 140,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _recognitionResult!.isMatch 
                            ? Colors.green.withOpacity(0.95)
                            : Colors.orange.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _recognitionResult!.isMatch ? Icons.check_circle : Icons.person_search,
                            color: Colors.white,
                            size: 40,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _recognitionResult!.isMatch ? 'Face Recognized!' : 'No Match Found',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_recognizedPersonName != null) ...[
                            const Divider(color: Colors.white70, height: 20),
                            Row(
                              children: [
                                const Icon(Icons.person, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Name: $_recognizedPersonName',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              const Icon(Icons.speed, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Accuracy: ${(_recognitionResult!.similarity * 100).toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
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
                      color: Colors.black.withOpacity(0.3),
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
                              color: Colors.white.withOpacity(_busy ? 0.1 : 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.photo,
                              size: 28,
                              color: _busy ? Colors.white38 : Colors.white,
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
                                  color: _busy ? const Color(0xFF6B1D73) : Colors.white,
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
                                        Icons.face_retouching_natural,
                                        color: Colors.grey[800],
                                        size: 28,
                                      ),
                              ),
                            ),
                          ),
                        ),

                        // Camera switch
                        GestureDetector(
                          onTap: _busy || _selectedImagePath != null ? null : _switchCamera,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(
                                _busy || _selectedImagePath != null ? 0.1 : 0.2,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.cameraswitch,
                              size: 28,
                              color: _busy || _selectedImagePath != null
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
                      color: Colors.black.withOpacity(0.4),
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
                              'Recognizing face...',
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