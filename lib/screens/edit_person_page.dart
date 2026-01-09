import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../services/insightface_pipeline.dart';
import 'face_rotation_capture_screen.dart';
import 'home_page.dart';
import 'reminders.dart';
import 'contact_info_page.dart';
import 'settings.dart';
import './sos_screen.dart';

class EditPersonPage extends StatefulWidget {
  final Map<String, dynamic> person;

  const EditPersonPage({super.key, required this.person});

  @override
  State<EditPersonPage> createState() => _EditPersonPageState();
}

class _EditPersonPageState extends State<EditPersonPage> {
  final TextEditingController _nameController = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  final FocusNode _nameFocusNode = FocusNode();

  List<File> _newImages = [];
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
    _nameController.text = widget.person['name'] ?? '';
    _initTts();

    _nameFocusNode.addListener(() {
      if (_nameFocusNode.hasFocus) {
        final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
        _speak(languageProvider.isArabic
            ? 'حقل الاسم، عدّل اسم الشخص'
            : 'Name field, edit the person name');
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
    final languageCode = Provider.of<LanguageProvider>(context, listen: false).languageCode;
    await _tts.setLanguage(languageCode == 'ar' ? 'ar-SA' : 'en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  Future<void> _pickImages() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    try {
      _speak(languageProvider.isArabic
          ? 'فتح الكاميرا لالتقاط دوران الوجه'
          : 'Opening camera for face rotation capture');
      
      final List<File>? capturedImages = await Navigator.push<List<File>>(
        context,
        MaterialPageRoute(
          builder: (context) => const FaceRotationCaptureScreen(),
        ),
      );

      if (capturedImages != null && capturedImages.isNotEmpty) {
        setState(() {
          _newImages = capturedImages;
        });

        _showSnackBar(
          languageProvider.isArabic
              ? 'تم التقاط ${capturedImages.length} صور دوران بنجاح'
              : '${capturedImages.length} rotation photos captured successfully',
          Colors.green,
        );
        
        _speak(
          languageProvider.isArabic
              ? 'تم التقاط ${capturedImages.length} صور بنجاح. هذه الصور ستستبدل الصور الموجودة'
              : '${capturedImages.length} photos captured successfully. These photos will replace the existing ones.',
        );
      }
    } catch (e) {
      _showSnackBar(
        languageProvider.isArabic
            ? 'فشل التقاط الصور: $e'
            : 'Failed to capture images: $e',
        Colors.red,
      );
      _speak(languageProvider.isArabic
          ? 'فشل التقاط الصور، حاول مرة أخرى'
          : 'Failed to capture images, please try again.');
    }
  }

  Future<void> _saveChanges() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_isProcessing) return;

    final newName = _nameController.text.trim();
    bool nameChanged = newName != widget.person['name'];
    bool hasNewPhotos = _newImages.isNotEmpty;

    setState(() {
      _isUploading = true;
      _isProcessing = true;
    });

    try {
      final personName = nameChanged ? newName : widget.person['name'];

      if (nameChanged) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('people')
            .doc(widget.person['id'])
            .update({'name': newName});

        final oldEmbeddings = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('face_embeddings')
            .doc(widget.person['name'])
            .get();

        if (oldEmbeddings.exists) {
          final data = oldEmbeddings.data();
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('face_embeddings')
              .doc(newName)
              .set(data!);

          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('face_embeddings')
              .doc(widget.person['name'])
              .delete();
        }

        InsightFacePipeline.removeFaceEmbedding(widget.person['name']);
        await _loadStoredEmbeddings();
      }

      int successCount = 0;
      List<String> newPhotoUrls = [];

      if (hasNewPhotos) {
        List<String> existingUrls = List<String>.from(
          widget.person['photoUrls'] ?? [],
        );

        for (String oldUrl in existingUrls) {
          try {
            final ref = FirebaseStorage.instance.refFromURL(oldUrl);
            await ref.delete();
            print('Deleted old photo from storage');
          } catch (e) {
            print('Failed to delete old photo: $e');
          }
        }

        print('Replacing with ${_newImages.length} new images for $personName');

        for (int i = 0; i < _newImages.length; i++) {
          try {
            final faceRect = await InsightFacePipeline.detectFace(
              _newImages[i],
            );
            if (faceRect == null) continue;

            final croppedFace = await InsightFacePipeline.cropFace(
              _newImages[i],
              faceRect,
            );
            if (croppedFace == null) continue;

            final tempDir = await Directory.systemTemp.createTemp();
            final tempFile = File('${tempDir.path}/face_$i.jpg');
            final jpg = img.encodeJpg(croppedFace);
            await tempFile.writeAsBytes(jpg);

            final success = await InsightFacePipeline.storeFaceEmbedding(
              personName,
              tempFile,
            );

            if (success) {
              successCount++;
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
                newPhotoUrls.add(photoUrl);
              } catch (e) {
                print('Failed to upload: $e');
              }
            }

            try {
              await tempFile.delete();
              await tempDir.delete();
            } catch (e) {
              print('Cleanup error: $e');
            }
          } catch (e) {
            print('Error processing image $i: $e');
          }
        }

        if (successCount > 0) {
          InsightFacePipeline.removeFaceEmbedding(personName);

          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('face_embeddings')
              .doc(personName)
              .delete();

          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('people')
              .doc(widget.person['id'])
              .update({
                'photoUrls': newPhotoUrls,
                'photoCount': newPhotoUrls.length,
                'embeddingCount': successCount,
              });

          await _saveEmbeddingsToFirestore(personName);
          await _loadStoredEmbeddings();

          widget.person['photoUrls'] = newPhotoUrls;
          widget.person['photoCount'] = newPhotoUrls.length;
        }
      }

