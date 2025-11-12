import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'home_page.dart';
import 'login_screen.dart';
import '../services/google_signin_handler.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with TickerProviderStateMixin, RouteAware {
  // Form + controllers
  final _formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  // UI state
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _showVerificationScreen = false;
  bool _emailVerified = false;

  // timers
  Timer? _checkTimer;
  Timer? _resendCooldownTimer;
  int _checkCount = 0;
  int _resendCooldown = 0;
  bool _canResend = true;

  // error banner
  String? _currentErrorMessage;
  bool _showErrorBanner = false;

  // typing/throttle
  Timer? _typingTimer;
  final Duration _typingDelay = const Duration(seconds: 2);
  final Map<String, String> _lastValues = {
    'name': '',
    'email': '',
    'phone': '',
    'password': '',
    'confirmPassword': '',
  };

  // Animations
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // TTS
  late FlutterTts _flutterTts;
  bool _ttsInitialized = false;

  // إلغاء فوري لأي قراءة + تتبع حالة النطق
  int _speechGen = 0;
  bool _isSpeaking = false;

  void _cancelAllSpeech({bool cancelTypingTimer = false}) {
    _speechGen++; // يبطل أي تسلسل نطق سابق
    try {
      _flutterTts.stop();
    } catch (_) {}
    _isSpeaking = false;
    if (cancelTypingTimer) {
      _typingTimer?.cancel();
    }
  }

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initTTS();
    _animationController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);

    _checkTimer?.cancel();
    _resendCooldownTimer?.cancel();
    _typingTimer?.cancel();

    _animationController.dispose();

    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();

    _cancelAllSpeech(cancelTypingTimer: true);
    super.dispose();
  }

  // RouteAware
  @override
  void didPush() {
    _speakWelcome();
  }

  @override
  void didPushNext() {
    _cancelAllSpeech(cancelTypingTimer: true);
  }

  @override
  void didPopNext() {
    _speakWelcome();
  }

  Future<void> _initTTS() async {
    _flutterTts = FlutterTts();
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true);

    // تتبع بداية/نهاية/إلغاء النطق
    try {
      _flutterTts.setStartHandler(() {
        _isSpeaking = true;
      });
      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
      });
      _flutterTts.setCancelHandler(() {
        _isSpeaking = false;
      });
      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
      });
    } catch (_) {
      // بعض الإصدارات قد لا تدعم جميع الـ handlers
    }

    setState(() => _ttsInitialized = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakWelcome());
  }

  Future<void> _speak(String text, {bool interrupt = true}) async {
    if (!_ttsInitialized || text.trim().isEmpty) return;
    if (interrupt) {
      try {
        await _flutterTts.stop();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 60));
    }
    await _flutterTts.speak(text);
  }

  void _speakWelcome() {
    _speak(
      "Create Account page. Please fill in your details to create a new account.",
      interrupt: true,
    );
  }

  Future<void> _speakForce(String text) async {
    if (!_ttsInitialized || text.trim().isEmpty) return;
    try {
      await _flutterTts.stop();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 60));
    await _flutterTts.speak(text);
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutBack,
          ),
        );
  }

  // لا نخفي الرسالة إلا بعد انتهاء القراءة (إن كان autoHide=true)
  Future<void> _autoHideBannerAfter(Duration d) async {
    await Future.delayed(d);
    // انتظر انتهاء أي قراءة حالية
    while (_isSpeaking) {
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
    }
    if (!mounted) return;
    setState(() {
      _showErrorBanner = false;
      _currentErrorMessage = null;
    });
  }

  void _showRealTimeError(String errorMessage) {
    // أي فاليديشن لحظي يلغي القراءة الحالية ثم يعرض رسالة الحقل
    _cancelAllSpeech();
    _showErrorWithSoundAndBanner(errorMessage, autoHide: true);
  }

  void _showErrorWithSoundAndBanner(
    String errorMessage, {
    bool autoHide = true,
  }) {
    setState(() {
      _currentErrorMessage = errorMessage;
      _showErrorBanner = true;
    });

    SemanticsService.announce(errorMessage, TextDirection.ltr);
    _speakForce("Error: $errorMessage");
    HapticFeedback.heavyImpact();

    // لا نخفي الرسالة إلا بعد ما يخلص TTS
    if (autoHide) {
      _autoHideBannerAfter(const Duration(seconds: 10));
    }
  }

  void _hideErrorBanner() {
    _cancelAllSpeech(); // أيضًا يوقف أي قراءة قائمة
    setState(() {
      _showErrorBanner = false;
      _currentErrorMessage = null;
    });
    _speak("Error message closed");
  }

  void _showSuccessWithSpeech(String successMessage) {
    _speakForce("Success: $successMessage");
    HapticFeedback.lightImpact();
    SemanticsService.announce(successMessage, TextDirection.ltr);
  }

  void _onButtonTap(String buttonName) {
    _speak(buttonName);
    HapticFeedback.selectionClick();
  }

  void _onFieldChanged(String fieldName, String value) {
    _typingTimer?.cancel();
    if (_lastValues[fieldName] == value) return;

    _lastValues[fieldName] = value;
    _typingTimer = Timer(_typingDelay, () {
      _validateFieldInRealTime(fieldName, value);
    });
  }

  void _onFieldFocusChanged(String fieldName, bool hasFocus) {
    if (hasFocus && _showErrorBanner) {
      // لا نخفي فورًا، إلا إذا تبين أن المستخدم يعدل ومحتاج يسمع خطأ الحقل
    }
  }

  void _validateFieldInRealTime(String fieldName, String value) {
    if (!mounted) return;
    String? errorMessage;

    switch (fieldName) {
      case 'name':
        errorMessage = _validateName(value);
        break;
      case 'email':
        errorMessage = _validateEmail(value);
        break;
      case 'phone':
        errorMessage = _validatePhone(value);
        break;
      case 'password':
        final missing = _getMissingPasswordRequirements(value);
        if (missing.isNotEmpty && value.isNotEmpty) {
          // نعرض كل المتطلبات المفقودة دفعة واحدة
          errorMessage = "Password missing: ${missing.join(', ')}";
        }
        break;
      case 'confirmPassword':
        if (value.isNotEmpty && value != passwordController.text) {
          errorMessage = "Passwords do not match";
        }
        break;
    }

    if (errorMessage != null && value.isNotEmpty) {
      // ألغِ قراءة قائمة (مثلاً قائمة الأخطاء الطويلة) واقرأ خطأ هذا الحقل الآن
      _showRealTimeError(errorMessage);
    } else {
      // لو أصلح الخطأ، اسكتي ولا تعرضي شيء
    }
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) return "Name is required";
    if (value.trim().length < 2) return "Name must be at least 2 characters";
    if (RegExp(r'[0-9]').hasMatch(value)) {
      return "Name should not contain numbers";
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return "Email is required";

    final emailRegex = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return "Please enter a valid email address, such as example@domain.com";
    }

    final allowedDomains = {
      'gmail.com': 'Gmail',
      'outlook.com': 'Outlook',
      'hotmail.com': 'Hotmail',
      'yahoo.com': 'Yahoo',
    };

    final parts = value.trim().split('@');
    if (parts.length != 2) return "Invalid email format";
    final domain = parts[1].toLowerCase();
    if (!allowedDomains.containsKey(domain)) {
      return "Only ${allowedDomains.values.join(', ')} emails are allowed";
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "Mobile number is required";
    }
    final cleaned = value.trim().replaceAll(RegExp(r'[-\s()]'), '');
    if (!cleaned.startsWith('05')) return "Mobile number must start with 05";
    if (cleaned.length != 10) return "Mobile number must be exactly 10 digits";
    if (!RegExp(r'^[0-9]+$').hasMatch(cleaned)) {
      return "Mobile number should contain only numbers";
    }
    return null;
  }

  List<String> _getMissingPasswordRequirements(String password) {
    final missing = <String>[];
    if (password.length < 8) missing.add('At least 8 characters long');
    if (!password.contains(RegExp(r'[A-Z]')))
      missing.add('One uppercase letter (A-Z)');
    if (!password.contains(RegExp(r'[a-z]')))
      missing.add('One lowercase letter (a-z)');
    if (!password.contains(RegExp(r'[0-9]'))) missing.add('One number (0-9)');
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      missing.add('One special character');
    }
    return missing;
  }

  String? _validatePassword(String password) {
    final errors = _getMissingPasswordRequirements(password);
    if (errors.isEmpty) return null;
    return errors.length == 1
        ? "Password missing: ${errors.first}"
        : "Password missing ${errors.length} requirements";
  }

  String _getPasswordStrength(String password) {
    if (password.isEmpty) return 'Empty';
    if (password.length < 8) return 'Too Short';
    var score = 0;
    if (password.contains(RegExp(r'[A-Z]'))) score++;
    if (password.contains(RegExp(r'[a-z]'))) score++;
    if (password.contains(RegExp(r'[0-9]'))) score++;
    if (score == 3 && password.length >= 8) return 'Strong';
    if (score >= 2) return 'Medium';
    if (score >= 1) return 'Weak';
    return 'Very Weak';
  }

  Color _getPasswordStrengthColor(String password) {
    switch (_getPasswordStrength(password)) {
      case 'Strong':
        return Colors.green;
      case 'Medium':
        return Colors.orange;
      case 'Weak':
      case 'Very Weak':
        return Colors.red;
      case 'Too Short':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  Map<String, dynamic> _validateAllFields() {
    final errors = <String, dynamic>{};
    final nameErr = _validateName(nameController.text);
    if (nameErr != null) errors['name'] = nameErr;

    final emailErr = _validateEmail(emailController.text);
    if (emailErr != null) errors['email'] = emailErr;

    final phoneErr = _validatePhone(phoneController.text);
    if (phoneErr != null) errors['phone'] = phoneErr;

    final pwdErrors = _getMissingPasswordRequirements(passwordController.text);
    if (pwdErrors.isNotEmpty) errors['password'] = pwdErrors;

    if (confirmPasswordController.text.isEmpty) {
      errors['confirmPassword'] = "Please confirm your password";
    } else if (confirmPasswordController.text != passwordController.text) {
      errors['confirmPassword'] = "Passwords do not match";
    }
    return errors;
  }

  Future<void> _announceAllErrors(Map<String, dynamic> errors) async {
    if (errors.isEmpty) return;

    // أوقفي أي قراءة حالية
    _cancelAllSpeech();
    final gen = _speechGen;

    // رسالة متعددة الأسطر + نقاط فرعية للباسورد
    String general = "Please fix the following errors:\n\n";
    if (errors.containsKey('name')) {
      general += "• Name: ${errors['name']}\n\n";
    }
    if (errors.containsKey('email')) {
      general += "• Email: ${errors['email']}\n\n";
    }
    if (errors.containsKey('phone')) {
      general += "• Mobile Number: ${errors['phone']}\n\n";
    }
    if (errors.containsKey('confirmPassword')) {
      general += "• Confirm Password: ${errors['confirmPassword']}\n\n";
    }
    if (errors.containsKey('password')) {
      final list = errors['password'] as List<String>;
      general += "• Password:\n";
      for (final item in list) {
        general += "   - $item\n";
      }
      general += "\n";
    }

    // نعرض الشريط بدون إخفاء تلقائي؛ سننهيه يدويًا بعد القراءة أو عند إغلاق المستخدم
    setState(() {
      _currentErrorMessage = general.trimRight();
      _showErrorBanner = true;
    });

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted || gen != _speechGen) return;

    await _speakForce("Found ${errors.length} errors");
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted || gen != _speechGen) return;

    if (errors.containsKey('name')) {
      await _speak("Name: ${errors['name']}");
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted || gen != _speechGen) return;
    }
    if (errors.containsKey('email')) {
      await _speak("Email: ${errors['email']}");
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted || gen != _speechGen) return;
    }
    if (errors.containsKey('phone')) {
      await _speak("Mobile Number: ${errors['phone']}");
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted || gen != _speechGen) return;
    }
    if (errors.containsKey('confirmPassword')) {
      await _speak("Confirm Password: ${errors['confirmPassword']}");
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted || gen != _speechGen) return;
    }
    if (errors.containsKey('password')) {
      await _speak("Password issues:");
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted || gen != _speechGen) return;

      final list = errors['password'] as List<String>;
      for (final item in list) {
        await _speak(item);
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted || gen != _speechGen) return;
      }
    }

    await _speak("Please fix these errors and try again.");
    // بعد انتهاء القراءة: نترك الشريط ظاهرًا لراحة المستخدم، أو أغلقيه يدويًا من X
    // لو حابة إغلاق تلقائي بعد القراءة، فعّلي السطرين التاليين:
    // if (mounted && gen == _speechGen) {
    //   _autoHideBannerAfter(const Duration(seconds: 1));
    // }
  }

  void _registerUser() async {
    _speak("Starting registration process. Please wait...");
    final fieldErrors = _validateAllFields();
    if (fieldErrors.isNotEmpty) {
      await _announceAllErrors(fieldErrors);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final user = cred.user;
      if (user == null) throw Exception("Failed to create user");

      var emailSent = false;
      try {
        final callable = FirebaseFunctions.instance.httpsCallable(
          'sendWelcomeEmail',
        );
        await callable.call({
          'email': emailController.text.trim(),
          'displayName': nameController.text.trim(),
        });
        emailSent = true;
      } catch (_) {
        try {
          await user.sendEmailVerification();
          emailSent = true;
        } catch (_) {
          emailSent = false;
        }
      }

      if (!emailSent) {
        await user.delete();
        throw FirebaseAuthException(
          code: 'email-send-failed',
          message: 'Failed to send verification email. Please try again later.',
        );
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'full_name': nameController.text.trim(),
        'email': emailController.text.trim(),
        'phone': phoneController.text.trim(),
        'created_at': Timestamp.now(),
        'profile_completed': false,
        'email_verified': false,
      });

      setState(() {
        _showVerificationScreen = true;
        _isLoading = false;
      });

      _cancelAllSpeech(cancelTypingTimer: true);

      _startCheckingVerification();

      _showSuccessWithSpeech(
        "Account created successfully! Please check your inbox and spam folder for the verification link. We've sent an email to ${emailController.text}.",
      );
    } on FirebaseAuthException catch (e) {
      var error = "Registration failed";
      if (e.code == 'too-many-requests' ||
          (e.message?.contains('blocked') ?? false)) {
        error =
            "Too many attempts from this device. Please wait 15–30 minutes and try again, or use a different network.";
      } else if (e.code == 'email-send-failed') {
        error =
            e.message ??
            "Failed to send verification email. Please try again later.";
      } else {
        switch (e.code) {
          case 'email-already-in-use':
            error = "This email is already registered. Please login instead.";
            break;
          case 'invalid-email':
            error = "Invalid email address";
            break;
          case 'weak-password':
            error = "Password too weak (min 6 characters)";
            break;
          case 'operation-not-allowed':
            error =
                "Registration is temporarily disabled. Please try again later.";
            break;
          default:
            error = e.message ?? "Registration failed";
        }
      }
      _showErrorWithSoundAndBanner(error); // autoHide مع انتظار انتهاء القراءة
    } catch (e) {
      _showErrorWithSoundAndBanner(
        "Unexpected error occurred. Please try again.",
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startCheckingVerification() {
    _checkTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _checkEmailVerification();
      _checkCount++;
      if (_checkCount >= 100) {
        timer.cancel();
        if (!mounted) return;
        _showErrorWithSoundAndBanner(
          "Verification timeout. Please resend the email.",
        );
      }
    });
  }

  Future<void> _checkEmailVerification() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await user.reload();
      final updated = FirebaseAuth.instance.currentUser;

      if (updated?.emailVerified == true && !_emailVerified) {
        setState(() => _emailVerified = true);
        _checkTimer?.cancel();

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'email_verified': true, 'verified_at': Timestamp.now()});

        const storage = FlutterSecureStorage();
        await storage.write(key: 'isLoggedIn', value: 'true');
        await storage.write(
          key: 'userEmail',
          value: emailController.text.trim(),
        );

        _showSuccessWithSpeech(
          "Email verified successfully! Welcome ${nameController.text}. Redirecting to home page...",
        );
        HapticFeedback.heavyImpact();

        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;

        _cancelAllSpeech(cancelTypingTimer: true);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    } catch (_) {}
  }

  void _startResendCooldown() {
    setState(() {
      _canResend = false;
      _resendCooldown = 60;
    });

    _resendCooldownTimer?.cancel();
    _resendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        setState(() => _canResend = true);
        _speak("You can now resend the verification email");
        timer.cancel();
      }
    });
  }

  Future<void> _resendVerificationEmail() async {
    if (!_canResend) {
      _speak("Please wait $_resendCooldown seconds before resending email");
      return;
    }

    try {
      setState(() => _isLoading = true);
      _speak("Sending new verification email...");
      final user = FirebaseAuth.instance.currentUser;
      await user?.sendEmailVerification();

      _startResendCooldown();
      _showSuccessWithSpeech(
        "New verification email sent successfully! Please check your inbox and spam folder.",
      );
      HapticFeedback.mediumImpact();
    } catch (e) {
      var msg = "Failed to resend email";
      if (e is FirebaseAuthException && e.code == 'too-many-requests') {
        msg = "Too many requests. Please wait and try again.";
      }
      _showErrorWithSoundAndBanner(msg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signUpWithGoogle() async {
    try {
      _speak("Starting Google sign up process. Please wait.");
      setState(() => _isLoading = true);

      try {
        await GoogleSignInHandler.signInWithGoogle(context);
        await Future.delayed(const Duration(seconds: 2));
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          _showSuccessWithSpeech("Google sign up completed successfully!");
        } else {
          throw Exception("User not created");
        }
      } catch (_) {
        _showErrorWithSoundAndBanner(
          "Google sign-up canceled. Please try again.",
        );
        return;
      }
    } catch (_) {
      _showErrorWithSoundAndBanner("Google sign-up failed. Please try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // =================== UI ===================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/backk.jpg'),
                fit: BoxFit.cover,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.1),
                    Colors.black.withOpacity(0.3),
                  ],
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: _showVerificationScreen
                    ? _buildVerificationWaitingScreen()
                    : _buildSignupForm(),
              ),
            ),
          ),

          // Error banner
          Positioned(bottom: 0, left: 0, right: 0, child: _buildErrorBanner()),
        ],
      ),
    );
  }

  Widget _buildSignupForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            const SizedBox(height: 20),
            Semantics(
              header: true,
              label: 'Create Account page',
              child: Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.person_add_rounded,
                      size: 60,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Create Account",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "Join us and start your journey",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withOpacity(0.8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Name
            Semantics(
              label: 'Full name input field',
              textField: true,
              hint: 'Enter your full name without numbers',
              child: _buildEnhancedTextFormField(
                controller: nameController,
                hint: "Name",
                icon: Icons.person_outline,
                validator: _validateName,
                fieldName: 'name',
              ),
            ),
            const SizedBox(height: 20),

            // Email
            Semantics(
              label: 'Email address input field',
              textField: true,
              hint: 'We will send a verification link to this email',
              child: _buildEnhancedTextFormField(
                controller: emailController,
                hint: "Email Address",
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: _validateEmail,
                fieldName: 'email',
              ),
            ),
            const SizedBox(height: 20),

            // Phone
            Semantics(
              label: 'Mobile number input field',
              textField: true,
              hint: 'Enter your 10-digit mobile number starting with 05',
              child: _buildEnhancedTextFormField(
                controller: phoneController,
                hint: "Mobile Number (05XXXXXXXX)",
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                validator: _validatePhone,
                fieldName: 'phone',
              ),
            ),
            const SizedBox(height: 20),

            // Password
            Semantics(
              label: 'Password input field',
              textField: true,
              obscured: true,
              hint:
                  'Create a strong password with uppercase, lowercase, numbers and special characters',
              child: _buildPasswordField(
                controller: passwordController,
                hint: "Password",
                obscure: _obscurePassword,
                onToggle: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return "Password is required";
                  }
                  return _validatePassword(v.trim());
                },
                fieldName: 'password',
              ),
            ),

            // Strength + requirements
            if (passwordController.text.isNotEmpty) ...[
              const SizedBox(height: 12),

              // Strength
              Semantics(
                label:
                    'Password strength: ${_getPasswordStrength(passwordController.text)}',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.security,
                        size: 20,
                        color: _getPasswordStrengthColor(
                          passwordController.text,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Password Strength: ${_getPasswordStrength(passwordController.text)}",
                        style: TextStyle(
                          color: _getPasswordStrengthColor(
                            passwordController.text,
                          ),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Requirements list
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF6B1D73).withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.checklist_rtl,
                          color: Color(0xFF6B1D73),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Password Requirements:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF6B1D73),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildPasswordRequirement(
                      'At least 8 characters',
                      passwordController.text.length >= 8,
                    ),
                    _buildPasswordRequirement(
                      'Uppercase letter (A-Z)',
                      passwordController.text.contains(RegExp(r'[A-Z]')),
                    ),
                    _buildPasswordRequirement(
                      'Lowercase letter (a-z)',
                      passwordController.text.contains(RegExp(r'[a-z]')),
                    ),
                    _buildPasswordRequirement(
                      'Number (0-9)',
                      passwordController.text.contains(RegExp(r'[0-9]')),
                    ),
                    _buildPasswordRequirement(
                      'Special character',
                      passwordController.text.contains(
                        RegExp(r'[!@#$%^&*(),.?":{}|<>]'),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Confirm password
            Semantics(
              label: 'Confirm password input field',
              textField: true,
              obscured: true,
              hint: 'Re-enter your password to confirm',
              child: _buildPasswordField(
                controller: confirmPasswordController,
                hint: "Confirm Password",
                obscure: _obscureConfirmPassword,
                onToggle: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return "Please confirm your password";
                  }
                  if (v != passwordController.text) {
                    return "Passwords do not match";
                  }
                  return null;
                },
                fieldName: 'confirmPassword',
              ),
            ),

            const SizedBox(height: 24),

            // Create Account button
            Semantics(
              label: 'Create account button',
              hint: 'Double tap to create your account',
              button: true,
              child: SizedBox(
                width: double.infinity,
                height: 59,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          _onButtonTap("Create account");
                          _registerUser();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B1D73),
                    foregroundColor: Colors.white,
                    elevation: 12,
                    shadowColor: const Color(0xFF6B1D73).withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 27,
                          width: 27,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "Create Account",
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Divider
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    "OR",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 1,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Google sign up
            Semantics(
              label: 'Sign up with Google button',
              button: true,
              hint: 'Double tap to sign up using your Google account',
              child: SizedBox(
                width: double.infinity,
                height: 59,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            _onButtonTap("Sign up with Google, Please wait");
                            _signUpWithGoogle();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.g_mobiledata, size: 30),
                        SizedBox(width: 12),
                        Text(
                          "Continue with Google",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Already have account -> Login
            Semantics(
              label: 'Already have an account, Log in button',
              button: true,
              hint: 'Double tap to go to login page',
              child: GestureDetector(
                onTap: () async {
                  _onButtonTap("Log in");
                  _cancelAllSpeech(cancelTypingTimer: true);
                  await Future.delayed(const Duration(milliseconds: 300));
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: Container(
                  height: 59,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Already have an account? ",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Text(
                        "Log In",
                        style: TextStyle(
                          color: Color.fromARGB(255, 248, 183, 255),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationWaitingScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const SizedBox(height: 60),
          Semantics(
            header: true,
            label: 'Email Verification page',
            child: Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _emailVerified
                        ? Icons.check_circle
                        : Icons.mark_email_unread_outlined,
                    size: 80,
                    color: _emailVerified ? Colors.green : Colors.white,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _emailVerified ? "Email Verified!" : "Check Your Email",
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (_emailVerified)
                    Text(
                      "Redirecting to home...",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.9),
                      ),
                      textAlign: TextAlign.center,
                    )
                  else
                    Column(
                      children: [
                        Text(
                          "We sent an email to",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.9),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          emailController.text,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 25),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(
                              255,
                              184,
                              215,
                              240,
                            ).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color.fromARGB(
                                255,
                                126,
                                192,
                                247,
                              ).withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    "IMPORTANT!",
                                    style: TextStyle(
                                      fontSize: 19,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "Check your SPAM/JUNK folder!",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.95),
                                  height: 1.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),

          if (!_emailVerified) ...[
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color.fromARGB(
                  255,
                  184,
                  215,
                  240,
                ).withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color.fromARGB(
                    255,
                    126,
                    192,
                    247,
                  ).withOpacity(0.3),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: const [
                      Icon(Icons.info_outline, color: Colors.white, size: 26),
                      SizedBox(width: 12),
                      Text(
                        "Next Steps",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "1. Open your email app\n"
                    "2. Check INBOX and SPAM folder\n"
                    "3. Find our verification email\n"
                    "4. Click the verification link\n"
                    "5. Come back here automatically\n\n"
                    "We're checking automatically!",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 17,
                      height: 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Resend email
            Semantics(
              label: _canResend
                  ? 'Resend verification email button'
                  : 'Resend available in $_resendCooldown seconds',
              button: true,
              hint: _canResend
                  ? 'Double tap to send verification email again'
                  : '',
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: (_isLoading || !_canResend)
                      ? null
                      : () {
                          _onButtonTap("Resend verification email");
                          _resendVerificationEmail();
                        },
                  icon: Icon(
                    _canResend ? Icons.refresh : Icons.timer_outlined,
                    size: 24,
                  ),
                  label: Text(
                    _canResend
                        ? "Resend Verification Email"
                        : "Resend in $_resendCooldown seconds",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canResend
                        ? Colors.white.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Back to login
            Semantics(
              label: 'Back to login button',
              button: true,
              hint: 'Double tap to go back to login page',
              child: TextButton(
                onPressed: () {
                  _onButtonTap("Back to login");
                  _checkTimer?.cancel();
                  _resendCooldownTimer?.cancel();
                  _cancelAllSpeech(cancelTypingTimer: true);
                  Navigator.pop(context);
                },
                child: const Text(
                  "Back to Login",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPasswordRequirement(String text, bool isMet) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: isMet ? Colors.green : Colors.red.shade300,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: isMet ? Colors.green.shade700 : Colors.grey.shade600,
                fontWeight: isMet ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedTextFormField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    required String fieldName,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        validator: validator,
        onChanged: (v) {
          setState(() {});
          _onFieldChanged(fieldName, v);
        },
        onTap: () => _onFieldFocusChanged(fieldName, true),
        style: const TextStyle(color: Colors.black, fontSize: 18),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 18),
          prefixIcon: ExcludeSemantics(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF6B1D73).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: const Color(0xFF6B1D73), size: 24),
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          fillColor: Colors.white.withOpacity(0.95),
          filled: true,
          contentPadding: const EdgeInsets.all(24),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
    required String fieldName,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        validator: validator,
        onChanged: (v) {
          setState(() {});
          _onFieldChanged(fieldName, v);
        },
        onTap: () => _onFieldFocusChanged(fieldName, true),
        style: const TextStyle(color: Colors.black, fontSize: 18),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 18),
          prefixIcon: ExcludeSemantics(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF6B1D73).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.lock_outline,
                color: Color(0xFF6B1D73),
                size: 24,
              ),
            ),
          ),
          suffixIcon: Semantics(
            label: obscure ? 'Show password' : 'Hide password',
            button: true,
            hint: 'Double tap to toggle password visibility',
            child: IconButton(
              onPressed: () {
                _onButtonTap(obscure ? "Show password" : "Hide password");
                onToggle();
              },
              icon: Icon(
                obscure ? Icons.visibility_off : Icons.visibility,
                color: const Color(0xFF6B1D73),
                size: 24,
              ),
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          fillColor: Colors.white.withOpacity(0.95),
          filled: true,
          contentPadding: const EdgeInsets.all(24),
        ),
      ),
    );
  }

  /// Error banner مع سكرول داخلي ويظل ظاهرًا حتى تنتهي القراءة أو الإغلاق اليدوي.
  Widget _buildErrorBanner() {
    if (!_showErrorBanner || _currentErrorMessage == null) {
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
                    _currentErrorMessage!,
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
              onPressed: _hideErrorBanner,
              icon: const Icon(Icons.close, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}
