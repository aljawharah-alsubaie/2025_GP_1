import 'dart:async'; // Timer
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart'; // HapticFeedback
import 'package:flutter/semantics.dart'; // SemanticsService

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isUploading = false;
  final picker = ImagePicker();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  late FocusNode _nameFocus;
  late FocusNode _emailFocus;
  late FocusNode _phoneFocus;
  late FocusNode _saveFocus;

  // 🎨 Colors
  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color lightPurple = Color.fromARGB(255, 217, 163, 227);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);

  // ===== Error banner & typing throttle =====
  String? _currentErrorMessage;
  bool _showErrorBanner = false;

  Timer? _typingTimer;
  final Duration _typingDelay = const Duration(seconds: 1);
  final Map<String, String> _lastValues = {'name': '', 'phone': ''};

  // ===== TTS =====
  final FlutterTts _flutterTts = FlutterTts();
  bool _ttsInitialized = false;

  // 🆕 نحتفظ بالقيم الأصلية للمقارنة وقت الضغط على Save
  String? _initialName;
  String? _initialPhone;

  Future<void> _initTTS() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    try {
      await _flutterTts.awaitSpeakCompletion(true);
    } catch (_) {}
    _ttsInitialized = true;
  }

  Future<void> _speak(String text) async {
    if (!_ttsInitialized || text.trim().isEmpty || !mounted) return;
    try {
      await _flutterTts.speak(text);
    } catch (_) {}
  }

  Future<void> _speakForce(String text) async {
    if (!_ttsInitialized || text.trim().isEmpty || !mounted) return;
    try {
      await _flutterTts.stop();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 50));
    try {
      await _flutterTts.speak(text);
    } catch (_) {}
  }

  Future<void> _stopSpeech() async {
    try {
      await _flutterTts.stop();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _nameFocus = FocusNode();
    _emailFocus = FocusNode();
    _phoneFocus = FocusNode();
    _saveFocus = FocusNode();
    _initTTS();
    _loadUserData();
  }

  Future<void> _speakWelcome() async {
    await Future.delayed(const Duration(milliseconds: 300));
    await _speak("Manage your personal information");
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final userDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;

          // خزّني النسخ الأصلية قبل عرضها
          _initialName = (data['full_name'] ?? '').toString();
          _initialPhone = (data['phone'] ?? '').toString();

          setState(() {
            _nameController.text = _initialName ?? '';
            _emailController.text = data['email'] ?? user.email ?? '';
            _phoneController.text = _initialPhone ?? '';
          });
          await _speakWelcome();
        }
      } catch (_) {
        await _speakWelcome();
      }
    }
  }

  // يوقف الكلام ويخفي الشريط لما الصفحة تفقد التركيز/نطلع
  @override
  void deactivate() {
    _stopSpeech();
    if (mounted) {
      _showErrorBanner = false;
      _currentErrorMessage = null;
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _stopSpeech();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _saveFocus.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ===== Helpers: phone errors list =====
  List<String> _getPhoneErrors(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[-\s()]'), '');
    final errors = <String>[];
    if (!cleaned.startsWith('05')) errors.add("Must start with 05");
    if (cleaned.length != 10) errors.add("Must be exactly 10 digits");
    if (!RegExp(r'^[0-9]+$').hasMatch(cleaned)) {
      errors.add("Should contain only numbers");
    }
    return errors;
  }

  // ===== Validators =====
  String? _validateName(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Name is required";
    if (RegExp(r'[0-9]').hasMatch(value)) {
      return "Name should not contain numbers";
    }
    return null;
  }

  String? _validatePhone(String? v) {
    final raw = (v ?? '').trim();
    if (raw.isEmpty) return "Mobile number is required";
    final errors = _getPhoneErrors(raw);
    if (errors.isEmpty) return null;
    return "Mobile number issues: ${errors.join('; ')}";
  }

  // ===== Banner helpers =====

  void _showBannerSilent({
    required String msg,
    bool autoHide = true,
    Duration hideAfter = const Duration(seconds: 20),
  }) {
    setState(() {
      _currentErrorMessage = msg;
      _showErrorBanner = true;
    });
    if (autoHide) {
      Future.delayed(hideAfter).then((_) {
        if (!mounted) return;
        setState(() {
          _showErrorBanner = false;
          _currentErrorMessage = null;
        });
      });
    }
  }

  void _showErrorWithSoundAndBanner(
    String msg, {
    bool autoHide = true,
    Duration hideAfter = const Duration(seconds: 20),
  }) {
    setState(() {
      _currentErrorMessage = msg;
      _showErrorBanner = true;
    });
    SemanticsService.announce(msg, TextDirection.ltr);
    _speakForce("Error: $msg");
    HapticFeedback.heavyImpact();

    if (autoHide) {
      Future.delayed(hideAfter).then((_) {
        if (!mounted) return;
        setState(() {
          _showErrorBanner = false;
          _currentErrorMessage = null;
        });
      });
    }
  }

  void _hideErrorBanner() async {
    await _stopSpeech(); // يوقف الكلام عند الضغط على X
    setState(() {
      _showErrorBanner = false;
      _currentErrorMessage = null;
    });
  }

  // يجمع كل الأخطاء ويعرضها بشريط واحد وينطقها بندًا بندًا
  Future<bool> _validateAllAndAnnounce() async {
    final nameErr = _validateName(_nameController.text);

    final phoneRaw = _phoneController.text.trim();
    String? phoneSummary;
    List<String> phoneList = [];
    if (phoneRaw.isEmpty) {
      phoneSummary = "Mobile number is required";
    } else {
      phoneList = _getPhoneErrors(phoneRaw);
      if (phoneList.isNotEmpty) {
        phoneSummary = "Mobile number has ${phoneList.length} issue(s)";
      }
    }

    final hasErrors = (nameErr != null) || (phoneSummary != null);
    if (!hasErrors) return true;

    final buf = StringBuffer("Please fix the following errors:\n\n");
    if (nameErr != null) buf.writeln("• Name: $nameErr\n");
    if (phoneSummary != null) {
      if (phoneList.isEmpty) {
        buf.writeln("• Mobile Number: $phoneSummary\n");
      } else {
        buf.writeln("• Mobile Number:");
        for (final e in phoneList) {
          buf.writeln("   - $e");
        }
        buf.writeln();
      }
    }
    final msg = buf.toString().trimRight();

    _showBannerSilent(
      msg: msg,
      autoHide: true,
      hideAfter: const Duration(seconds: 25), // نفس كودك الحالي
    );

    await _stopSpeech();
    await _speak(
      "Found ${(nameErr != null ? 1 : 0) + (phoneSummary != null ? 1 : 0)} errors.",
    );
    if (nameErr != null) {
      await _speak("Name: $nameErr");
    }
    if (phoneSummary != null) {
      if (phoneList.isEmpty) {
        await _speak("Mobile Number: $phoneSummary");
      } else {
        await _speak("Mobile number issues:");
        for (final e in phoneList) {
          await _speak(e);
        }
      }
    }
    await _speak("Please fix these errors and try again.");

    return false;
  }

  // 🆕 فحص إن كان فيه تغييرات فعلًا
  bool _noChangesMade() {
    final currentName = _nameController.text.trim();
    final currentPhone = _phoneController.text.trim();
    final initialName = (_initialName ?? '').trim();
    final initialPhone = (_initialPhone ?? '').trim();
    return currentName == initialName && currentPhone == initialPhone;
  }

  // ===== Real-time typing validation =====
  void _onFieldChanged(String fieldName, String value) {
    _typingTimer?.cancel();
    if (_lastValues[fieldName] == value) return;
    _lastValues[fieldName] = value;

    _typingTimer = Timer(_typingDelay, () {
      _validateFieldInRealTime(fieldName, value);
    });
  }

  void _validateFieldInRealTime(String fieldName, String value) {
    String? err;
    if (fieldName == 'name') err = _validateName(value);
    if (fieldName == 'phone') err = _validatePhone(value);

    if (err != null && value.trim().isNotEmpty) {
      _showErrorWithSoundAndBanner(
        err,
        autoHide: true,
        hideAfter: const Duration(seconds: 20),
      );
    }
  }

  Future<void> _saveProfile() async {
    // 🆕 أولًا: إذا ما فيه تغييرات، ننطق ونطلع
    if (_noChangesMade()) {
      await _speakForce("No changes made to your profile");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No changes to save',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            backgroundColor: Color(0xFF7A7A7A),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // بعدها نتحقق من الصحة (حتى بدون تعديل في الحقول الأخرى)
    final ok = await _validateAllAndAnnounce();
    if (!ok) return;

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
              child: Icon(Icons.save_outlined, color: vibrantPurple, size: 52),
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
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
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
        final userData = {
          'email': _emailController.text.trim(),
          'full_name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
        };

        await _firestore.collection('users').doc(user.uid).update(userData);
        setState(() {
          // حدّث النسخ الأصلية بعد الحفظ الناجح
          _initialName = _nameController.text.trim();
          _initialPhone = _phoneController.text.trim();
        });

        await _speak("Your changes have been saved successfully.");

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your changes have been saved successfully',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
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
    return WillPopScope(
      onWillPop: () async {
        await _stopSpeech(); // يوقف الكلام عند رجوع النظام
        if (mounted) {
          _showErrorBanner = false;
          _currentErrorMessage = null;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: ultraLightPurple,
        body: Stack(
          children: [
            // الخلفية
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
                        const SizedBox(height: 15),
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
                        _buildSaveButton(),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // شريط الخطأ
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildErrorBanner(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(25, 100, 25, 60),
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
          // Back button: صامت + يوقف الكلام ويغلق الشريط
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
                child: const Center(
                  child: Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 20,
                  ),
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
            onTap: isEmail
                ? () async => _speak("Email cannot be edited.")
                : null,
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
              onChanged: (v) {
                if (label == "Name") _onFieldChanged('name', v);
                if (label == "Phone Number") _onFieldChanged('phone', v);
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

  Widget _buildErrorBanner() {
    if (!_showErrorBanner || _currentErrorMessage == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFD32F2F),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                _currentErrorMessage!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
                softWrap: true,
              ),
            ),
          ),
          Semantics(
            label: 'Close error message',
            button: true,
            hint: 'Double tap to close error message',
            child: IconButton(
              onPressed: _hideErrorBanner,
              icon: const Icon(Icons.close, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}
