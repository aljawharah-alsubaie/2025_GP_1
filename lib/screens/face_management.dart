import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;
import '../services/face_recognition_service.dart';
import 'home_page.dart';
import 'reminders.dart';
import 'sos_screen.dart';
import 'settings.dart';

class FaceManagementPage extends StatefulWidget {
  const FaceManagementPage({super.key});

  @override
  State<FaceManagementPage> createState() => _FaceManagementPageState();
}

class _FaceManagementPageState extends State<FaceManagementPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _people = [];
  bool _isLoading = true;
  bool _isUploading = false;
  bool _isProcessing = false; // ⭐ إضافة جديدة
  String _searchQuery = '';
  
  // Multiple images support
  List<File> _selectedImages = [];
  final int _minImages = 3;
  final int _maxImages = 10;

  @override
  void initState() {
    super.initState();
    _initializeFaceRecognition();
    _loadPeople();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
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
                .map((e) => (e as List).map((v) => (v as num).toDouble()).toList())
                .toList();
            allEmbeddings[doc.id] = personEmbeddings;
          }
        }

        FaceRecognitionService.loadMultipleEmbeddings(allEmbeddings);
        print('✅ Loaded embeddings for ${allEmbeddings.length} persons');
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading people: $e')),
        );
      }
    }
  }

  Future<void> _pickImages() async {
    if (_selectedImages.length >= _maxImages) {
      _showSnackBar('Maximum $_maxImages photos allowed', Colors.orange);
      return;
    }

    try {
      final List<XFile> images = await ImagePicker().pickMultiImage(imageQuality: 90);

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

  // ⭐ الدالة المعدلة
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

    // ⭐ تحقق من أن العملية ما بدأت
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

      // Upload photos and generate embeddings
      for (int i = 0; i < _selectedImages.length; i++) {
        try {
          // Detect and crop face
          final faceRect = await FaceRecognitionService.detectFaceEnhanced(_selectedImages[i]);
          
          if (faceRect != null) {
            final croppedFace = await FaceRecognitionService.cropFaceEnhanced(
              _selectedImages[i],
              faceRect,
            );

            if (croppedFace != null) {
              // Upload to Storage
              final storageRef = FirebaseStorage.instance
                  .ref()
                  .child('users')
                  .child(user.uid)
                  .child('faces')
                  .child(personName)
                  .child('${DateTime.now().millisecondsSinceEpoch}_$i.jpg');

              // Save cropped face as proper file
              final tempDir = await Directory.systemTemp.createTemp();
              final tempFile = File('${tempDir.path}/face_$i.jpg');
              
              // Use image package to encode properly
              final jpg = img.encodeJpg(croppedFace);
              await tempFile.writeAsBytes(jpg);

              // Generate embedding FIRST (before upload/delete)
              final success = await FaceRecognitionService.storeFaceEmbedding(
                personName,
                tempFile,
                normalizationType: 'arcface',
              );

              if (success) {
                successCount++;
                
                // Only upload if embedding succeeded
                final uploadTask = await storageRef.putFile(tempFile);
                final photoUrl = await uploadTask.ref.getDownloadURL();
                photoUrls.add(photoUrl);
              } else {
                failedCount++;
              }

              // Clean up temp file AFTER everything
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

        // Update progress - ⭐ إزالة setState من هنا
      }

      if (successCount > 0) {
        // Save to Firestore
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

        // Save embeddings
        await _saveEmbeddingsToFirestore(personName);
        await _loadPeople();

        if (mounted) {
          // ⭐ أغلق الـ dialog أولاً
          Navigator.pop(context);
          
          // ⭐ انتظر frame واحد قبل ما تنضف
          await Future.delayed(const Duration(milliseconds: 100));
          
          // ⭐ نضف البيانات بعد ما ينغلق الـ dialog
          _resetForm();
          
          // ⭐ اعرض رسالة النجاح
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

  // ⭐ دالة معدلة
  void _showSuccessDialog(String personName, int success, int failed) {
    // ⭐ تأكد إن الـ context لسه موجود
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false, // ⭐ امنع الإغلاق بالضغط برا
      builder: (context) => WillPopScope( // ⭐ امنع الرجوع بزر الباك
        onWillPop: () async => false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 32),
              SizedBox(width: 12),
              Text('Success!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Person: $personName', 
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('✅ Successful: $success photos'),
              if (failed > 0) 
                Text('❌ Failed: $failed photos', 
                  style: const TextStyle(color: Colors.orange)),
              const SizedBox(height: 12),
              const Text('Face recognition trained successfully!',
                style: TextStyle(fontSize: 14, color: Colors.green)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Add Another'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // أغلق الـ dialog
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B1D73),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  // ⭐ دالة معدلة
  void _resetForm() {
    // ⭐ استخدم post frame callback عشان تتجنب مشاكل rebuild
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

  Future<void> _deletePerson(String personId, String personName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Delete from Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('people')
          .doc(personId)
          .delete();

      // Delete embeddings
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

  void _showDeleteConfirmation(String personId, String personName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Person',
          style: TextStyle(color: Color(0xFF6B1D73), fontWeight: FontWeight.bold),
        ),
        content: Text('Are you sure you want to delete "$personName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deletePerson(personId, personName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
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

  List<Map<String, dynamic>> get _filteredPeople {
    if (_searchQuery.isEmpty) return _people;
    return _people
        .where((person) =>
            person['name'].toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.only(
                    top: 40,
                    left: 16,
                    right: 16,
                    bottom: 30,
                  ),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(74, 243, 210, 247),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(65),
                      bottomRight: Radius.circular(65),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 40,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Text(
                              'Face Management',
                              style: TextStyle(
                                color: Color(0xFFB14ABA),
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Positioned(
                              left: 0,
                              child: GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: const Icon(
                                  Icons.arrow_back_ios,
                                  color: Color(0xFFB14ABA),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 25),
                      Center(
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.85,
                          height: 35,
                          decoration: BoxDecoration(
                            color: const Color(0x38B14ABA),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.search,
                                color: Color(0xFFB14ABA),
                                size: 25,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  onChanged: (value) =>
                                      setState(() => _searchQuery = value),
                                  decoration: const InputDecoration(
                                    hintText: "Search",
                                    border: InputBorder.none,
                                    hintStyle: TextStyle(
                                      color: Color(0xFFB14ABA),
                                    ),
                                    contentPadding: EdgeInsets.only(bottom: 10),
                                  ),
                                  style: const TextStyle(
                                    color: Color(0xFFB14ABA),
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
                const SizedBox(height: 23),
                _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(50.0),
                        child: CircularProgressIndicator(
                          color: Color(0xFFB14ABA),
                        ),
                      )
                    : _filteredPeople.isEmpty && _searchQuery.isNotEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(40.0),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.search_off,
                                    size: 40,
                                    color: Colors.grey.withOpacity(0.6),
                                  ),
                                  const SizedBox(height: 15),
                                  const Text(
                                    "No people found matching your search",
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _people.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(40.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.person_add_outlined,
                                        size: 40,
                                        color: const Color(0xFFB14ABA)
                                            .withOpacity(0.6),
                                      ),
                                      const SizedBox(height: 15),
                                      const Text(
                                        "You haven't added people yet",
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Column(
                                  children: _filteredPeople.map((person) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 20),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF640B6D),
                                            Color(0xFFCEA5D2),
                                          ],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Stack(
                                        children: [
                                          ListTile(
                                            contentPadding:
                                                const EdgeInsets.all(16),
                                            leading: CircleAvatar(
                                              radius: 30,
                                              backgroundColor: Colors.white,
                                              backgroundImage:
                                                  person['photoUrls'] != null &&
                                                          (person['photoUrls']
                                                                  as List)
                                                              .isNotEmpty
                                                      ? NetworkImage(
                                                          person['photoUrls'][0])
                                                      : null,
                                              child: person['photoUrls'] ==
                                                          null ||
                                                      (person['photoUrls']
                                                              as List)
                                                          .isEmpty
                                                  ? const Icon(Icons.person,
                                                      color: Colors.grey)
                                                  : null,
                                            ),
                                            title: Text(
                                              person['name'] ?? 'Unknown',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            subtitle: Text(
                                              '${person['photoCount'] ?? 0} photos',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 10,
                                            right: 10,
                                            child: GestureDetector(
                                              onTap: () =>
                                                  _showDeleteConfirmation(
                                                person['id'],
                                                person['name'] ?? 'Unknown',
                                              ),
                                              child: Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withOpacity(0.25),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withOpacity(0.4),
                                                    width: 2,
                                                  ),
                                                ),
                                                child: const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.white,
                                                  size: 22,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: GestureDetector(
              onTap: () => _showAddDialog(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF6B1D73),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6B1D73).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: Colors.white, size: 24),
                    SizedBox(width: 10),
                    Text(
                      'Add Contact',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const HomePage()),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.home_outlined, size: 26, color: Color(0xFFB14ABA)),
                      SizedBox(height: 2),
                      Text('Home',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFB14ABA))),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const RemindersPage()),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none,
                          size: 26, color: Colors.black54),
                      SizedBox(height: 2),
                      Text('Reminders',
                          style: TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const SosScreen()),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning_amber_outlined,
                          size: 26, color: Colors.black54),
                      SizedBox(height: 2),
                      Text('Emergency',
                          style: TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsPage()),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.settings, size: 26, color: Colors.black54),
                      SizedBox(height: 2),
                      Text('Settings',
                          style: TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ⭐ دالة معدلة
  void _showAddDialog() {
    _resetForm();
    showDialog(
      context: context,
      barrierDismissible: false, // ⭐ امنع الإغلاق أثناء المعالجة
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => WillPopScope(
          onWillPop: () async => !_isUploading, // ⭐ امنع الإغلاق لو في معالجة
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(width: 24),
                        const Text(
                          "Add Person",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF6B1D73),
                          ),
                        ),
                        GestureDetector(
                          onTap: _isUploading ? null : () { // ⭐ منع الإغلاق أثناء الرفع
                            _resetForm();
                            Navigator.pop(context);
                          },
                          child: Icon(Icons.close, 
                            color: _isUploading ? Colors.grey : const Color(0xFF6B1D73)
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text("Name", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: _nameController,
                      enabled: !_isUploading, // ⭐ تعطيل أثناء الرفع
                      decoration: InputDecoration(
                        hintText: "Enter name",
                        hintStyle: const TextStyle(color: Colors.grey),
                        fillColor: Colors.grey.shade100,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _selectedImages.length >= _minImages
                            ? Colors.green.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedImages.length >= _minImages
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _selectedImages.length >= _minImages
                                ? Icons.check_circle
                                : Icons.info,
                            color: _selectedImages.length >= _minImages
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedImages.length >= _minImages
                                  ? 'Ready! ${_selectedImages.length} photos selected'
                                  : 'Need ${_minImages - _selectedImages.length} more photos (min $_minImages)',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isUploading || _isProcessing // ⭐ إضافة _isProcessing
                                ? null
                                : () async {
                                    await _pickSingleImage();
                                    setDialogState(() {});
                                  },
                            icon: const Icon(Icons.camera_alt, size: 18),
                            label: const Text('Camera'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6B1D73),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isUploading || _isProcessing // ⭐ إضافة _isProcessing
                                ? null
                                : () async {
                                    await _pickImages();
                                    setDialogState(() {});
                                  },
                            icon: const Icon(Icons.photo_library, size: 18),
                            label: const Text('Gallery'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple.shade300,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Images Grid
                    if (_selectedImages.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Selected Photos (${_selectedImages.length})',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _isUploading || _isProcessing // ⭐ إضافة _isProcessing
                                ? null
                                : () {
                                    setDialogState(() => _selectedImages.clear());
                                  },
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('Clear'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 200,
                        child: GridView.builder(
                          shrinkWrap: true,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _selectedImages.length,
                          itemBuilder: (context, index) {
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    _selectedImages[index],
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: _isUploading || _isProcessing // ⭐ منع الحذف أثناء المعالجة
                                        ? null
                                        : () {
                                            setDialogState(() => _removeImage(index));
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: _isUploading || _isProcessing 
                                            ? Colors.grey 
                                            : Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 14,
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
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 24),
                    
                    // Submit Button - ⭐ التعديل الرئيسي
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        onPressed: _isUploading ||
                                _isProcessing || // ⭐ إضافة
                                _nameController.text.trim().isEmpty ||
                                _selectedImages.length < _minImages
                            ? null
                            : () async {
                                // ⭐ تحديث حالة الـ dialog
                                setDialogState(() {
                                  _isUploading = true;
                                });
                                
                                // ⭐ تنفيذ العملية
                                await _addPerson();
                                
                                // ⭐ لو لسه موجود، حدّث الحالة
                                if (mounted && Navigator.canPop(context)) {
                                  setDialogState(() {
                                    _isUploading = false;
                                  });
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B1D73),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          disabledBackgroundColor: Colors.grey.shade300,
                        ),
                        child: _isUploading
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Processing ${_selectedImages.length} photos...',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ],
                              )
                            : const Text(
                                "Add Person & Train Model",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Info Text
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Best results with 5-7 photos from different angles',
                              style: TextStyle(fontSize: 11, color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}