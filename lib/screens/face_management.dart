import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
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
  File? _selectedImage;
  File? _croppedFaceImage;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _people = [];
  bool _isLoading = true;
  bool _isUploading = false;
  bool _isDetectingFace = false;
  String _searchQuery = '';

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
    FaceRecognitionService.dispose();
    super.dispose();
  }

  Future<void> _initializeFaceRecognition() async {
    final success = await FaceRecognitionService.initialize();
    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to initialize face recognition'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else {
      await _loadStoredEmbeddings();
    }
  }

  Future<void> _loadStoredEmbeddings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('face_embeddings')
          .doc('embeddings')
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        Map<String, List<double>> embeddings = {};

        data.forEach((key, value) {
          if (value is List) {
            embeddings[key] = List<double>.from(value);
          }
        });

        FaceRecognitionService.loadEmbeddings(embeddings);
      }
    } catch (e) {
      print('Error loading embeddings: $e');
    }
  }

  Future<void> _saveEmbeddingsToFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final embeddings = FaceRecognitionService.getStoredEmbeddings();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('face_embeddings')
          .doc('embeddings')
          .set(embeddings);
    } catch (e) {
      print('Error saving embeddings: $e');
    }
  }

  Future<Rect?> detectFace(File imageFile) async {
    return await FaceRecognitionService.detectFaceEnhanced(imageFile);
  }

  Future<File?> cropFace(File imageFile, Rect rect) async {
    try {
      final croppedImage = await FaceRecognitionService.cropFaceEnhanced(
        imageFile,
        rect,
      );
      if (croppedImage == null) return null;

      final croppedFile = File('${imageFile.path}_face.jpg')
        ..writeAsBytesSync(img.encodeJpg(croppedImage));
      return croppedFile;
    } catch (e) {
      print('Error cropping face: $e');
      return imageFile;
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

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final imageFile = File(picked.path);

      setState(() {
        _isDetectingFace = true;
        _selectedImage = imageFile;
        _croppedFaceImage = null;
      });

      try {
        final faceRect = await detectFace(imageFile);

        if (faceRect != null) {
          final croppedFace = await cropFace(imageFile, faceRect);

          setState(() {
            _croppedFaceImage = croppedFace;
            _isDetectingFace = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Face detected and cropped successfully!'),
                backgroundColor: Color(0xFF6B1D73),
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          setState(() => _isDetectingFace = false);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No face detected in this image. Please choose a clear face photo.',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      } catch (e) {
        setState(() => _isDetectingFace = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error detecting face: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _addPerson() async {
    if (_nameController.text.trim().isEmpty || _selectedImage == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please provide both name and photo')),
        );
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isUploading = true);

    try {
      final imageToUpload = _croppedFaceImage ?? _selectedImage!;

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('photos')
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      final uploadTask = await storageRef.putFile(imageToUpload);
      final photoUrl = await uploadTask.ref.getDownloadURL();

      final docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('people')
          .add({
            'name': _nameController.text.trim(),
            'photoUrl': photoUrl,
            'faceDetected': _croppedFaceImage != null,
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (_croppedFaceImage != null) {
        final success = await FaceRecognitionService.storeFaceEmbedding(
          docRef.id,
          _croppedFaceImage!,
          normalizationType: 'arcface',
        );

        if (success) {
          await _saveEmbeddingsToFirestore();
        }
      }

      await _loadPeople();

      if (mounted) {
        Navigator.pop(context);
        _resetForm();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _croppedFaceImage != null
                  ? 'Person added successfully with face recognition!'
                  : 'Person added successfully (no face detected)',
            ),
            backgroundColor: _croppedFaceImage != null
                ? Colors.green
                : Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding person: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _resetForm() {
    setState(() {
      _selectedImage = null;
      _croppedFaceImage = null;
      _nameController.clear();
      _isUploading = false;
      _isDetectingFace = false;
    });
  }

  Future<void> _deletePerson(
    String personId,
    String personName,
    String? photoUrl,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('people')
          .doc(personId)
          .delete();

      if (photoUrl != null && photoUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(photoUrl).delete();
        } catch (e) {
          print('Storage deletion error: $e');
        }
      }

      FaceRecognitionService.removeFaceEmbedding(personId);
      await _saveEmbeddingsToFirestore();

      await _loadPeople();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$personName deleted successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting person: $e')));
      }
    }
  }

  Future<void> _updatePerson(
    String personId,
    String newName,
    File? newImage,
    String? oldPhotoUrl,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isUploading = true);

    try {
      String? photoUrl = oldPhotoUrl;
      bool? faceDetected;

      if (newImage != null) {
        final imageToUpload = _croppedFaceImage ?? newImage;
        faceDetected = _croppedFaceImage != null;

        if (oldPhotoUrl != null && oldPhotoUrl.isNotEmpty) {
          try {
            await FirebaseStorage.instance.refFromURL(oldPhotoUrl).delete();
          } catch (e) {
            print('Error deleting old image: $e');
          }
        }

        final storageRef = FirebaseStorage.instance
            .ref()
            .child('users')
            .child(user.uid)
            .child('photos')
            .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

        final uploadTask = await storageRef.putFile(imageToUpload);
        photoUrl = await uploadTask.ref.getDownloadURL();

        if (_croppedFaceImage != null) {
          FaceRecognitionService.removeFaceEmbedding(personId);
          final success = await FaceRecognitionService.storeFaceEmbedding(
            personId,
            _croppedFaceImage!,
            normalizationType: 'arcface',
          );

          if (success) {
            await _saveEmbeddingsToFirestore();
          }
        } else {
          FaceRecognitionService.removeFaceEmbedding(personId);
          await _saveEmbeddingsToFirestore();
        }
      }

      final updateData = <String, dynamic>{'name': newName.trim()};
      if (photoUrl != null) updateData['photoUrl'] = photoUrl;
      if (faceDetected != null) updateData['faceDetected'] = faceDetected;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('people')
          .doc(personId)
          .update(updateData);

      await _loadPeople();

      if (mounted) {
        Navigator.pop(context);
        _resetForm();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              faceDetected == true
                  ? 'Person updated successfully with face detection!'
                  : faceDetected == false
                  ? 'Person updated successfully (no face detected in new photo)'
                  : 'Person updated successfully!',
            ),
            backgroundColor: faceDetected == true
                ? Colors.green
                : Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating person: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDeleteConfirmation(
    String personId,
    String personName,
    String? photoUrl,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Delete Person',
            style: TextStyle(
              color: Color(0xFF6B1D73),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to delete "$personName"?',
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _deletePerson(personId, personName, photoUrl);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B1D73),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ],
        );
      },
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
                                color: const Color(0xFFB14ABA).withOpacity(0.6),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                    contentPadding: const EdgeInsets.all(16),
                                    leading: CircleAvatar(
                                      radius: 30,
                                      backgroundColor: Colors.white,
                                      backgroundImage:
                                          person['photoUrl'] != null
                                          ? NetworkImage(person['photoUrl'])
                                          : null,
                                      child: person['photoUrl'] == null
                                          ? const Icon(
                                              Icons.person,
                                              color: Colors.grey,
                                            )
                                          : null,
                                    ),
                                    title: Text(
                                      person['name'] ?? 'Unknown',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GestureDetector(
                                          onTap: () => _showEditDialog(
                                            person['id'],
                                            person['name'] ?? 'Unknown',
                                            person['photoUrl'],
                                          ),
                                          child: Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(
                                                0.25,
                                              ),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white.withOpacity(
                                                  0.4,
                                                ),
                                                width: 2,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.edit,
                                              color: Colors.white,
                                              size: 22,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        GestureDetector(
                                          onTap: () => _showDeleteConfirmation(
                                            person['id'],
                                            person['name'] ?? 'Unknown',
                                            person['photoUrl'],
                                          ),
                                          child: Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(
                                                0.25,
                                              ),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white.withOpacity(
                                                  0.4,
                                                ),
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
                                      ],
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
                      Icon(
                        Icons.home_outlined,
                        size: 26,
                        color: Color(0xFFB14ABA),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Home',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFB14ABA),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RemindersPage(),
                    ),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 26,
                        color: Colors.black54,
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Reminders',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
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
                      Icon(
                        Icons.warning_amber_outlined,
                        size: 26,
                        color: Colors.black54,
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Emergency',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsPage(),
                    ),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.settings, size: 26, color: Colors.black54),
                      SizedBox(height: 2),
                      Text(
                        'Settings',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
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

  void _showAddDialog() {
    _resetForm();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
                        onTap: () {
                          _resetForm();
                          Navigator.pop(context);
                        },
                        child: const Icon(
                          Icons.close,
                          color: Color(0xFF6B1D73),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Name",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  TextField(
                    controller: _nameController,
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
                  Row(
                    children: [
                      const Text(
                        "Upload Face Photo",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (_croppedFaceImage != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            "Face Ready",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ] else if (_selectedImage != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            "No Face",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  GestureDetector(
                    onTap: _isDetectingFace
                        ? null
                        : () async {
                            await _pickImage();
                            setDialogState(() {});
                          },
                    child: Container(
                      width: double.infinity,
                      height: 100,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _selectedImage != null
                            ? const Color(0xFFF8F4F9)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _croppedFaceImage != null
                              ? Colors.green
                              : _selectedImage != null
                              ? Colors.orange
                              : Colors.grey.shade300,
                          width: _selectedImage != null ? 2 : 1,
                        ),
                      ),
                      child: _isDetectingFace
                          ? const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                  color: Color(0xFF6B1D73),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  "Detecting face...",
                                  style: TextStyle(
                                    color: Color(0xFF6B1D73),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            )
                          : _selectedImage == null
                          ? const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.upload,
                                  size: 30,
                                  color: Color(0xFF6B1D73),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  "Click to Upload Photo",
                                  style: TextStyle(
                                    color: Color(0xFF6B1D73),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _croppedFaceImage != null
                                        ? Colors.green
                                        : Colors.orange,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _croppedFaceImage != null
                                        ? "Face Detected & Ready"
                                        : "No Face Detected",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  "Tap to change photo",
                                  style: TextStyle(
                                    color: Color(0xFF6B1D73),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton(
                      onPressed:
                          _isUploading ||
                              _nameController.text.trim().isEmpty ||
                              _selectedImage == null
                          ? null
                          : () async {
                              setDialogState(() => _isUploading = true);
                              await _addPerson();
                              setDialogState(() => _isUploading = false);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B1D73),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor: Colors.grey.shade300,
                      ),
                      child: _isUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              "Add Person",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
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

  void _showEditDialog(
    String personId,
    String currentName,
    String? currentPhotoUrl,
  ) {
    _resetForm();
    _nameController.text = currentName;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
                        "Edit Person",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6B1D73),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          _resetForm();
                          Navigator.pop(context);
                        },
                        child: const Icon(
                          Icons.close,
                          color: Color(0xFF6B1D73),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Name",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  TextField(
                    controller: _nameController,
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
                  const Text(
                    "Photo",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: double.infinity,
                    height: 80,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F4F9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300, width: 1),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: Colors.white,
                          backgroundImage: _selectedImage != null
                              ? FileImage(_selectedImage!)
                              : (currentPhotoUrl != null
                                    ? NetworkImage(currentPhotoUrl)
                                    : null),
                          child:
                              _selectedImage == null && currentPhotoUrl == null
                              ? const Icon(Icons.person, color: Colors.grey)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _selectedImage != null
                                    ? "New photo selected"
                                    : "Current photo",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: _isDetectingFace
                                    ? null
                                    : () async {
                                        await _pickImage();
                                        setDialogState(() {});
                                      },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6B1D73),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _isDetectingFace
                                        ? "Detecting..."
                                        : "Change Photo",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
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
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton(
                      onPressed:
                          _isUploading || _nameController.text.trim().isEmpty
                          ? null
                          : () async {
                              setDialogState(() => _isUploading = true);
                              await _updatePerson(
                                personId,
                                _nameController.text.trim(),
                                _selectedImage,
                                currentPhotoUrl,
                              );
                              setDialogState(() => _isUploading = false);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B1D73),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor: Colors.grey.shade300,
                      ),
                      child: _isUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              "Update Person",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
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