      if (mounted) {
        String message = '';
        if (nameChanged && hasNewPhotos && successCount > 0) {
          message = languageProvider.isArabic
              ? 'تم تحديث الاسم واستبدال $successCount ${successCount > 1 ? 'صور' : 'صورة'} بنجاح'
              : 'Name updated and replaced with $successCount photo${successCount > 1 ? 's' : ''} successfully';
        } else if (nameChanged && !hasNewPhotos) {
          message = languageProvider.isArabic
              ? 'تم تحديث الاسم بنجاح إلى $newName'
              : 'Name updated successfully to $newName';
        } else if (!nameChanged && hasNewPhotos && successCount > 0) {
          message = languageProvider.isArabic
              ? 'تم الاستبدال بـ $successCount ${successCount > 1 ? 'صور' : 'صورة'} بنجاح'
              : 'Replaced with $successCount photo${successCount > 1 ? 's' : ''} successfully';
        }

        if (message.isNotEmpty) {
          _showSnackBar(message, Colors.green);
          await _speak(message);
          await Future.delayed(const Duration(milliseconds: 2000));

          if (nameChanged) {
            widget.person['name'] = newName;
          }

          setState(() {
            _newImages.clear();
          });

          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      print('Error saving changes: $e');
      if (mounted) {
        _showSnackBar(
          languageProvider.isArabic
              ? 'خطأ في حفظ التغييرات: $e'
              : 'Error saving changes: $e',
          Colors.red,
        );
        _speak(languageProvider.isArabic
            ? 'خطأ في حفظ التغييرات، حاول مرة أخرى'
            : 'Error saving changes, please try again.');
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

  Future<void> _loadStoredEmbeddings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('face_embeddings')
          .get();

      if (snapshot.docs.isNotEmpty) {
        Map<String, List<List<double>>> allEmbeddings = {};

        for (var doc in snapshot.docs) {
          final data = doc.data();
          if (data['embeddings'] != null) {
            List<List<double>> personEmbeddings = (data['embeddings'] as List)
                .map(
                  (e) => (e as List).map((v) => (v as num).toDouble()).toList(),
                )
                .toList();
            allEmbeddings[doc.id] = personEmbeddings;
          }
        }

        InsightFacePipeline.loadMultipleEmbeddings(allEmbeddings);
      }
    } catch (e) {
      print('Error loading embeddings: $e');
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
              'updated_at': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }
    } catch (e) {
      print('Error saving embeddings: $e');
    }
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
    final languageProvider = Provider.of<LanguageProvider>(context);
    
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
                _speak(languageProvider.isArabic ? 'العودة' : 'Going back');
                Future.delayed(const Duration(milliseconds: 800), () {
                  Navigator.pop(context);
                });
              },
              child: Container(
                width: 52,
                height: 52,
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
                child: Center(
                  child: Icon(
                    languageProvider.isArabic
                        ? Icons.arrow_forward_ios
                        : Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              languageProvider.isArabic ? 'تعديل الشخص' : 'Edit Person',
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
    final languageProvider = Provider.of<LanguageProvider>(context);
    final String originalName = widget.person['name'] ?? '';
    final bool hasChanges =
        _nameController.text.trim() != originalName || _newImages.isNotEmpty;

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
                    Text(
                      languageProvider.isArabic ? 'الاسم' : "Name",
                      style: const TextStyle(
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
                    enabled: !_isUploading && !_isProcessing,
                    style: const TextStyle(
                      fontSize: 17.5,
                      color: deepPurple,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: languageProvider.isArabic ? 'ادخل الاسم' : "Enter name",
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
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 33),

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
                    Text(
                      languageProvider.isArabic ? 'الصورة' : "Photo",
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 19.5,
                        color: deepPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: _newImages.isNotEmpty
                        ? vibrantPurple.withOpacity(0.15)
                        : ultraLightPurple.withOpacity(0.38),
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(
                      color: _newImages.isNotEmpty
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
                              languageProvider.isArabic
                                  ? 'قسم الصورة. اضغط لبدء التقاط دوران الوجه. الكاميرا ستوجهك لالتقاط 5 صور من زوايا مختلفة. هذه الصور ستستبدل الصور الموجودة'
                                  : 'Photo section. Tap to start face rotation capture. The camera will guide you to take 5 photos from different angles. These photos will replace the existing ones.',
                            );
                            _pickImages();
                          },
                    borderRadius: BorderRadius.circular(15),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _newImages.isNotEmpty
                                ? Icons.check_circle_outline
                                : Icons.camera_alt_outlined,
                            size: 52,
                            color: _newImages.isNotEmpty
                                ? vibrantPurple
                                : vibrantPurple.withOpacity(0.7),
                          ),
                          const SizedBox(height: 11),
                          Text(
                            _newImages.isNotEmpty
                                ? (languageProvider.isArabic
                                    ? 'تم التقاط ${_newImages.length} صور دوران'
                                    : '${_newImages.length} rotation photos captured')
                                : (languageProvider.isArabic
                                    ? 'اضغط لالتقاط دوران الوجه'
                                    : 'Tap to capture face rotation'),
                            style: const TextStyle(
                              fontSize: 17.5,
                              fontWeight: FontWeight.w600,
                              color: deepPurple,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _newImages.isNotEmpty
                                ? (languageProvider.isArabic
                                    ? 'ستستبدل الصور الموجودة'
                                    : 'Will replace existing photos')
                                : (languageProvider.isArabic
                                    ? 'أمام، يسار، يمين، أعلى، أسفل'
                                    : 'Front, Left, Right, Up, Down'),
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
                      !hasChanges
                  ? null
                  : () {
                      _hapticFeedback();
                      _speak(
                        languageProvider.isArabic
                            ? 'زر حفظ التغييرات، جاري حفظ التحديثات، انتظر من فضلك'
                            : 'Save changes button, saving your updates, please wait.',
                      );
                      _saveChanges();
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
                      Icons.check_circle_rounded,
                      size: 27,
                      color: Colors.white,
                    ),
              label: Text(
                languageProvider.isArabic ? 'حفظ التغييرات' : "Save Changes",
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

  Widget _buildFloatingBottomNav() {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
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
                      label: languageProvider.isArabic ? 'الرئيسية' : 'Home',
                      isActive: false,
                      description: 'Navigate to Homepage',
                      onTap: () {
                        _hapticFeedback();
                        _speak(languageProvider.isArabic
                            ? 'الانتقال للصفحة الرئيسية'
                            : 'Navigate to Homepage');
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
                      label: languageProvider.isArabic ? 'التذكيرات' : 'Reminders',
                      description: 'Manage your reminders and notifications',
                      isActive: false,
                      onTap: () {
                        _speak(
                          languageProvider.isArabic
                              ? 'التذكيرات، أنشئ وأدر التذكيرات، وسيخطرك التطبيق في الوقت المناسب'
                              : 'Reminders, Create and manage reminders, and the app will notify you at the right time',
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
                      label: languageProvider.isArabic ? 'جهات الاتصال' : 'Contacts',
                      description:
                          'Manage your emergency contacts and important people',
                      isActive: false,
                      onTap: () {
                        _speak(languageProvider.isArabic
                            ? 'جهات الاتصال، تخزين وإدارة جهات اتصال الطوارئ'
                            : 'Contact, Store and manage emergency contacts');
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
                      label: languageProvider.isArabic ? 'الإعدادات' : 'Settings',
                      description: 'Adjust app settings and preferences',
                      isActive: false,
                      onTap: () {
                        _speak(
                          languageProvider.isArabic
                              ? 'الإعدادات، إدارة الإعدادات والتفضيلات'
                              : 'Settings, Manage your settings and preferences',
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
                languageProvider.isArabic
                    ? 'طوارئ، إرسال تنبيه طوارئ لجهات الاتصال الموثوقة عندما تحتاج المساعدة'
                    : 'Emergency SOS, Sends an emergency alert to your trusted contacts when you need help',
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