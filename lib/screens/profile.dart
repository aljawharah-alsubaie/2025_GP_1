import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  File? _image;
  String? _profileImageUrl;
  bool _isUploading = false;
  final picker = ImagePicker();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  late FocusNode _nameFocus;
  late FocusNode _emailFocus;
  late FocusNode _phoneFocus;
  late FocusNode _saveFocus;

  // 🎨 نفس ألوان الصفحة الرئيسية
  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color lightPurple = Color.fromARGB(255, 217, 163, 227);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);

  @override
  void initState() {
    super.initState();
    _nameFocus = FocusNode();
    _emailFocus = FocusNode();
    _phoneFocus = FocusNode();
    _saveFocus = FocusNode();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _saveFocus.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user != null) {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data();
        _emailController.text = data?['email'] ?? '';
        _nameController.text = data?['full_name'] ?? '';
        _phoneController.text = data?['phone'] ?? '';
        _profileImageUrl = data?['profileImageUrl'];
        setState(() {});
      }
    }
  }

  Future<String?> _uploadImageToFirebase(File imageFile) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final storageRef = _storage.ref().child('profilePic/${user.uid}.jpg');
      final uploadTask = storageRef.putFile(imageFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload image: $e'),
            backgroundColor: vibrantPurple,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _saveProfile() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(32),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: vibrantPurple.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.save_outlined,
                color: vibrantPurple,
                size: 48,
                semanticLabel: 'Save confirmation',
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Confirm Save',
              style: TextStyle(
                color: deepPurple,
                fontWeight: FontWeight.w800,
                fontSize: 24,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to save changes to your profile?',
          style: TextStyle(
            color: deepPurple.withOpacity(0.7),
            fontSize: 18,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        actions: [
          Column(
            children: [
              // Yes Button - Prominent
              SizedBox(
                width: double.infinity,
                height: 56,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [vibrantPurple, primaryPurple],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: vibrantPurple.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Yes, Save Changes',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                      semanticsLabel: 'Yes, save changes to profile',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Cancel Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.grey.shade100,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade300, width: 2),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: deepPurple,
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                    semanticsLabel: 'Cancel, do not save changes',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm == true) {
      final user = _auth.currentUser;
      if (user != null) {
        Map<String, dynamic> userData = {
          'email': _emailController.text.trim(),
          'full_name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
        };

        if (_image != null) {
          setState(() => _isUploading = true);
          final imageUrl = await _uploadImageToFirebase(_image!);
          if (imageUrl != null) {
            userData['profileImageUrl'] = imageUrl;
            _profileImageUrl = imageUrl;
          }
          setState(() => _isUploading = false);
        }

        await _firestore.collection('users').doc(user.uid).update(userData);
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Your changes have been saved successfully',
                style: TextStyle(fontSize: 16),
              ),
              backgroundColor: vibrantPurple,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _getImage() async {
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      setState(() => _image = File(pickedFile.path));
      // Announce image selection for screen readers
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile image selected'),
            duration: const Duration(seconds: 2),
            backgroundColor: vibrantPurple,
          ),
        );
      }
    }
  }

  ImageProvider _getProfileImage() {
    if (_image != null) {
      return FileImage(_image!);
    } else if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      return NetworkImage(_profileImageUrl!);
    } else {
      return const AssetImage('assets/images/profileimg.jpg');
    }
  }

  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: deepPurple,
        fontWeight: FontWeight.w500,
        fontSize: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: lightPurple, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: lightPurple, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: vibrantPurple, width: 3),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      filled: true,
      fillColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ultraLightPurple,
      body: Stack(
        children: [
          // 🎨 خلفية متدرجة مثل الصفحة الرئيسية
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

          SingleChildScrollView(
            child: Column(
              children: [
                _buildModernHeader(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),

                      // 📝 Personal Details Section
                      _buildSectionCard(
                        title: "Personal Details",
                        icon: Icons.person_outline,
                        children: [
                          _buildTextField(
                            "Name",
                            _nameController,
                            _nameFocus,
                            _emailFocus,
                            Icons.badge_outlined,
                          ),
                          _buildTextField(
                            "Email Address",
                            _emailController,
                            _emailFocus,
                            _phoneFocus,
                            Icons.email_outlined,
                          ),
                          _buildTextField(
                            "Phone Number",
                            _phoneController,
                            _phoneFocus,
                            _saveFocus,
                            Icons.phone_outlined,
                          ),
                        ],
                      ),

                      const SizedBox(height: 30),

                      // 💾 Save Button
                      _buildSaveButton(),

                      const SizedBox(height: 30),
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

  // 🎯 Modern Header مثل الصفحة الرئيسية
  Widget _buildModernHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 30),
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
          // Header Row
          Row(
            children: [
              // Back Button
              Semantics(
                label: 'Go back',
                button: true,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [vibrantPurple, primaryPurple],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: vibrantPurple.withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Title
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'My Profile',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      foreground: Paint()
                        ..shader = LinearGradient(
                          colors: [deepPurple, vibrantPurple],
                        ).createShader(Rect.fromLTWH(0, 0, 200, 70)),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),

          // Profile Picture
          Semantics(
            label: 'Profile picture. Double tap to change',
            button: true,
            image: true,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: vibrantPurple.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 70,
                    backgroundColor: Colors.white,
                    child: CircleAvatar(
                      radius: 66,
                      backgroundColor: palePurple,
                      backgroundImage: _getProfileImage(),
                    ),
                  ),
                ),

                if (_isUploading)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.5),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),

                Positioned(
                  bottom: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: _isUploading ? null : _getImage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [vibrantPurple, primaryPurple],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: vibrantPurple.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        size: 24,
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
    );
  }

  // 📦 Section Card
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Semantics(
      label: '$title section',
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: palePurple.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [vibrantPurple, primaryPurple],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: deepPurple,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  // 📝 Text Field
  Widget _buildTextField(
    String label,
    TextEditingController controller,
    FocusNode currentFocus,
    FocusNode nextFocus,
    IconData icon,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: vibrantPurple),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: deepPurple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          label: '$label input field',
          textField: true,
          child: TextField(
            controller: controller,
            focusNode: currentFocus,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => nextFocus.requestFocus(),
            keyboardType: label == "Email Address"
                ? TextInputType.emailAddress
                : label == "Phone Number"
                ? TextInputType.phone
                : TextInputType.text,
            decoration: _buildInputDecoration(label),
            style: TextStyle(
              fontSize: 16,
              color: deepPurple,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // 💾 Save Button
  Widget _buildSaveButton() {
    return Semantics(
      label: _isUploading
          ? 'Saving changes, please wait'
          : 'Save changes button. Double tap to save your profile',
      button: true,
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [vibrantPurple, primaryPurple]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: vibrantPurple.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          focusNode: _saveFocus,
          onPressed: _isUploading ? null : _saveProfile,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _isUploading
              ? const SizedBox(
                  height: 28,
                  width: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.save_outlined, color: Colors.white, size: 24),
                    SizedBox(width: 12),
                    Text(
                      "Save Changes",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
