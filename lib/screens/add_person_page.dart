import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_tts/flutter_tts.dart';
import '../services/insightface_pipeline.dart';

class AddPersonPage extends StatefulWidget {
  const AddPersonPage({super.key});

  @override
  State<AddPersonPage> createState() => _AddPersonPageState();
}

class _AddPersonPageState extends State<AddPersonPage> {
  final TextEditingController _nameController = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  List<File> _selectedImages = [];
  final int _minImages = 1;
  final int _maxImages = 10;
  bool _isUploading = false;
  bool _isProcessing = false;

  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  Future<void> _pickImages() async {
    if (_selectedImages.length >= _maxImages) {
      _showSnackBar('Maximum $_maxImages photos allowed', Colors.orange);
      return;
    }

    try {
      final List<XFile> images = await ImagePicker().pickMultiImage(
        imageQuality: 90,
      );

      if (images.isNotEmpty) {
        int added = 0;
        for (var image in images) {
          if (_selectedImages.length < _maxImages) {
            _selectedImages.add(File(image.path));
            added++;
          }
        }
        setState(() {});
        _showSnackBar('$added Photo(s) Added Successfully', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Failed to pick images: $e', Colors.red);
    }
  }

  Future<void> _saveEmbeddingsToFirestore(String personId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final embeddings = InsightFacePipeline.getStoredEmbeddings();
      if (embeddings.containsKey(personId)) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('face_embeddings')
            .doc(personId)
            .set({
              'name': personId,
              'embeddings': embeddings[personId],
              'image_count': (embeddings[personId] as List).length,
              'created_at': FieldValue.serverTimestamp(),
              'updated_at': FieldValue.serverTimestamp(),
            });
      }
    } catch (e) {
      print('Error saving embeddings: $e');
    }
  }

