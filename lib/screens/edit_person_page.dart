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

class EditPersonPage extends StatefulWidget {
  final Map<String, dynamic> person;

  const EditPersonPage({super.key, required this.person});

  @override
  State<EditPersonPage> createState() => _EditPersonPageState();
}

class _EditPersonPageState extends State<EditPersonPage> {
  final TextEditingController _nameController = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  List<File> _newImages = [];
  final int _maxImages = 10;
  bool _isUploading = false;
  bool _isProcessing = false;

  // 🎨 Purple color scheme
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
    try {
      final List<XFile> images = await ImagePicker().pickMultiImage(
        imageQuality: 90,
      );

      if (images.isNotEmpty) {
        int added = 0;
        for (var image in images) {
          if (_newImages.length < _maxImages) {
            _newImages.add(File(image.path));
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

  Future<void> _saveChanges() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_isProcessing) return;

    final newName = _nameController.text.trim();
    bool nameChanged = newName != widget.person['name'];
    bool hasNewPhotos = _newImages.isNotEmpty;

    // تحقق إذا ما فيه أي تغيير
    if (!nameChanged && !hasNewPhotos) {
      _showSnackBar('No changes made!', Colors.orange);
      await _speak('No changes made');
      return;
    }

    setState(() {
      _isUploading = true;
      _isProcessing = true;
    });

    try {
      final personName = nameChanged ? newName : widget.person['name'];

      // تحديث الاسم إذا تغير
      if (nameChanged) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('people')
            .doc(widget.person['id'])
            .update({'name': newName});

        // Update embeddings with new name
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

      // إضافة/استبدال الصور الجديدة
      int successCount = 0;
      List<String> newPhotoUrls = [];

      if (hasNewPhotos) {
        // حذف الصور القديمة من Storage
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
          // حذف embeddings القديمة
          InsightFacePipeline.removeFaceEmbedding(personName);

          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('face_embeddings')
              .doc(personName)
              .delete();

          // تحديث الصور في Firestore
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

          // حفظ embeddings الجديدة
          await _saveEmbeddingsToFirestore(personName);
          await _loadStoredEmbeddings();

          // ✅ تحديث البيانات المحلية
          widget.person['photoUrls'] = newPhotoUrls;
          widget.person['photoCount'] = newPhotoUrls.length;
        }
      }

      if (mounted) {
        String message = '';
        if (nameChanged && hasNewPhotos && successCount > 0) {
          message =
              'Name updated and replaced with $successCount photo${successCount > 1 ? 's' : ''} successfully';
        } else if (nameChanged) {
          message = 'Name updated successfully to $newName';
        } else if (hasNewPhotos && successCount > 0) {
          message =
              'Replaced with $successCount photo${successCount > 1 ? 's' : ''} successfully';
        }

        if (message.isNotEmpty) {
          _showSnackBar(message, Colors.green);
          await _speak(message);
          await Future.delayed(const Duration(milliseconds: 2000));

          // ✅ تحديث الاسم المحلي
          if (nameChanged) {
            widget.person['name'] = newName;
          }

          setState(() {
            _newImages.clear();
          });

          // ✅ إرجاع true للإشارة بأن في تحديث
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      print('Error saving changes: $e');
      if (mounted) {
        _showSnackBar('Error saving changes: $e', Colors.red);
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
              'Edit Person',
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
                const SizedBox(height: 5),
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
                    enabled: !_isProcessing && !_isUploading,
                    decoration: InputDecoration(
                      hintText: "Enter person's name",
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
                    onChanged: (value) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 30),
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
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: _newImages.isNotEmpty
                        ? vibrantPurple.withOpacity(0.15)
                        : ultraLightPurple.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _newImages.isNotEmpty
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
                            _newImages.isNotEmpty
                                ? Icons.check_circle_outline
                                : Icons.cloud_upload_outlined,
                            size: 45,
                            color: _newImages.isNotEmpty
                                ? vibrantPurple
                                : vibrantPurple.withOpacity(0.7),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _newImages.isNotEmpty
                                ? '${_newImages.length} photo${_newImages.length > 1 ? 's' : ''} selected'
                                : 'Click to select new photos',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: deepPurple,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _newImages.isNotEmpty
                                ? 'Will replace existing photos'
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
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed:
                  _isUploading ||
                      _isProcessing ||
                      _nameController.text.trim().isEmpty
                  ? null
                  : _saveChanges,
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
                      Icons.check_circle_rounded,
                      size: 24,
                      color: Colors.white,
                    ),
              label: Text(
                _isUploading ? 'Processing...' : "Save Changes",
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
