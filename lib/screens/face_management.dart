import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_tts/flutter_tts.dart';
import '../services/face_recognition_service.dart';
import 'home_page.dart';
import 'reminders.dart';
import 'contact_info_page.dart';
import 'settings.dart';

class FaceManagementPage extends StatefulWidget {
  const FaceManagementPage({super.key});

  @override
  State<FaceManagementPage> createState() => _FaceManagementPageState();
}

class _FaceManagementPageState extends State<FaceManagementPage>
    with TickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  List<Map<String, dynamic>> _people = [];
  bool _isLoading = true;
  bool _isUploading = false;
  bool _isProcessing = false;
  String _searchQuery = '';

  AnimationController? _fadeController;
  AnimationController? _slideController;

  List<File> _selectedImages = [];
  final int _minImages = 3;
  final int _maxImages = 10;

  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color lightPurple = Color.fromARGB(255, 217, 163, 227);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);

  @override
  void initState() {
    super.initState();
    _initTts();
    _initializeFaceRecognition();
    _loadPeople();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    _tts.stop();
    _fadeController?.dispose();
    _slideController?.dispose();
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

  Future<void> _initializeFaceRecognition() async {
    final success = await FaceRecognitionService.initialize();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to initialize face recognition'),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      await _loadStoredEmbeddings();
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

        FaceRecognitionService.loadMultipleEmbeddings(allEmbeddings);
        print('Loaded embeddings for ${allEmbeddings.length} persons');
      }
    } catch (e) {
      print('Error loading embeddings: $e');
    }
  }

  Future<void> _saveEmbeddingsToFirestore(String personId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final embeddings = FaceRecognitionService.getStoredEmbeddings();
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

  Future<void> _loadPeople() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('people')
          .orderBy('createdAt', descending: true)
          .get();

      setState(() {
        _people = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading people: $e')));
      }
    }
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
        _showSnackBar('Added $added photo(s)', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Failed to pick images: $e', Colors.red);
    }
  }

  Future<void> _pickSingleImage() async {
    if (_selectedImages.length >= _maxImages) {
      _showSnackBar('Maximum $_maxImages photos allowed', Colors.orange);
      return;
    }

    try {
      final XFile? image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );

      if (image != null) {
        setState(() {
          _selectedImages.add(File(image.path));
        });
      }
    } catch (e) {
      _showSnackBar('Failed to capture image: $e', Colors.red);
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<void> _addPerson() async {
    if (_nameController.text.trim().isEmpty) {
      _showSnackBar('Please enter a name', Colors.red);
      return;
    }

    if (_selectedImages.length < _minImages) {
      _showSnackBar('Please add at least $_minImages photos', Colors.red);
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

      for (int i = 0; i < _selectedImages.length; i++) {
        try {
          final faceRect = await FaceRecognitionService.detectFaceEnhanced(
            _selectedImages[i],
          );

          if (faceRect != null) {
            final croppedFace = await FaceRecognitionService.cropFaceEnhanced(
              _selectedImages[i],
              faceRect,
            );

            if (croppedFace != null) {
              final storageRef = FirebaseStorage.instance
                  .ref()
                  .child('users')
                  .child(user.uid)
                  .child('faces')
                  .child(personName)
                  .child('${DateTime.now().millisecondsSinceEpoch}_$i.jpg');

              final tempDir = await Directory.systemTemp.createTemp();
              final tempFile = File('${tempDir.path}/face_$i.jpg');

              final jpg = img.encodeJpg(croppedFace);
              await tempFile.writeAsBytes(jpg);

              final success = await FaceRecognitionService.storeFaceEmbedding(
                personName,
                tempFile,
                normalizationType: 'arcface',
              );

              if (success) {
                successCount++;

                final uploadTask = await storageRef.putFile(tempFile);
                final photoUrl = await uploadTask.ref.getDownloadURL();
                photoUrls.add(photoUrl);
              } else {
                failedCount++;
              }

              try {
                await tempFile.delete();
                await tempDir.delete();
              } catch (e) {
                print('Cleanup error: $e');
              }
            }
          } else {
            failedCount++;
          }
        } catch (e) {
          print('Error processing image $i: $e');
          failedCount++;
        }
      }

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
        await _loadPeople();

        if (mounted) {
          Navigator.pop(context);
          await Future.delayed(const Duration(milliseconds: 100));
          _resetForm();
          _showSuccessDialog(personName, successCount, failedCount);
        }
      } else {
        if (mounted) {
          _showSnackBar('Failed to process any images with faces', Colors.red);
        }
      }
    } catch (e) {
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

  void _showSuccessDialog(String personName, int success, int failed) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
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
                    color: Colors.green.shade50,
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
                          color: Colors.green.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 50,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Success!',
                        style: TextStyle(
                          color: deepPurple,
                          fontWeight: FontWeight.w800,
                          fontSize: 26,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        personName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: deepPurple,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Successful: $success photos',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green.shade800,
                                  ),
                                ),
                              ],
                            ),
                            if (failed > 0) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.warning,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Failed: $failed photos',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orange.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Face recognition trained successfully!',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                _hapticFeedback();
                                Navigator.pop(context);
                                _showAddDialog();
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                side: const BorderSide(
                                  color: vibrantPurple,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Add Another',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: vibrantPurple,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                _hapticFeedback();
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: deepPurple,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Done',
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
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _resetForm() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _selectedImages.clear();
          _nameController.clear();
          _isUploading = false;
          _isProcessing = false;
        });
      }
    });
  }

  Future<void> _updatePersonName(
    String personId,
    String oldName,
    String newName,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('people')
          .doc(personId)
          .update({'name': newName});

      final oldEmbeddings = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('face_embeddings')
          .doc(oldName)
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
            .doc(oldName)
            .delete();
      }

      FaceRecognitionService.removeFaceEmbedding(oldName);
      await _loadStoredEmbeddings();
      await _loadPeople();
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error updating name: $e', Colors.red);
      }
    }
  }

  Future<void> _deletePerson(String personId, String personName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('people')
          .doc(personId)
          .delete();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('face_embeddings')
          .doc(personName)
          .delete();

      FaceRecognitionService.removeFaceEmbedding(personName);

      await _loadPeople();

      if (mounted) {
        _showSnackBar('$personName deleted successfully!', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Error deleting person: $e', Colors.red);
    }
  }

  void _showEditDialog(Map<String, dynamic> person) {
    final nameController = TextEditingController(text: person['name']);
    bool isUploadingPhotos = false;
    bool photosChanged = false;

    final Color fieldBackground = vibrantPurple.withOpacity(0.08);
    final Color fieldBorder = vibrantPurple.withOpacity(0.35);
    final Color fieldFocus = vibrantPurple;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 820),
            padding: const EdgeInsets.all(28),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [vibrantPurple, primaryPurple],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Text(
                        "Edit Person",
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: deepPurple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Name",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: deepPurple,
                        fontSize: 18,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    enabled: !isUploadingPhotos,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: deepPurple,
                    ),
                    decoration: InputDecoration(
                      hintText: "Enter person's name",
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      filled: true,
                      fillColor: fieldBackground,
                      prefixIcon: Icon(
                        Icons.person,
                        color: vibrantPurple,
                        size: 24,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: fieldBorder, width: 1.3),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: fieldBorder, width: 1.3),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: fieldFocus, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Photo",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: deepPurple,
                        fontSize: 17,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: isUploadingPhotos
                        ? null
                        : () async {
                            _hapticFeedback();

                            try {
                              final picker = ImagePicker();
                              final List<XFile> picked = await picker
                                  .pickMultiImage(imageQuality: 100);

                              if (picked.isEmpty) return;

                              setDialogState(() {
                                isUploadingPhotos = true;
                              });

                              Future<Uint8List> compressImage(
                                Uint8List input,
                              ) async {
                                final decoded = img.decodeImage(input);
                                if (decoded == null) return input;

                                final int maxSide = 1024;
                                img.Image resized = decoded;
                                if (decoded.width > maxSide ||
                                    decoded.height > maxSide) {
                                  resized = img.copyResize(
                                    decoded,
                                    width: decoded.width >= decoded.height
                                        ? maxSide
                                        : null,
                                    height: decoded.height > decoded.width
                                        ? maxSide
                                        : null,
                                    interpolation: img.Interpolation.average,
                                  );
                                }
                                final jpg = img.encodeJpg(resized, quality: 85);
                                return Uint8List.fromList(jpg);
                              }

                              Future<String> uploadBytes(
                                Uint8List bytes,
                                String filename,
                              ) async {
                                final uid =
                                    FirebaseAuth.instance.currentUser!.uid;
                                final ref = FirebaseStorage.instance.ref().child(
                                  'users/$uid/faces/${person['name']}/$filename',
                                );

                                final task = await ref.putData(
                                  bytes,
                                  SettableMetadata(contentType: 'image/jpeg'),
                                );
                                return await task.ref.getDownloadURL();
                              }

                              final List<String> newUrls = [];
                              for (final xf in picked) {
                                final raw = await xf.readAsBytes();
                                final comp = await compressImage(raw);
                                final filename =
                                    'img_${DateTime.now().millisecondsSinceEpoch}_${newUrls.length}.jpg';
                                final url = await uploadBytes(comp, filename);
                                newUrls.add(url);
                              }

                              if (newUrls.isEmpty) {
                                setDialogState(() {
                                  isUploadingPhotos = false;
                                });
                                return;
                              }

                              final uid =
                                  FirebaseAuth.instance.currentUser!.uid;
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uid)
                                  .collection('people')
                                  .doc(person['id'])
                                  .update({
                                    'photoUrls': FieldValue.arrayUnion(newUrls),
                                    'photoCount': FieldValue.increment(
                                      newUrls.length,
                                    ),
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  });

                              if (context.mounted) {
                                setDialogState(() {
                                  final List<dynamic> currentUrls = List.from(
                                    person['photoUrls'] ?? [],
                                  );
                                  currentUrls.insertAll(0, newUrls);
                                  person['photoUrls'] = currentUrls;
                                  person['photoCount'] =
                                      (person['photoCount'] ?? 0) +
                                      newUrls.length;
                                  isUploadingPhotos = false;
                                  photosChanged = true;
                                });
                              }

                              await _loadPeople();

                              if (mounted) {
                                _showSnackBar(
                                  'Photos updated successfully ✅',
                                  Colors.green,
                                );
                              }
                            } catch (e) {
                              print('Error updating photos: $e');

                              if (context.mounted) {
                                setDialogState(() {
                                  isUploadingPhotos = false;
                                });
                              }

                              if (mounted) {
                                _showSnackBar(
                                  'Failed to update photos',
                                  Colors.red,
                                );
                              }
                            }
                          },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: fieldBackground,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: fieldBorder, width: 1.3),
                      ),
                      child: isUploadingPhotos
                          ? Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      vibrantPurple,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Uploading Photos...',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          color: deepPurple,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Please wait...',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: deepPurple.withOpacity(0.6),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Container(
                                  width: 66,
                                  height: 66,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        vibrantPurple.withOpacity(0.15),
                                        primaryPurple.withOpacity(0.15),
                                      ],
                                    ),
                                  ),
                                  child:
                                      (person['photoUrls'] != null &&
                                          (person['photoUrls'] as List)
                                              .isNotEmpty)
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            32.5,
                                          ),
                                          child: Image.network(
                                            person['photoUrls'][0],
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : Icon(
                                          Icons.person,
                                          color: vibrantPurple,
                                          size: 32,
                                        ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Upload Photo',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          color: deepPurple,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${person['photoCount'] ?? 0} photos stored',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.cloud_upload_outlined,
                                  color: vibrantPurple,
                                  size: 30,
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 45),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isUploadingPhotos
                              ? null
                              : () {
                                  _hapticFeedback();
                                  Navigator.pop(context);
                                },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            backgroundColor: deepPurple.withOpacity(0.15),
                            foregroundColor: deepPurple,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: vibrantPurple.withOpacity(0.35),
                                width: 1.3,
                              ),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isUploadingPhotos
                              ? null
                              : () async {
                                  final newName = nameController.text.trim();
                                  if (newName.isEmpty) {
                                    _showSnackBar(
                                      'Please enter a name',
                                      Colors.red,
                                    );
                                    return;
                                  }

                                  if (newName == person['name'] &&
                                      !photosChanged) {
                                    Navigator.pop(context);
                                    _showSnackBar(
                                      'No changes made',
                                      Colors.orange,
                                    );
                                    return;
                                  }

                                  _hapticFeedback();
                                  Navigator.pop(context);

                                  if (newName != person['name']) {
                                    await _updatePersonName(
                                      person['id'],
                                      person['name'],
                                      newName,
                                    );
                                  }

                                  if (mounted) {
                                    _showSnackBar(
                                      'Changes saved successfully! ✅',
                                      Colors.green,
                                    );
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            backgroundColor: primaryPurple,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Save Changes',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(String personId, String personName) {
    _hapticFeedback();
    _speak('Delete $personName');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Text(
                      'Delete Person',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: deepPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    text: 'Are you sure you want to delete ',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: deepPurple,
                    ),
                    children: [
                      TextSpan(
                        text: '"$personName"',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: deepPurple,
                          fontSize: 17,
                        ),
                      ),
                      const TextSpan(text: '?'),
                    ],
                  ),
                ),
                const SizedBox(height: 60),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _hapticFeedback();
                          _speak('Cancelled');
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          backgroundColor: deepPurple.withOpacity(0.15),
                          foregroundColor: deepPurple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: vibrantPurple.withOpacity(0.35),
                              width: 1.3,
                            ),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          _hapticFeedback();
                          Navigator.pop(context);
                          await _deletePerson(personId, personName);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Delete',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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

  List<Map<String, dynamic>> get _filteredPeople {
    if (_searchQuery.isEmpty) return _people;
    return _people
        .where(
          (person) =>
              person['name'].toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
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
                _buildModernHeader(),
                Expanded(child: _buildPeopleList()),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [_buildAddButton(), _buildFloatingBottomNav()],
      ),
    );
  }

  Widget _buildModernHeader() {
    return FadeTransition(
      opacity: _fadeController ?? const AlwaysStoppedAnimation(1.0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(25, 50, 25, 45),
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
        child: Column(
          children: [
            Row(
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Face Management',
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
                      const SizedBox(height: 4),
                      Text(
                        'Manage saved faces',
                        style: TextStyle(
                          fontSize: 14,
                          color: deepPurple.withOpacity(0.6),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),
            Container(
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    lightPurple.withOpacity(0.3),
                    palePurple.withOpacity(0.4),
                  ],
                ),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: deepPurple.withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: vibrantPurple.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.search, color: vibrantPurple, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      decoration: InputDecoration(
                        hintText: "Search people...",
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                          color: deepPurple.withOpacity(0.7),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: const TextStyle(
                        color: deepPurple,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeopleList() {
    return SlideTransition(
      position: _slideController != null
          ? Tween<Offset>(
              begin: const Offset(0, 0.15),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: _slideController!,
                curve: Curves.easeOutCubic,
              ),
            )
          : const AlwaysStoppedAnimation(Offset.zero),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: vibrantPurple))
          : _filteredPeople.isEmpty && _searchQuery.isNotEmpty
          ? _buildEmptySearch()
          : _people.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              itemCount: _filteredPeople.length,
              itemBuilder: (context, index) {
                return _buildPersonCard(_filteredPeople[index]);
              },
            ),
    );
  }

  Widget _buildPersonCard(Map<String, dynamic> person) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: palePurple.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            _hapticFeedback();
            _speak(person['name'] ?? 'Unknown');
            _showEditDialog(person);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [vibrantPurple, primaryPurple],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromARGB(76, 142, 58, 149),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(3),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    backgroundImage:
                        person['photoUrls'] != null &&
                            (person['photoUrls'] as List).isNotEmpty
                        ? NetworkImage(person['photoUrls'][0])
                        : null,
                    child:
                        person['photoUrls'] == null ||
                            (person['photoUrls'] as List).isEmpty
                        ? Icon(
                            Icons.person,
                            color: deepPurple.withOpacity(0.5),
                            size: 32,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person['name'] ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: deepPurple,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.photo_library,
                            size: 14,
                            color: vibrantPurple.withOpacity(0.6),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${person['photoCount'] ?? 0} photos',
                            style: TextStyle(
                              fontSize: 13,
                              color: deepPurple.withOpacity(0.5),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    _hapticFeedback();
                    _speak('Edit ${person['name']}');
                    _showEditDialog(person);
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: vibrantPurple.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: vibrantPurple.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.edit_outlined,
                      color: vibrantPurple,
                      size: 20,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    _hapticFeedback();
                    _showDeleteConfirmation(
                      person['id'],
                      person['name'] ?? 'Unknown',
                    );
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.red.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySearch() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: deepPurple.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              "No people found",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: deepPurple,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Try a different search term",
              style: TextStyle(
                fontSize: 14,
                color: deepPurple.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    vibrantPurple.withOpacity(0.2),
                    primaryPurple.withOpacity(0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.person_add_outlined,
                size: 50,
                color: vibrantPurple,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "No people added yet",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: deepPurple,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Tap the button below to add your first person",
              style: TextStyle(
                fontSize: 14,
                color: deepPurple.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 25),
      child: GestureDetector(
        onTap: () {
          _hapticFeedback();
          _speak('Add New Contact');
          _showAddDialog();
        },
        child: Container(
          width: double.infinity,
          height: 58,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [deepPurple, vibrantPurple]),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: vibrantPurple.withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                'Add New Contact',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBottomNav() {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
      ),
      child: Container(
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavButton(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  isActive: true,
                  onTap: () {
                    _hapticFeedback();
                    _speak('Home');
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const HomePage()),
                    );
                  },
                ),
                _buildNavButton(
                  icon: Icons.notifications_rounded,
                  label: 'Reminders',
                  onTap: () {
                    _hapticFeedback();
                    _speak('Reminders');
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RemindersPage(),
                      ),
                    );
                  },
                ),
                _buildNavButton(
                  icon: Icons.contact_phone,
                  label: 'Emergency',
                  onTap: () {
                    _hapticFeedback();
                    _speak('Emergency Contact');
                    Navigator.pushReplacement(
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
                  onTap: () {
                    _hapticFeedback();
                    _speak('Settings');
                    Navigator.pushReplacement(
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
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String label,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withOpacity(0.25) : Colors.transparent,
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
              color: isActive ? Colors.white : Colors.white.withOpacity(0.9),
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white.withOpacity(0.9),
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDialog() {
    _resetForm();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => WillPopScope(
          onWillPop: () async => !_isUploading,
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: vibrantPurple.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [vibrantPurple, primaryPurple],
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_add,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            "Add New Person",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _isUploading
                              ? null
                              : () {
                                  _resetForm();
                                  Navigator.pop(context);
                                },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close,
                              color: _isUploading
                                  ? Colors.white.withOpacity(0.5)
                                  : Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Name",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: deepPurple,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _nameController,
                            enabled: !_isUploading,
                            decoration: InputDecoration(
                              hintText: "Enter person's name",
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              fillColor: ultraLightPurple,
                              filled: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _selectedImages.length >= _minImages
                                  ? Colors.green.shade50
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _selectedImages.length >= _minImages
                                    ? Colors.green
                                    : Colors.orange,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _selectedImages.length >= _minImages
                                      ? Icons.check_circle
                                      : Icons.info_outline,
                                  color: _selectedImages.length >= _minImages
                                      ? Colors.green
                                      : Colors.orange,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _selectedImages.length >= _minImages
                                        ? 'Ready! ${_selectedImages.length} photos selected'
                                        : 'Need ${_minImages - _selectedImages.length} more photos (min $_minImages)',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          _selectedImages.length >= _minImages
                                          ? Colors.green.shade800
                                          : Colors.orange.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isUploading || _isProcessing
                                      ? null
                                      : () async {
                                          await _pickSingleImage();
                                          setDialogState(() {});
                                        },
                                  icon: const Icon(Icons.camera_alt, size: 20),
                                  label: const Text('Camera'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: deepPurple,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isUploading || _isProcessing
                                      ? null
                                      : () async {
                                          await _pickImages();
                                          setDialogState(() {});
                                        },
                                  icon: const Icon(
                                    Icons.photo_library,
                                    size: 20,
                                  ),
                                  label: const Text('Gallery'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: vibrantPurple,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (_selectedImages.isNotEmpty) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Selected Photos (${_selectedImages.length})',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: deepPurple,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _isUploading || _isProcessing
                                      ? null
                                      : () {
                                          setDialogState(
                                            () => _selectedImages.clear(),
                                          );
                                        },
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                  ),
                                  label: const Text('Clear All'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                  ),
                              itemCount: _selectedImages.length,
                              itemBuilder: (context, index) {
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(
                                        _selectedImages[index],
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    if (!_isUploading && !_isProcessing)
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: GestureDetector(
                                          onTap: () {
                                            setDialogState(
                                              () => _removeImage(index),
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.red,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black26,
                                                  blurRadius: 4,
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.close,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    Positioned(
                                      bottom: 4,
                                      left: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                          ],
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.lightbulb_outline,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'For best results, use 5-7 photos from different angles and lighting',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue.shade800,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed:
                                  _isUploading ||
                                      _isProcessing ||
                                      _nameController.text.trim().isEmpty ||
                                      _selectedImages.length < _minImages
                                  ? null
                                  : () async {
                                      setDialogState(() {
                                        _isUploading = true;
                                      });

                                      await _addPerson();

                                      if (mounted &&
                                          Navigator.canPop(context)) {
                                        setDialogState(() {
                                          _isUploading = false;
                                        });
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: deepPurple,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                disabledBackgroundColor: Colors.grey.shade300,
                                elevation: 0,
                              ),
                              child: _isUploading
                                  ? Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Processing ${_selectedImages.length} photos...',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Text(
                                      "Add Person & Train Model",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