  Future<void> _addPerson() async {
    if (_nameController.text.trim().isEmpty) {
      _showSnackBar('Please enter a name', Colors.red);
      return;
    }

    if (_selectedImages.length < _minImages) {
      _showSnackBar('Please add at least $_minImages photo', Colors.red);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_isProcessing) return;

    setState(() {
      _isUploading = true;
      _isProcessing = true;
    });

    try {
      final personName = _nameController.text.trim();
      List<String> photoUrls = [];
      int successCount = 0;
      int failedCount = 0;
      List<String> failReasons = [];

      print('Processing ${_selectedImages.length} images for $personName');

      for (int i = 0; i < _selectedImages.length; i++) {
        try {
          print('Processing image ${i + 1}/${_selectedImages.length}');

          final faceRect = await InsightFacePipeline.detectFace(
            _selectedImages[i],
          );

          if (faceRect == null) {
            failedCount++;
            failReasons.add('Image ${i + 1}: No face detected');
            print('Image $i: No face detected');
            continue;
          }

          print(
            'Image $i: Face detected at ${faceRect.width.toInt()}x${faceRect.height.toInt()}',
          );

          final croppedFace = await InsightFacePipeline.cropFace(
            _selectedImages[i],
            faceRect,
          );

          if (croppedFace == null) {
            failedCount++;
            failReasons.add('Image ${i + 1}: Failed to crop face');
            print('Image $i: Failed to crop face');
            continue;
          }

          final tempDir = await Directory.systemTemp.createTemp();
          final tempFile = File('${tempDir.path}/face_$i.jpg');
          final jpg = img.encodeJpg(croppedFace);
          await tempFile.writeAsBytes(jpg);

          print('Image $i: Saved cropped face to temp file');

          final success = await InsightFacePipeline.storeFaceEmbedding(
            personName,
            tempFile,
          );

          if (success) {
            successCount++;
            print('Image $i: Embedding stored successfully');

            try {
              final storageRef = FirebaseStorage.instance
                  .ref()
                  .child('users')
                  .child(user.uid)
                  .child('faces')
                  .child(personName)
                  .child('${DateTime.now().millisecondsSinceEpoch}_$i.jpg');

              final uploadTask = await storageRef.putFile(tempFile);
              final photoUrl = await uploadTask.ref.getDownloadURL();
              photoUrls.add(photoUrl);
              print('Image $i: Uploaded to Firebase Storage');
            } catch (e) {
              print('Image $i: Failed to upload to storage: $e');
            }
          } else {
            failedCount++;
            failReasons.add('Image ${i + 1}: Failed to extract face features');
            print('Image $i: Failed to extract embedding');
          }

          try {
            await tempFile.delete();
            await tempDir.delete();
          } catch (e) {
            print('Cleanup error: $e');
          }
        } catch (e, stackTrace) {
          print('Error processing image $i: $e');
          print('Stack trace: $stackTrace');
          failedCount++;
          failReasons.add('Image ${i + 1}: Processing error');
        }
      }

      print('Results: Success=$successCount, Failed=$failedCount');

      if (successCount > 0) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('people')
            .add({
              'name': personName,
              'photoUrls': photoUrls,
              'photoCount': photoUrls.length,
              'embeddingCount': successCount,
              'faceDetected': true,
              'createdAt': FieldValue.serverTimestamp(),
            });

        await _saveEmbeddingsToFirestore(personName);

        if (mounted) {
          //  Show success message with green snackbar
          _showSnackBar(
            'Person $personName added successfully with $successCount photo${successCount > 1 ? 's' : ''}',
            Colors.green,
          );

          //  Speak the success message BEFORE navigating back
          await _speak(
            'Person $personName added successfully with $successCount photo${successCount > 1 ? 's' : ''}',
          );

          //  Wait a bit for the speech to complete before navigating
          await Future.delayed(const Duration(milliseconds: 5000));

          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          String errorMsg = 'Failed to process any images with faces.\n\n';
          if (failReasons.isNotEmpty) {
            errorMsg += 'Issues found:\n${failReasons.take(3).join('\n')}';
            if (failReasons.length > 3) {
              errorMsg += '\n... and ${failReasons.length - 3} more';
            }
          }
          errorMsg +=
              '\n\nTips:\n• Use well-lit photos\n• Face should be clearly visible\n• Avoid blurry images';

          _showDetailedErrorDialog(errorMsg);
        }
      }
    } catch (e, stackTrace) {
      print('Error in _addPerson: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        _showSnackBar('Error adding person: $e', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _isProcessing = false;
        });
      }
    }
  }

  void _showDetailedErrorDialog(String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: double.infinity,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Processing Failed',
                      style: TextStyle(
                        color: deepPurple,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 14,
                        color: deepPurple.withOpacity(0.8),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          _hapticFeedback();
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: deepPurple,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Try Again',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ultraLightPurple,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ultraLightPurple,
                  palePurple.withOpacity(0.3),
                  Colors.white,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildForm()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(25, 50, 25, 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.9),
            Colors.white.withOpacity(0.7),
            const Color.fromARGB(198, 255, 255, 255),
            const Color.fromARGB(195, 240, 224, 245),
          ],
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              _hapticFeedback();
              _speak('Going back');
              Navigator.pop(context);
            },
            child: Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [vibrantPurple, primaryPurple],
                ),
                borderRadius: BorderRadius.all(Radius.circular(18)),
                boxShadow: [
                  BoxShadow(
                    color: Color.fromARGB(76, 142, 58, 149),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Add New Person',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w900,
                foreground: Paint()
                  ..shader = const LinearGradient(
                    colors: [deepPurple, vibrantPurple],
                  ).createShader(const Rect.fromLTWH(0, 0, 200, 70)),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: deepPurple.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name Field
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: vibrantPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.badge_outlined,
                        color: vibrantPurple,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Name",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: deepPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: ultraLightPurple.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: vibrantPurple.withOpacity(0.5),
                      width: 1.5,
                    ),
                  ),
                  child: TextField(
                    controller: _nameController,
                    enabled: !_isUploading,
                    decoration: InputDecoration(
                      hintText: "Enter name",
                      hintStyle: TextStyle(
                        color: const Color.fromARGB(255, 79, 79, 79),
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: vibrantPurple,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // Photo Section Label
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: vibrantPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: vibrantPurple,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Photo",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: deepPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Upload Photo Container
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: _selectedImages.isNotEmpty
                        ? vibrantPurple.withOpacity(0.15)
                        : ultraLightPurple.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _selectedImages.isNotEmpty
                          ? vibrantPurple
                          : vibrantPurple.withOpacity(0.4),
                      width: 2,
                    ),
                  ),
                  child: InkWell(
                    onTap: _isUploading || _isProcessing ? null : _pickImages,
                    borderRadius: BorderRadius.circular(12),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _selectedImages.isNotEmpty
                                ? Icons.check_circle_outline
                                : Icons.cloud_upload_outlined,
                            size: 45,
                            color: _selectedImages.isNotEmpty
                                ? vibrantPurple
                                : vibrantPurple.withOpacity(0.7),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _selectedImages.isNotEmpty
                                ? '${_selectedImages.length} photo${_selectedImages.length > 1 ? 's' : ''} uploaded'
                                : 'Click here to upload photos',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: deepPurple,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedImages.isNotEmpty
                                ? 'Click to change photos'
                                : 'JPG or PNG',
                            style: TextStyle(fontSize: 13, color: deepPurple),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 25),
              ],
            ),
          ),

          // زر الإضافة خارج الكارد
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed:
                  _isUploading ||
                      _isProcessing ||
                      _nameController.text.trim().isEmpty ||
                      _selectedImages.length < _minImages
                  ? null
                  : _addPerson,
              icon: _isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(
                      Icons.person_add_rounded,
                      size: 24,
                      color: Colors.white,
                    ),
              label: Text(
                _isUploading
                    ? 'Processing ${_selectedImages.length} photo${_selectedImages.length > 1 ? 's' : ''}...'
                    : "Add New Person",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: vibrantPurple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                disabledBackgroundColor: Colors.grey.shade300,
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
