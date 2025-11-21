import 'dart:async'; // Timer
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart'; // HapticFeedback
import 'package:flutter/semantics.dart'; // SemanticsService
import 'home_page.dart';
import 'reminders.dart';
import 'contact_info_page.dart';
import 'settings.dart';
import './sos_screen.dart';

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

  // ===== Banner (الهيدر البنفسجي) =====
  String? _currentErrorMessage;
  bool _showErrorBanner = false;
  Timer? _bannerTimer;

  // ===== البانر الأحمر السفلي للأخطاء =====
  String? _bottomErrorMessage;
  bool _showBottomErrorBanner = false;
  Timer? _bottomBannerTimer; // تايمر خاص بالبانر الأحمر

  // تهدئة صوتية للأخطاء أثناء الكتابة
  DateTime? _lastRealtimeSpeakAt;
  final Duration _realtimeSpeakCooldown = const Duration(seconds: 2);

  // ===== TTS =====
  final FlutterTts _flutterTts = FlutterTts();
  bool _ttsInitialized = false;

  // مؤقّت التايبنج
  Timer? _typingTimer;
  final Duration _typingDelay = const Duration(seconds: 1);
  final Map<String, String> _lastValues = {'name': '', 'phone': ''};

  // قيم أصلية للمقارنة عند الحفظ
  String? _initialName;
  String? _initialPhone;

  // علم لتفادي تكرار الفحص عند الدخول
  bool _didInitialPhoneCheck = false;

  // ✅ يتحكم متى نخلي حقل الجوال أحمر + الملاحظة الحمراء
  bool _showPhoneEmptyError = false;

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

  // التكلم بدون await حتى لا يعلّق الـUI
  void _speakNow(String text, {bool force = false}) {
    if (!_ttsInitialized || text.trim().isEmpty || !mounted) return;
    () async {
      try {
        if (force) await _flutterTts.stop();
        await _flutterTts.speak(text);
      } catch (_) {}
    }();
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

  Future<void> _speakPhoneNote() async {
    await _speak(
      "Phone number note. It should start with zero five and be exactly ten digits.",
    );
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
          _initialName = (data['full_name'] ?? '').toString();
          _initialPhone = (data['phone'] ?? '').toString();
          final phoneText = _initialPhone ?? '';

          setState(() {
            _nameController.text = _initialName ?? '';
            _emailController.text = data['email'] ?? user.email ?? '';
            _phoneController.text = phoneText;
            // ✅ من البداية: لو الرقم فاضي نخلي الفيلد أحمر + الملاحظة
            _showPhoneEmptyError = phoneText.trim().isEmpty;
          });

          // 1) تعريف الصفحة
          await _speakWelcome();
          // 🔁 ديلاي زيادة بين الترحيب وملاحظة الرقم
          await Future.delayed(const Duration(seconds: 1));
          // 2) ملاحظة الرقم
          await _speakPhoneNote();
          // 🔁 ديلاي زيادة قبل فحص الرقم
          await Future.delayed(const Duration(seconds: 1));
          // 3) لو الرقم فاضي يطلع مسج النقص
          await _checkPhoneOnEnter();
        } else {
          setState(() {
            _showPhoneEmptyError = _phoneController.text.trim().isEmpty;
          });
          await _speakWelcome();
          await Future.delayed(const Duration(seconds: 1));
          await _speakPhoneNote();
          await Future.delayed(const Duration(seconds: 1));
          await _checkPhoneOnEnter();
        }
      } catch (_) {
        setState(() {
          _showPhoneEmptyError = _phoneController.text.trim().isEmpty;
        });
        await _speakWelcome();
        await Future.delayed(const Duration(seconds: 1));
        await _speakPhoneNote();
        await Future.delayed(const Duration(seconds: 1));
        await _checkPhoneOnEnter();
      }
    } else {
      setState(() {
        _showPhoneEmptyError = _phoneController.text.trim().isEmpty;
      });
      await _speakWelcome();
      await Future.delayed(const Duration(seconds: 1));
      await _speakPhoneNote();
      await Future.delayed(const Duration(seconds: 1));
      await _checkPhoneOnEnter();
    }
  }

  Future<void> _checkPhoneOnEnter() async {
    if (_didInitialPhoneCheck) return;
    _didInitialPhoneCheck = true;

    final phone = _phoneController.text.trim();

    // ✅ أي وقت نفحص فيه، نحدّث الفلاغ
    if (mounted) {
      setState(() {
        _showPhoneEmptyError = phone.isEmpty;
      });
    }

    if (phone.isEmpty && mounted) {
      FocusScope.of(context).unfocus();

      await Future.delayed(const Duration(milliseconds: 200));
      _showErrorWithSoundAndBanner(
        "Your mobile number is missing\nPlease enter your phone number",
        autoHide: true,
        hideAfter: const Duration(seconds: 8),
        speak: false,
      );
      _speakForce(
        "Your mobile number is missing. Please fill in your phone number. It should start with zero five and be exactly ten digits",
      );
      HapticFeedback.mediumImpact();
      SemanticsService.announce("Phone number is required", TextDirection.ltr);
    }
  }

  @override
  void deactivate() {
    _stopSpeech();
    _bannerTimer?.cancel();
    _bottomBannerTimer?.cancel();
    if (mounted) {
      _showErrorBanner = false;
      _currentErrorMessage = null;
      _showBottomErrorBanner = false;
      _bottomErrorMessage = null;
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _bannerTimer?.cancel();
    _bottomBannerTimer?.cancel();
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

  void _showErrorWithSoundAndBanner(
    String msg, {
    bool autoHide = true,
    Duration hideAfter = const Duration(seconds: 5),
    bool speak = true,
  }) {
    setState(() {
      _currentErrorMessage = msg;
      _showErrorBanner = true;
    });

    if (speak) {
      SemanticsService.announce(msg, TextDirection.ltr);
      _speakForce("Error: $msg");
      HapticFeedback.heavyImpact();
    }

    _bannerTimer?.cancel();
    if (autoHide) {
      _bannerTimer = Timer(hideAfter, () {
        if (!mounted) return;
        setState(() {
          _showErrorBanner = false;
          _currentErrorMessage = null;
        });
      });
    }
  }

  void _hideErrorBanner() async {
    await _stopSpeech();
    _bannerTimer?.cancel();
    setState(() {
      _showErrorBanner = false;
      _currentErrorMessage = null;
    });
  }

  // 🟥 بانر أخطاء أحمر في أسفل الصفحة (زي signup)
  void _showBottomError(String msg, {bool speak = true}) async {
    _bottomBannerTimer?.cancel();

    setState(() {
      _bottomErrorMessage = msg;
      _showBottomErrorBanner = true;
    });

    if (speak) {
      SemanticsService.announce(msg, TextDirection.ltr);
      await _speakForce("Error: $msg");
      HapticFeedback.heavyImpact();
    }

    _bottomBannerTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        _showBottomErrorBanner = false;
        _bottomErrorMessage = null;
      });
    });
  }

  void _hideBottomErrorBanner() async {
    await _stopSpeech();
    _bottomBannerTimer?.cancel();
    setState(() {
      _showBottomErrorBanner = false;
      _bottomErrorMessage = null;
    });
    _speak("Error message closed");
  }

  // يجمع كل الأخطاء ويعرضها في البانر الأحمر + يقرأها واحدة واحدة
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

    _showBottomError(msg, speak: false);

    await _stopSpeech();

    int errorCount = 0;
    if (nameErr != null) errorCount++;
    if (phoneSummary != null) errorCount++;

    if (errorCount > 0) {
      await _speak("Found $errorCount error${errorCount > 1 ? 's' : ''}.");
    }

    if (nameErr != null) {
      await _speak("Name: $nameErr");
    }

    if (phoneSummary != null) {
      if (phoneList.isEmpty) {
        await _speak("Mobile number: $phoneSummary");
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

    // ✅ هنا التغيير المهم: نحدّث حالة فضاوة الرقم طول الوقت
    if (fieldName == 'phone') {
      setState(() {
        _showPhoneEmptyError = value.trim().isEmpty;
      });
    }

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
      _showBottomError(err, speak: false);

      final now = DateTime.now();
      final allowSpeak =
          _lastRealtimeSpeakAt == null ||
          now.difference(_lastRealtimeSpeakAt!) >= _realtimeSpeakCooldown;

      if (allowSpeak) {
        _speakForce("Error. $err");
        _lastRealtimeSpeakAt = now;
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_noChangesMade()) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        HapticFeedback.selectionClick();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No changes to save',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            backgroundColor: Color(0xFF1F1F1F),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
      _speakNow("No changes made to your profile", force: true);
      return;
    }

    final ok = await _validateAllAndAnnounce();
    if (!ok) return;

    _speakNow(
      "Are you sure you want to save changes? Buttons: Confirm on the top, Cancel at the bottom",
      force: true,
    );

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
                height: 75,
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
                      'Confirm',
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
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                height: 65,
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
                        fontWeight: FontWeight.w900,
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
      _speakNow("Saving... please wait", force: true);
      setState(() => _isUploading = true);

      final user = _auth.currentUser;
      if (user != null) {
        try {
          final userData = {
            'email': _emailController.text.trim(),
            'full_name': _nameController.text.trim(),
            'phone': _phoneController.text.trim(),
          };

          await _firestore.collection('users').doc(user.uid).update(userData);

          setState(() {
            _initialName = _nameController.text.trim();
            _initialPhone = _phoneController.text.trim();
            _isUploading = false;
          });

          if (mounted) {
            FocusScope.of(context).unfocus();

            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: Colors.green,
                  elevation: 16,
                  margin: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  duration: const Duration(seconds: 2),
                  content: SizedBox(
                    height: 40,
                    child: Row(
                      children: const [
                        Icon(Icons.check_circle, color: Colors.white, size: 26),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your changes have been saved successfully',
                            style: TextStyle(
                              fontSize: 16,
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

          await _stopSpeech();
          _speakForce("Your changes have been saved successfully.");
        } catch (e) {
          if (mounted) {
            setState(() => _isUploading = false);
          }
          await _stopSpeech();
          _showBottomError(
            "Failed to save changes. Please try again.",
            speak: true,
          );
        }
      }
    } else if (confirm == false) {
      _speakNow("Changes cancelled.", force: true);
    }
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  InputDecoration _buildInputDecoration(String label, {bool isError = false}) {
    final Color borderColor = isError
        ? Colors.red.shade600
        : lightPurple; // لون البوردر العادي
    final Color focusedColor = isError
        ? Colors.red.shade700
        : vibrantPurple; // مع الفوكس

    return InputDecoration(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: focusedColor, width: 3),
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
        await _stopSpeech();
        _bannerTimer?.cancel();
        _bottomBannerTimer?.cancel();
        if (mounted) {
          _showErrorBanner = false;
          _currentErrorMessage = null;
          _showBottomErrorBanner = false;
          _bottomErrorMessage = null;
        }
        return true;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false, // يثبّت الفوتر حتى مع الكيبورد
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
                        const SizedBox(height: 20),
                        _buildSaveButton(),
                        const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _buildTopOverlayBanner(),
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildFloatingBottomNav(),
            ),
            Positioned(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 0,
              right: 0,
              child: _buildBottomErrorBanner(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(25, 85, 25, 25),
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
          const SizedBox(width: 20),
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
        padding: const EdgeInsets.all(25),
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
    final bool isPhone = label == "Phone Number";

    // ✅ البوردر الأحمر للرقم بس إذا فاضي
    final bool isPhoneEmptyError = isPhone && _showPhoneEmptyError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 19, color: vibrantPurple),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 17,
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
              decoration: _buildInputDecoration(
                label,
                isError: isPhoneEmptyError,
              ),
              style: TextStyle(
                fontSize: 16,
                color: deepPurple,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),

        // ✅ الملاحظة تحت الفيلد تبان بس إذا الرقم فاضي
        if (isPhone && _showPhoneEmptyError)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'It should start with 05 and be 10 digits',
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w800,
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
        height: 65,
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
                  _speak("Save changes");
                  _saveProfile();
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: _isUploading
                ? Row(
                    key: const ValueKey('saving'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        "Saving…",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  )
                : Row(
                    key: const ValueKey('normal'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.save_outlined, color: Colors.white, size: 23),
                      SizedBox(width: 10),
                      Text(
                        "Save Changes",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopOverlayBanner() {
    return IgnorePointer(
      ignoring: !_showErrorBanner,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        offset: _showErrorBanner ? Offset.zero : const Offset(0, -1),
        child: Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 80, 20, 14),
              color: Colors.transparent,
              child: Semantics(
                liveRegion: true,
                label: 'Important message',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 22,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [vibrantPurple, primaryPurple],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: vibrantPurple.withOpacity(0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.white,
                        size: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _currentErrorMessage ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.45,
                          ),
                          softWrap: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Semantics(
                        label: 'Close message',
                        button: true,
                        hint: 'Double tap to close',
                        child: InkWell(
                          onTap: _hideErrorBanner,
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 23,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomErrorBanner() {
    if (!_showBottomErrorBanner || _bottomErrorMessage == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFD32F2F),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _bottomErrorMessage!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    softWrap: true,
                  ),
                ),
              ),
            ),
          ),
          Semantics(
            label: 'Close error message',
            button: true,
            hint: 'Double tap to close error message',
            child: IconButton(
              onPressed: _hideBottomErrorBanner,
              icon: const Icon(Icons.close, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }

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
                      onTap: () {
                        _speak('Contact, Store and manage emergency contacts');
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
