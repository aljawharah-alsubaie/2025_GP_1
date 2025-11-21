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

// 👇 نفس الصفحات المستخدمة في الفوتر
import 'home_page.dart';
import 'reminders.dart';
import 'contact_info_page.dart';
import 'settings.dart';
import './sos_screen.dart';

class AddPersonPage extends StatefulWidget {
  const AddPersonPage({super.key});

  @override
  State<AddPersonPage> createState() => _AddPersonPageState();
}

class _AddPersonPageState extends State<AddPersonPage> {
  final TextEditingController _nameController = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  final FocusNode _nameFocusNode = FocusNode();

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

    // 🗣️ يتكلم أول ما حقل الاسم ياخذ فوكس
    _nameFocusNode.addListener(() {
      if (_nameFocusNode.hasFocus) {
        _speak('Name field, enter the person name');
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    // عشان ما تتراكب الأصوات
    await _tts.stop();
    await _tts.speak(text);
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  Future<void> _pickImages() async {
    if (_selectedImages.length >= _maxImages) {
      _showSnackBar('Maximum $_maxImages photos allowed', Colors.orange);
      _speak('Maximum $_maxImages photos allowed');
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

        if (added > 0) {
          _showSnackBar('$added Photo(s) Added Successfully', Colors.green);

          // 🗣️ يتكلم بعد إضافة الصور
          final plural = added > 1 ? 'photos' : 'photo';
          _speak('$added $plural added successfully');
        }
      }
    } catch (e) {
      _showSnackBar('Failed to pick images: $e', Colors.red);
      _speak('Failed to pick images');
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
      _speak('Please enter a name');
      return;
    }

    if (_selectedImages.length < _minImages) {
      _showSnackBar('Please add at least $_minImages photo', Colors.red);
      _speak('Please add at least one photo');
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
          _showSnackBar(
            'Person $personName added successfully with $successCount photo${successCount > 1 ? 's' : ''}',
            Colors.green,
          );

          await _speak(
            'Person $personName added successfully with $successCount photo${successCount > 1 ? 's' : ''}',
          );

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
          _speak(
            'Failed to process images. Please review the tips and try again.',
          );
        }
      }
    } catch (e, stackTrace) {
      print('Error in _addPerson: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        _showSnackBar('Error adding person: $e', Colors.red);
        _speak('Error adding person, please try again');
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

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          elevation: 14,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          duration: const Duration(seconds: 2),
          content: SizedBox(
            height: 40,
            child: Row(
              children: [
                Icon(
                  color == Colors.green
                      ? Icons.check_circle
                      : Icons.error_outline,
                  color: Colors.white,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
      bottomNavigationBar: _buildFloatingBottomNav(),
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
          Semantics(
            label: 'Go back to previous page',
            button: true,
            child: GestureDetector(
              onTap: () {
                _speak('Going back');
                Future.delayed(const Duration(milliseconds: 800), () {
                  Navigator.pop(context);
                });
              },
              child: Container(
                width: 53,
                height: 53,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [vibrantPurple, primaryPurple],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: vibrantPurple.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Add New Person',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w900,
                foreground: Paint()
                  ..shader = const LinearGradient(
                    colors: [deepPurple, vibrantPurple],
                  ).createShader(const Rect.fromLTWH(0, 0, 240, 80)),
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
              borderRadius: BorderRadius.circular(27),
              boxShadow: [
                BoxShadow(
                  color: deepPurple.withOpacity(0.13),
                  blurRadius: 25,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name Field
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9.5),
                      decoration: BoxDecoration(
                        color: vibrantPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.badge_outlined,
                        color: vibrantPurple,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 9),
                    const Text(
                      "Name",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 19.5,
                        color: deepPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                Container(
                  decoration: BoxDecoration(
                    color: ultraLightPurple.withOpacity(0.38),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: vibrantPurple.withOpacity(0.58),
                      width: 1.7,
                    ),
                  ),
                  child: TextField(
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    enabled: !_isUploading,
                    style: const TextStyle(
                      fontSize: 17.5,
                      color: deepPurple,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: "Enter name",
                      hintStyle: const TextStyle(
                        color: Color.fromARGB(255, 79, 79, 79),
                        fontSize: 16.5,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(17),
                        borderSide: const BorderSide(
                          color: vibrantPurple,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 19,
                        vertical: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 33),

                // Photo Section Label
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9.5),
                      decoration: BoxDecoration(
                        color: vibrantPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: vibrantPurple,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 9),
                    const Text(
                      "Photo",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 19.5,
                        color: deepPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // Upload Photo Container
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: _selectedImages.isNotEmpty
                        ? vibrantPurple.withOpacity(0.15)
                        : ultraLightPurple.withOpacity(0.38),
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(
                      color: _selectedImages.isNotEmpty
                          ? vibrantPurple
                          : vibrantPurple.withOpacity(0.4),
                      width: 2,
                    ),
                  ),
                  child: InkWell(
                    onTap: _isUploading || _isProcessing
                        ? null
                        : () {
                            _speak(
                              'Photo section, tap to upload one or more face photos',
                            );
                            _pickImages();
                          },
                    borderRadius: BorderRadius.circular(15),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _selectedImages.isNotEmpty
                                ? Icons.check_circle_outline
                                : Icons.cloud_upload_outlined,
                            size: 52,
                            color: _selectedImages.isNotEmpty
                                ? vibrantPurple
                                : vibrantPurple.withOpacity(0.7),
                          ),
                          const SizedBox(height: 11),
                          Text(
                            _selectedImages.isNotEmpty
                                ? '${_selectedImages.length} photo${_selectedImages.length > 1 ? 's' : ''} uploaded'
                                : 'Click here to upload photos',
                            style: const TextStyle(
                              fontSize: 17.5,
                              fontWeight: FontWeight.w600,
                              color: deepPurple,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _selectedImages.isNotEmpty
                                ? 'Click to change photos'
                                : 'JPG or PNG',
                            style: const TextStyle(
                              fontSize: 14.5,
                              color: deepPurple,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 29),
              ],
            ),
          ),

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 66,
            child: ElevatedButton.icon(
              onPressed:
                  _isUploading ||
                      _isProcessing ||
                      _nameController.text.trim().isEmpty ||
                      _selectedImages.length < _minImages
                  ? null
                  : () {
                      // 🗣️ لما يضغط على زر الإضافة
                      _hapticFeedback();
                      _speak(
                        'Add new person button, processing photos. Please wait.',
                      );
                      _addPerson();
                    },
              icon: _isUploading
                  ? const SizedBox(
                      width: 23,
                      height: 23,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(
                      Icons.person_add_rounded,
                      size: 27,
                      color: Colors.white,
                    ),
              label: Text(
                _isUploading
                    ? 'Processing ${_selectedImages.length} photo${_selectedImages.length > 1 ? 's' : ''}...'
                    : "Add New Person",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: vibrantPurple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
                disabledBackgroundColor: Colors.grey.shade300,
                elevation: 3.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🔻 نفس الفوتر حق FaceManagementPage بالضبط
  Widget _buildFloatingBottomNav() {
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          child: Container(
            height: 95,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  deepPurple.withOpacity(0.95),
                  vibrantPurple.withOpacity(0.98),
                  primaryPurple,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: deepPurple.withOpacity(0.3),
                  blurRadius: 25,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildNavButton(
                      icon: Icons.home_rounded,
                      label: 'Home',
                      isActive: false,
                      description: 'Navigate to Homepage',
                      onTap: () {
                        _hapticFeedback();
                        _speak('Navigate to Homepage');
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HomePage(),
                          ),
                        );
                      },
                    ),
                    _buildNavButton(
                      icon: Icons.notifications_rounded,
                      label: 'Reminders',
                      description: 'Manage your reminders and notifications',
                      isActive: false,
                      onTap: () {
                        _speak(
                          'Reminders, Create and manage reminders, and the app will notify you at the right time',
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RemindersPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 60),
                    _buildNavButton(
                      icon: Icons.contacts_rounded,
                      label: 'Contacts',
                      description:
                          'Manage your emergency contacts and important people',
                      isActive: false,
                      onTap: () {
                        _speak('Contacts, Store and manage emergency contacts');
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ContactInfoPage(),
                          ),
                        );
                      },
                    ),
                    _buildNavButton(
                      icon: Icons.settings_rounded,
                      label: 'Settings',
                      description: 'Adjust app settings and preferences',
                      isActive: false,
                      onTap: () {
                        _speak(
                          'Settings, Manage your settings and preferences',
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        Positioned(
          bottom: 40,
          child: GestureDetector(
            onTap: () {
              _hapticFeedback();
              _speak(
                'Emergency SOS, Sends an emergency alert to your trusted contacts when you need help',
              );
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SosScreen()),
              );
            },
            child: Container(
              width: 75,
              height: 75,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.red.shade400, Colors.red.shade700],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.6),
                    blurRadius: 25,
                    spreadRadius: 5,
                  ),
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 40,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: const Icon(
                Icons.emergency_outlined,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String label,
    required String description,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: '$label button',
      button: true,
      selected: isActive,
      hint: description,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white.withOpacity(0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isActive
                ? Border.all(color: Colors.white.withOpacity(0.3), width: 1.5)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive
                    ? Colors.white
                    : const Color.fromARGB(255, 255, 253, 253).withOpacity(0.9),
                size: 25,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withOpacity(0.9),
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
