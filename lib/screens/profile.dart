import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isUploading = false;
  final picker = ImagePicker();
  final FlutterTts _flutterTts = FlutterTts();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

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
    _initializeTts();
    _loadUserData();
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  Future<void> _speakWelcome() async {
    await Future.delayed(const Duration(milliseconds: 500));
    await _speak(
      "Personal information page. You can edit your name and phone number.",
    );
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        DocumentSnapshot userDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          Map<String, dynamic> userData =
              userDoc.data() as Map<String, dynamic>;

          setState(() {
            _nameController.text = userData['full_name'] ?? '';
            _emailController.text = userData['email'] ?? user.email ?? '';
            _phoneController.text = userData['phone'] ?? '';
          });

          // النطق بعد تحميل البيانات
          await _speakWelcome();
        }
      } catch (e) {
        print('Error loading user data: $e');
        await _speakWelcome();
      }
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _saveFocus.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    await _speak("Are you sure you want to save changes?");

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(35),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: vibrantPurple.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.save_outlined,
                color: vibrantPurple,
                size: 52,
                semanticLabel: 'Save confirmation',
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Confirm Save',
              style: TextStyle(
                color: deepPurple,
                fontWeight: FontWeight.w800,
                fontSize: 26,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to save changes to your profile?',
          style: TextStyle(
            color: deepPurple.withOpacity(0.8),
            fontSize: 19,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        actions: [
          Column(
            children: [
              // Yes Button
              SizedBox(
                width: double.infinity,
                height: 62,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [vibrantPurple, primaryPurple],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: vibrantPurple.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'Yes, Save Changes',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        letterSpacing: 0.3,
                      ),
                      semanticsLabel: 'Yes, save changes to profile',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Cancel Button
              SizedBox(
                width: double.infinity,
                height: 58,
                child: Container(
                  decoration: BoxDecoration(
                    color: palePurple.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: vibrantPurple.withOpacity(0.5),
                      width: 2.5,
                    ),
                  ),
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: vibrantPurple,
                        fontWeight: FontWeight.w700,
                        fontSize: 19,
                        letterSpacing: 0.3,
                      ),
                      semanticsLabel: 'Cancel, do not save changes',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _speak("Saving your changes, please wait.");

      final user = _auth.currentUser;
      if (user != null) {
        Map<String, dynamic> userData = {
          'email': _emailController.text.trim(),
          'full_name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
        };

        await _firestore.collection('users').doc(user.uid).update(userData);
        setState(() {});

        await _speak("Your changes have been saved successfully.");

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Your changes have been saved successfully',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              backgroundColor: vibrantPurple,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
          );
        }
      }
    } else if (confirm == false) {
      await _speak("Changes cancelled.");
    }
  }

  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
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
                // 🎯 الهيدر الجديد - زر الرجوع والعنوان منزلين
                _buildModernHeader(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 15),

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

  // 🎯 الهيدر الجديد - زر الرجوع والعنوان منزلين
  Widget _buildModernHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        25,
        100,
        25,
        60,
      ), // زيادة الـ top إلى 100 لتنزيل المحتوى
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
          // 🔙 زر الرجوع على اليسار - بنفسجي
          Semantics(
            label: 'Go back to previous page',
            button: true,
            child: GestureDetector(
              onTap: () async {
                await _speak("Going back");
                await Future.delayed(const Duration(milliseconds: 800));
                if (mounted) {
                  Navigator.pop(context);
                }
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
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // النص في المنتصف
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My Profile',
                  style: TextStyle(
                    fontSize: 25.5,
                    fontWeight: FontWeight.w900,
                    foreground: Paint()
                      ..shader = LinearGradient(
                        colors: [deepPurple, vibrantPurple],
                      ).createShader(Rect.fromLTWH(0, 0, 200, 70)),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your personal information',
                  style: TextStyle(
                    fontSize: 14.5,
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
        padding: const EdgeInsets.all(30),
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
          children: [...children],
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
    final bool isEmail = label == "Email Address";

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
        const SizedBox(height: 20),
        Semantics(
          label: isEmail ? '$label (not editable)' : '$label input field',
          textField: !isEmail,
          child: GestureDetector(
            onTap: isEmail ? () => _speak("Email cannot be edited.") : null,
            child: TextField(
              controller: controller,
              focusNode: currentFocus,
              enabled: !isEmail,
              readOnly: isEmail,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => nextFocus.requestFocus(),
              onTap: () {
                if (!isEmail) {
                  _speak("Editing $label");
                }
              },
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
        ),
        const SizedBox(height: 20),
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
        height: 70,
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
          onPressed: _isUploading
              ? null
              : () {
                  _speak("Save changes button.");
                  _saveProfile();
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _isUploading
              ? const SizedBox(
                  height: 80,
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
