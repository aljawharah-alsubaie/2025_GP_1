import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'home_page.dart';
import 'login_screen.dart';
import '../services/google_signin_handler.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _showVerificationScreen = false;
  bool _emailVerified = false;

  Timer? _checkTimer;
  Timer? _resendCooldownTimer;
  int _checkCount = 0;
  int _resendCooldown = 0;
  bool _canResend = true;

  String? _currentErrorMessage;
  bool _showErrorBanner = false;

  late FlutterTts _flutterTts;
  bool _ttsInitialized = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  Timer? _typingTimer;
  final Duration _typingDelay = const Duration(seconds: 2);
  final Map<String, String> _lastValues = {};

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeTTS();
    _animationController.forward();

    _lastValues['name'] = '';
    _lastValues['email'] = '';
    _lastValues['phone'] = '';
    _lastValues['password'] = '';
    _lastValues['confirmPassword'] = '';
  }

  void _initializeTTS() async {
    _flutterTts = FlutterTts();

    // إعدادات الصوت
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    setState(() {
      _ttsInitialized = true;
    });

    _speak(
      "Welcome to Create Account page. Please fill in your details to create a new account.",
    );
  }

  // ✅ دالة التكلم الأساسية
  Future<void> _speak(String text) async {
    if (_ttsInitialized && text.isNotEmpty) {
      await _flutterTts.speak(text);
    }
  }

  // ✅ دالة التكلم مع إيقاف أي كلام سابق
  Future<void> _speakForce(String text) async {
    if (_ttsInitialized) {
      await _flutterTts.stop(); // إيقاف أي كلام سابق
      await Future.delayed(const Duration(milliseconds: 100));
      await _flutterTts.speak(text);
    }
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

  @override
  void dispose() {
    _checkTimer?.cancel();
    _resendCooldownTimer?.cancel();
    _typingTimer?.cancel();
    _animationController.dispose();
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  void _onFieldChanged(String fieldName, String value) {
    _typingTimer?.cancel();

    if (_lastValues[fieldName] != value) {
      _lastValues[fieldName] = value;

      _typingTimer = Timer(_typingDelay, () {
        _validateFieldInRealTime(fieldName, value);
      });
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
        List<String> missingReqs = _getMissingPasswordRequirements(value);
        if (missingReqs.isNotEmpty && value.isNotEmpty) {
          errorMessage = "Password missing: ${missingReqs.join(', ')}";
        }
        break;
      case 'confirmPassword':
        if (value.isNotEmpty && value != passwordController.text) {
          errorMessage = "Passwords do not match";
        }
        break;
    }

    if (errorMessage != null && value.isNotEmpty) {
      _showRealTimeError(errorMessage);
    }
  }

  void _showRealTimeError(String errorMessage) {
    setState(() {
      _currentErrorMessage = errorMessage;
      _showErrorBanner = true;
    });

    SemanticsService.announce(errorMessage, TextDirection.ltr);

    _speakForce("Note: $errorMessage");

    HapticFeedback.mediumImpact();

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _showErrorBanner = false;
          _currentErrorMessage = null;
        });
      }
    });
  }

  void _onFieldFocusChanged(String fieldName, bool hasFocus) {
    if (hasFocus) {
      if (_showErrorBanner) {
        setState(() {
          _showErrorBanner = false;
          _currentErrorMessage = null;
        });
      }
    }
  }

  void _showErrorWithSoundAndBanner(String errorMessage) {
    setState(() {
      _currentErrorMessage = errorMessage;
      _showErrorBanner = true;
    });

    SemanticsService.announce(errorMessage, TextDirection.ltr);

    _speakForce("Error: $errorMessage");

    HapticFeedback.heavyImpact();

    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() {
          _showErrorBanner = false;
          _currentErrorMessage = null;
        });
      }
    });
  }

  void _hideErrorBanner() {
    setState(() {
      _showErrorBanner = false;
      _currentErrorMessage = null;
    });
    // ✅ نطق تأكيد الإغلاق
    _speak("Error message closed");
  }

  // ✅ دالة للتكلم عند النجاح
  void _showSuccessWithSpeech(String successMessage) {
    // ✅ نطق رسالة النجاح
    _speakForce("Success: $successMessage");

    // ✅ اهتزاز خفيف للإشارة إلى النجاح
    HapticFeedback.lightImpact();

    // ✅ الإعلان للقارئ الشاشة
    SemanticsService.announce(successMessage, TextDirection.ltr);
  }

  // ✅ دالة للتكلم عند الضغط على الأزرار
  void _onButtonTap(String buttonName) {
    _speak("$buttonName");
    HapticFeedback.selectionClick();
  }

  // ✅ دالة للتحقق من أي متطلبات الباسوورد غير مستوفاة
  List<String> _getMissingPasswordRequirements(String password) {
    List<String> missingRequirements = [];

    if (password.length < 8) {
      missingRequirements.add('At least 8 characters long');
    }

    if (!password.contains(RegExp(r'[A-Z]'))) {
      missingRequirements.add('One uppercase letter (A-Z)');
    }

    if (!password.contains(RegExp(r'[a-z]'))) {
      missingRequirements.add('One lowercase letter (a-z)');
    }

    if (!password.contains(RegExp(r'[0-9]'))) {
      missingRequirements.add('One number (0-9)');
    }

    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      missingRequirements.add('One special character');
    }

    return missingRequirements;
  }

  // ✅ Password strength validation - strict and mandatory rules
  // ✅ تعديل الدالة لترجع قائمة بجميع الأخطاء
  List<String> _validatePasswordAllErrors(String password) {
    return _getMissingPasswordRequirements(password);
  }

  // ✅ دالة التحقق العادية (للتوافق مع الـ validator)
  String? _validatePassword(String password) {
    List<String> errors = _validatePasswordAllErrors(password);
    if (errors.isEmpty) return null;

    // ✅ ترجع رسالة توضح أن هناك متطلبات ناقصة
    if (errors.length == 1) {
      return "Password missing: ${errors.first}";
    } else {
      return "Password missing ${errors.length} requirements";
    }
  }

  String _getPasswordStrength(String password) {
    if (password.isEmpty) return 'Empty';

    if (password.length < 8) return 'Too Short';

    int strength = 0;

    if (password.contains(RegExp(r'[A-Z]'))) strength++;
    if (password.contains(RegExp(r'[a-z]'))) strength++;
    if (password.contains(RegExp(r'[0-9]'))) strength++;

    // All four conditions must be met
    if (strength == 3 && password.length >= 8) {
      return 'Strong';
    } else if (strength >= 2) {
      return 'Medium';
    } else if (strength >= 1) {
      return 'Weak';
    }

    return 'Very Weak';
  }

  Color _getPasswordStrengthColor(String password) {
    final strength = _getPasswordStrength(password);

    switch (strength) {
      case 'Strong':
        return Colors.green;
      case 'Medium':
        return Colors.orange;
      case 'Weak':
      case 'Very Weak':
        return Colors.red;
      case 'Too Short':
        return Colors.red.shade700;
      default:
        return Colors.grey;
    }
  }

  // ✅ Helper function to display each requirement with checkmark or cross
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

  // ✅ Name validation - no numbers allowed
  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "Full name is required";
    }

    if (value.trim().length < 2) {
      return "Name must be at least 2 characters";
    }

    // Check if name contains numbers
    if (RegExp(r'[0-9]').hasMatch(value)) {
      return "Name should not contain numbers";
    }

    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "Email is required";
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

    if (!emailRegex.hasMatch(value.trim())) {
      return "Please enter a valid email address (such as, example@domain.com)";
    }

    final allowedDomains = {
      'gmail.com': 'Gmail',
      'outlook.com': 'Outlook',
      'hotmail.com': 'Hotmail',
      'yahoo.com': 'Yahoo',
    };

    final emailParts = value.trim().split('@');
    if (emailParts.length != 2) {
      return "Invalid email format";
    }

    final domain = emailParts[1].toLowerCase();

    if (!allowedDomains.containsKey(domain)) {
      return "Only ${allowedDomains.values.join(', ')} emails are allowed";
    }

    return null;
  }

  // ✅ Phone number format validation
  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "Mobile number is required";
    }

    final cleanedPhone = value.trim().replaceAll(RegExp(r'[-\s()]'), '');

    // Check if starts with 05
    if (!cleanedPhone.startsWith('05')) {
      return "Mobile number must start with 05";
    }

    // Check if exactly 10 digits
    if (cleanedPhone.length != 10) {
      return "Mobile number must be exactly 10 digits";
    }

    // Check if contains only numbers
    if (!RegExp(r'^[0-9]+$').hasMatch(cleanedPhone)) {
      return "Mobile number should contain only numbers";
    }

    return null;
  }

  // ✅ دالة جديدة للتحقق من جميع الحقول وإرجاع جميع الأخطاء
  Map<String, dynamic> _validateAllFields() {
    Map<String, dynamic> errors = {};

    // التحقق من الاسم
    String? nameError = _validateName(nameController.text);
    if (nameError != null) {
      errors['name'] = nameError;
    }

    // التحقق من البريد الإلكتروني
    String? emailError = _validateEmail(emailController.text);
    if (emailError != null) {
      errors['email'] = emailError;
    }

    // التحقق من الهاتف
    String? phoneError = _validatePhone(phoneController.text);
    if (phoneError != null) {
      errors['phone'] = phoneError;
    }

    // التحقق من كلمة المرور - الآن ترجع قائمة بجميع الأخطاء
    List<String> passwordErrors = _validatePasswordAllErrors(
      passwordController.text,
    );
    if (passwordErrors.isNotEmpty) {
      errors['password'] = passwordErrors;
    }

    // التحقق من تأكيد كلمة المرور
    if (confirmPasswordController.text.isEmpty) {
      errors['confirmPassword'] = "Please confirm your password";
    } else if (confirmPasswordController.text != passwordController.text) {
      errors['confirmPassword'] = "Passwords do not match";
    }

    return errors;
  }

  // ✅ دالة جديدة لنطق جميع الأخطاء بالترتيب
  void _announceAllErrors(Map<String, dynamic> errors) async {
    if (errors.isEmpty) return;

    // ✅ عرض نفس الرسالة في الشريط الأحمر (ما تتغير)
    String generalErrors = "Please fix the following errors: ";

    if (errors.containsKey('name')) {
      generalErrors += "Full Name: ${errors['name']}. ";
    }
    if (errors.containsKey('email')) {
      generalErrors += "Email: ${errors['email']}. ";
    }
    if (errors.containsKey('phone')) {
      generalErrors += "Mobile Number: ${errors['phone']}. ";
    }
    if (errors.containsKey('confirmPassword')) {
      generalErrors += "Confirm Password: ${errors['confirmPassword']}. ";
    }

    // ✅ نفس الشريط الأحمر
    setState(() {
      _currentErrorMessage = generalErrors;
      _showErrorBanner = true;
    });

    await _speakForce("Found ${errors.length} errors");

    await Future.delayed(const Duration(milliseconds: 2000));

    // ✅ نطق كل خطأ على حدة
    if (errors.containsKey('name')) {
      await _speak("Full Name: ${errors['name']}");
      await Future.delayed(const Duration(milliseconds: 5000));
    }

    if (errors.containsKey('email')) {
      await _speak("Email: ${errors['email']}");
      await Future.delayed(const Duration(milliseconds: 5000));
    }

    if (errors.containsKey('phone')) {
      await _speak("Mobile Number: ${errors['phone']}");
      await Future.delayed(const Duration(milliseconds: 4000));
    }

    if (errors.containsKey('confirmPassword')) {
      await _speak("Confirm Password: ${errors['confirmPassword']}");
      await Future.delayed(const Duration(milliseconds: 4000));
    }

    if (errors.containsKey('password')) {
      await _speak("Password issues:");
      await Future.delayed(const Duration(milliseconds: 2000));

      List<String> passwordErrors = errors['password'];
      for (String requirement in passwordErrors) {
        await _speak(requirement);
        await Future.delayed(const Duration(milliseconds: 3000));
      }
    }

    await _speak("Please fix these errors and try again.");
  }

  void _registerUser() async {
    // ✅ نطق بدء عملية التسجيل
    _speak("Starting registration process. Please wait...");

    // ✅ التحقق من جميع الحقول يدوياً والحصول على جميع الأخطاء
    Map<String, dynamic> fieldErrors = _validateAllFields();

    if (fieldErrors.isEmpty) {
      // إذا لا توجد أخطاء، تابع عملية التسجيل
      setState(() => _isLoading = true);

      try {
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: emailController.text.trim(),
              password: passwordController.text.trim(),
            );

        User? user = userCredential.user;

        if (user == null) {
          throw Exception("Failed to create user");
        }

        final String fullName = nameController.text.trim();

        bool emailSent = false;

        try {
          final callable = FirebaseFunctions.instance.httpsCallable(
            'sendWelcomeEmail',
          );
          await callable.call({
            'email': emailController.text.trim(),
            'displayName': fullName,
          });
          emailSent = true;
          print('Custom email sent via Cloud Function');
        } catch (cloudFunctionError) {
          print('Cloud Function error: $cloudFunctionError');

          try {
            await user.sendEmailVerification();
            emailSent = true;
            print('Sent default Firebase email as fallback');
          } catch (verificationError) {
            print('Failed to send verification email: $verificationError');
            emailSent = false;
          }
        }

        if (!emailSent) {
          await user.delete();
          throw FirebaseAuthException(
            code: 'email-send-failed',
            message:
                'Failed to send verification email. Please try again later or use a different network.',
          );
        }

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'full_name': fullName,
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

        _startCheckingVerification();

        // ✅ نطق نجاح إنشاء الحساب
        _showSuccessWithSpeech(
          "Account created successfully! Please check your email inbox and spam folder for verification link. We've sent a verification email to ${emailController.text}",
        );
      } on FirebaseAuthException catch (e) {
        String error = "An error occurred";

        if (e.code == 'too-many-requests' ||
            e.message?.contains('blocked') == true) {
          error =
              "Too many attempts from this device. Please wait 15-30 minutes and try again, or use a different network.";
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

        _showErrorWithSoundAndBanner(error);
      } catch (e) {
        _showErrorWithSoundAndBanner(
          "Unexpected error occurred. Please try again.",
        );
        print('Registration error: $e');
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } else {
      // ✅ إذا توجد أخطاء، نطق جميع الأخطاء بالترتيب
      _announceAllErrors(fieldErrors);
    }
  }

  void _startCheckingVerification() {
    _checkTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _checkEmailVerification();
      _checkCount++;

      if (_checkCount >= 100) {
        timer.cancel();
        if (mounted) {
          _showErrorWithSoundAndBanner(
            "Verification timeout. Please resend the email.",
          );
        }
      }
    });
  }

  Future<void> _checkEmailVerification() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        await user.reload();
        final updatedUser = FirebaseAuth.instance.currentUser;

        if (updatedUser?.emailVerified == true && !_emailVerified) {
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

          // ✅ نطق نجاح التحقق
          _showSuccessWithSpeech(
            "Email verified successfully! Welcome ${nameController.text}. Redirecting to home page...",
          );

          HapticFeedback.heavyImpact();

          await Future.delayed(const Duration(seconds: 2));

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomePage()),
            );
          }
        }
      }
    } catch (e) {
      print('Error checking verification: $e');
    }
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
        // ✅ نطق إمكانية إعادة الإرسال
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
      // ✅ نطق بدء إعادة الإرسال
      _speak("Sending new verification email...");

      final user = FirebaseAuth.instance.currentUser;

      await user?.sendEmailVerification();

      _startResendCooldown();

      _showSuccessWithSpeech(
        "New verification email sent successfully! Please check your inbox and spam folder.",
      );

      HapticFeedback.mediumImpact();
    } catch (e) {
      String errorMessage = "Failed to resend email";
      if (e is FirebaseAuthException && e.code == 'too-many-requests') {
        errorMessage = "Too many requests. Please wait and try again.";
      }
      _showErrorWithSoundAndBanner(errorMessage);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signUpWithGoogle() async {
    try {
      _speak("Starting Google sign up process");
      setState(() => _isLoading = true);

      // ✅ استخدام try-catch داخلي للكشف عن الفشل
      try {
        await GoogleSignInHandler.signInWithGoogle(context);

        // ✅ الانتظار قليلاً ثم التحقق من حالة المستخدم
        await Future.delayed(const Duration(seconds: 2));

        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          // ✅ نطق النجاح فقط إذا تم إنشاء المستخدم
          _showSuccessWithSpeech("Google sign up completed successfully!");
        } else {
          throw Exception("User not created");
        }
      } catch (handlerError) {
        // ✅ نطق الفشل مع التفاصيل
        _showErrorWithSoundAndBanner(
          "Google sign-up canceled. Please try again.",
        );
        return; // الخروج من الدالة عند الفشل
      }
    } catch (e) {
      _showErrorWithSoundAndBanner("Google sign-up failed. Please try again.");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ✅ Widget للشريط الأحمر في الأسفل
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
          // أيقونة الخطأ
          ExcludeSemantics(
            child: Icon(Icons.error_outline, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 12),

          // نص الخطأ
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                _currentErrorMessage!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // زر الإغلاق
          Semantics(
            label: 'Close error message',
            button: true,
            hint: 'Double tap to close error message',
            child: IconButton(
              onPressed: _hideErrorBanner,
              icon: Icon(Icons.close, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
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

          // ✅ الشريط الأحمر في الأسفل
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
                    ExcludeSemantics(
                      child: Icon(
                        Icons.person_add_rounded,
                        size: 60,
                        color: Colors.white,
                      ),
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
            Semantics(
              label: 'Full name input field',
              textField: true,
              hint: 'Enter your full name without numbers',
              child: _buildEnhancedTextFormField(
                controller: nameController,
                hint: "Full Name",
                icon: Icons.person_outline,
                validator: _validateName,
                fieldName: 'name',
              ),
            ),
            const SizedBox(height: 20),
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
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Password is required";
                  }

                  // ✅ Apply all strict conditions
                  String? passwordError = _validatePassword(value.trim());
                  if (passwordError != null) {
                    return passwordError;
                  }

                  return null;
                },
                fieldName: 'password',
              ),
            ),

            // ✅ Show password strength and requirements list
            if (passwordController.text.isNotEmpty) ...[
              const SizedBox(height: 12),

              // Show password strength
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
                      ExcludeSemantics(
                        child: Icon(
                          Icons.security,
                          size: 20,
                          color: _getPasswordStrengthColor(
                            passwordController.text,
                          ),
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
                      children: [
                        Icon(
                          Icons.checklist_rtl,
                          color: const Color(0xFF6B1D73),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
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
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Please confirm your password";
                  }
                  if (value != passwordController.text) {
                    return "Passwords do not match";
                  }
                  return null;
                },
                fieldName: 'confirmPassword',
              ),
            ),
            const SizedBox(height: 24),

            // Create Account Button
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

            // Google Sign Up Button
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
                            _onButtonTap("Sign up with Google");
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
                      children: [
                        ExcludeSemantics(
                          child: Icon(Icons.g_mobiledata, size: 30),
                        ),
                        const SizedBox(width: 12),
                        const Text(
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
            // Already have account
            // Already have account
            // في دالة _buildSignupForm()، غير الجزء الأخير ليصبح:
            Semantics(
              label: 'Already have an account, Log in button',
              button: true,
              hint: 'Double tap to go to login page',
              child: GestureDetector(
                onTap: () async {
                  _onButtonTap("Log in");
                  await Future.delayed(const Duration(milliseconds: 300));

                  // ✅ الانتقال لصفحة Login بدلاً من الرجوع للخلف
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
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
                  if (_emailVerified)
                    ExcludeSemantics(
                      child: Icon(
                        Icons.check_circle,
                        size: 80,
                        color: Colors.green,
                      ),
                    )
                  else
                    ExcludeSemantics(
                      child: Icon(
                        Icons.mark_email_unread_outlined,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    _emailVerified ? "Email Verified!" : "Check Your Email",
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 255, 255, 255),
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
                          "We sent a email to",
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
                                children: [
                                  ExcludeSemantics(
                                    child: Icon(
                                      Icons.warning_amber_rounded,
                                      color: Color.fromARGB(255, 255, 255, 255),
                                      size: 26,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    "IMPORTANT!",
                                    style: TextStyle(
                                      fontSize: 19,
                                      color: Color.fromARGB(255, 255, 255, 255),
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
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          Icons.info_outline,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
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
                    "1. Open your email app\n2. Check INBOX and SPAM folder\n3. Find our verification email\n4. Click the verification link\n5. Come back here automatically\n\n We're checking automatically!",
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
            Semantics(
              label: 'Back to login button',
              button: true,
              hint: 'Double tap to go back to login page',
              child: TextButton(
                onPressed: () {
                  _onButtonTap("Back to login");
                  _checkTimer?.cancel();
                  _resendCooldownTimer?.cancel();
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
        onChanged: (value) {
          setState(() {});
          _onFieldChanged(fieldName, value); // ✅ استدعاء دالة التنبيه
        },
        onTap: () => _onFieldFocusChanged(fieldName, true), // ✅ عند التركيز
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
        onChanged: (value) {
          setState(() {});
          _onFieldChanged(fieldName, value); // ✅ استدعاء دالة التنبيه
        },
        onTap: () => _onFieldFocusChanged(fieldName, true), // ✅ عند التركيز
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
}
