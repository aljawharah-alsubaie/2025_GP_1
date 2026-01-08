import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/google_signin_handler.dart';
import '../providers/language_provider.dart';
import 'home_page.dart';
import 'signup_screen.dart';
import 'set_password_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_functions/cloud_functions.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  String? _currentErrorMessage;
  bool _showErrorBanner = false;

  late AnimationController _animationController;
  late AnimationController _buttonAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _buttonScaleAnimation;

  late final FlutterTts _tts;
  bool _ttsReady = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _checkRememberedUser();
    _initTts();
    _animationController.forward();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _buttonAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeInOut),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.2, 1.0, curve: Curves.easeOutBack),
          ),
        );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.4, 1.0, curve: Curves.elasticOut),
      ),
    );

    _buttonScaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _buttonAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  Future<void> _initTts() async {
    _tts = FlutterTts();
    
    // ✅ نحدد اللغة بناءً على اختيار المستخدم
    final languageCode = Provider.of<LanguageProvider>(context, listen: false).languageCode;
    await _tts.setLanguage(languageCode == 'ar' ? 'ar-SA' : 'en-US');
    
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);

    _tts.setStartHandler(() {});
    _tts.setCompletionHandler(() {});
    _tts.setErrorHandler((msg) {});

    setState(() => _ttsReady = true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      final message = languageProvider.isArabic
          ? "مرحبا بعودتك. من فضلك ادخل بريدك الإلكتروني وكلمة المرور للمتابعة"
          : "Welcome back. Please enter your email and password to continue";
      _speak(message, interrupt: true);
    });
  }

  Future<void> _speak(String text, {bool interrupt = true}) async {
    if (!_ttsReady) return;
    if (interrupt) {
      try {
        await _tts.stop();
      } catch (_) {}
    }
    if (text.trim().isEmpty) return;
    await _tts.speak(text);
  }

  Future<void> _speakForce(String text) async {
    if (!_ttsReady || text.trim().isEmpty) return;
    try {
      await _tts.stop();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 60));
    await _tts.speak(text);
  }

  Future<void> _stopSpeak() async {
    if (!_ttsReady) return;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> _checkRememberedUser() async {
    const storage = FlutterSecureStorage();
    final rememberMe = await storage.read(key: 'rememberMe');
    final savedEmail = await storage.read(key: 'savedEmail');

    if (rememberMe == 'true' && savedEmail != null) {
      setState(() {
        _emailController.text = savedEmail;
        _rememberMe = true;
      });
    }
  }

  @override
  void dispose() {
    _stopSpeak();
    _tts.stop();
    _animationController.dispose();
    _buttonAnimationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendLoginAlertEmail({
    required String email,
    required String method,
  }) async {
    if (email.isEmpty) return;
    try {
      await FirebaseFunctions.instance
          .httpsCallable('sendLoginAlertEmail')
          .call({'email': email, 'loginMethod': method});
    } catch (e) {
      debugPrint('sendLoginAlertEmail failed: $e');
    }
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);
    _buttonAnimationController.forward().then((_) {
      _buttonAnimationController.reverse();
    });

    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    _speak(
      languageProvider.isArabic ? "جاري تسجيل الدخول، انتظر من فضلك" : "Logging in, please wait.",
      interrupt: true,
    );

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (email.isEmpty) {
        await _showErrorWithSoundAndBanner(
          languageProvider.isArabic ? "البريد الإلكتروني مطلوب للمتابعة" : "Email is required to continue"
        );
        return;
      }

      if (password.isEmpty) {
        await _showErrorWithSoundAndBanner(
          languageProvider.isArabic ? "كلمة المرور مطلوبة للمتابعة" : "Password is required to continue"
        );
        return;
      }

      if (!email.contains('@')) {
        await _showErrorWithSoundAndBanner(
          languageProvider.isArabic
              ? "من فضلك ادخل بريد إلكتروني صحيح بالصيغة example@domain.com"
              : "Please enter a valid email in the format example@domain.com.",
        );
        return;
      }

      final domain = email.split('@').last.toLowerCase();

      const allowedDomains = [
        'gmail.com',
        'outlook.com',
        'hotmail.com',
        'yahoo.com',
      ];

      if (!allowedDomains.contains(domain)) {
        await _showErrorWithSoundAndBanner(
          languageProvider.isArabic ? "بريد إلكتروني أو كلمة مرور غير صحيحة" : 'Invalid email or password.'
        );
        return;
      }

      final checkEmailCallable = FirebaseFunctions.instance.httpsCallable(
        'checkEmailStatus',
      );

      final checkResult = await checkEmailCallable.call(<String, dynamic>{
        'email': email,
      });

      final checkData = Map<String, dynamic>.from(
        checkResult.data as Map<dynamic, dynamic>,
      );

      final bool exists = checkData['exists'] == true;
      final List<String> providers = List<String>.from(
        checkData['providers'] ?? const [],
      );

      if (!exists) {
        await _showErrorWithSoundAndBanner(
          languageProvider.isArabic
              ? "لا يوجد حساب بهذا البريد. من فضلك أنشئ حساباً أولاً"
              : 'No account found for this email. Please sign up first',
        );
        return;
      }

      if (!providers.contains('password')) {
        await _showErrorWithSoundAndBanner(
          languageProvider.isArabic
              ? "هذا البريد مسجل عبر Google. من فضلك استخدم تسجيل الدخول بـ Google"
              : 'This email is registered with Google. Please continue with Google sign-in.',
        );
        return;
      }

      final UserCredential credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      final user = credential.user;

      if (user == null) {
        await _showErrorWithSoundAndBanner(
          languageProvider.isArabic ? "فشل تسجيل الدخول. حاول مرة أخرى" : "Login failed. Please try again"
        );
        return;
      }

      if (!user.emailVerified) {
        try {
          final callable = FirebaseFunctions.instance.httpsCallable(
            'handleUnverifiedLogin',
          );

          final result = await callable.call(<String, dynamic>{
            'email': email,
            'displayName': user.displayName ?? email.split('@').first,
          });

          final data = Map<String, dynamic>.from(
            result.data as Map<dynamic, dynamic>,
          );

          final bool resent = data['resent'] == true;
          final String? lastSentAt = data['lastSentAt'] as String?;

          if (resent) {
            await _showErrorWithSoundAndBanner(
              languageProvider.isArabic
                  ? "بريدك لم يتم التحقق منه بعد. أرسلنا لك رابط تحقق جديد. تفقد بريدك ثم حاول تسجيل الدخول مرة أخرى"
                  : "Your email is not verified yet. We have sent you a new verification link. "
                    "Please check your inbox then try logging in again after verifying",
            );
          } else {
            final extraTimeInfo = lastSentAt != null
                ? (languageProvider.isArabic ? " أرسلنا رسالة تحقق مؤخراً." : " We already sent a verification email recently.")
                : "";
            await _showErrorWithSoundAndBanner(
              languageProvider.isArabic
                  ? "بريدك لم يتم التحقق منه بعد.$extraTimeInfo من فضلك تفقد بريدك واستخدم رسالة التحقق الموجودة"
                  : "Your email is not verified yet.$extraTimeInfo Please check your inbox and use the existing verification email",
            );
          }
        } catch (e) {
          await _showErrorWithSoundAndBanner(
            languageProvider.isArabic
                ? "بريدك لم يتم التحقق منه بعد. من فضلك تفقد بريدك للحصول على رسالة التحقق"
                : "Your email is not verified yet. Please check your inbox for the verification email",
          );
        }

        await FirebaseAuth.instance.signOut();
        return;
      }

      await _sendLoginAlertEmail(email: email, method: 'Email/Password');

      String fullName = 'User';

      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        final data = userDoc.data();

        if (data != null && data.isNotEmpty) {
          fullName =
              data['full_name'] ?? user.displayName ?? user.email ?? 'User';
        } else {
          fullName = user.displayName ?? user.email ?? 'User';
        }
      } catch (_) {
        fullName = user.displayName ?? user.email ?? 'User';
      }

      final welcomeMsg = languageProvider.isArabic
          ? "مرحباً بعودتك، $fullName!"
          : "Welcome back, $fullName!";
      
      _showSnackBar(welcomeMsg, Colors.green);
      await _speakForce(welcomeMsg);

      if (_rememberMe) {
        try {
          const storage = FlutterSecureStorage();
          await storage.write(key: 'saved_email', value: email);
        } catch (_) {}
      }

      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 500));

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('Login error code: ${e.code}');

      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        await _showErrorWithSoundAndBanner(
          languageProvider.isArabic ? "بريد إلكتروني أو كلمة مرور غير صحيحة" : 'Invalid email or password'
        );
        return;
      }

      if (e.code == 'invalid-email') {
        await _showErrorWithSoundAndBanner(
          languageProvider.isArabic
              ? "صيغة البريد الإلكتروني غير صحيحة. من فضلك ادخل بريداً صحيحاً"
              : 'The email format is invalid. Please enter a valid email address',
        );
        return;
      }

      if (e.code == 'user-disabled') {
        await _showErrorWithSoundAndBanner(
          languageProvider.isArabic
              ? "تم تعطيل هذا الحساب. من فضلك تواصل مع الدعم"
              : 'This account has been disabled. Please contact support',
        );
        return;
      }

      await _showErrorWithSoundAndBanner(
        languageProvider.isArabic
            ? "حدث خطأ غير متوقع. حاول مرة أخرى"
            : 'An unexpected error occurred. Please try again',
      );
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Network') ||
          e.toString().contains('Handshake') ||
          e.toString().contains('Failed host lookup')) {
        await _showErrorWithSoundAndBanner(
          languageProvider.isArabic
              ? "من فضلك تحقق من اتصالك بالإنترنت وحاول مرة أخرى"
              : 'Please check your internet connection and try again',
        );
        return;
      }

      await _showErrorWithSoundAndBanner(
        languageProvider.isArabic
            ? "حدث خطأ غير متوقع. حاول مرة أخرى"
            : 'An unexpected error occurred. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }Future<void> _loginWithGoogle() async {
    if (_isLoading) return;

    try {
      setState(() => _isLoading = true);
      
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

      await _speakForce(
        languageProvider.isArabic
            ? "تم تفعيل تسجيل الدخول بـ Google. من فضلك اختر حسابك"
            : "Google login activated. Please choose your account"
      );
      await Future.delayed(const Duration(milliseconds: 400));

      final cred = await GoogleSignInHandler.signInWithGoogleForLogin(context);

      if (cred == null) {
        await _showErrorWithSoundAndBanner(
          languageProvider.isArabic ? "تم إلغاء تسجيل الدخول بـ Google" : "Google login was cancelled"
        );
        return;
      }

      final user = cred.user;
      if (user == null) {
        await _showErrorWithSoundAndBanner(
          languageProvider.isArabic
              ? "فشل تسجيل الدخول بـ Google، حاول مرة أخرى"
              : "Google sign-in failed, please try again.",
        );
        return;
      }

      try {
        await _sendLoginAlertEmail(email: user.email ?? '', method: 'Google');
      } catch (e) {
        debugPrint('❌ sendLoginAlertEmail failed: $e');
      }

      final userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final userDoc = await userDocRef.get();

      Map<String, dynamic> data = {};
      String fullName = 'User';

      if (userDoc.exists) {
        data = userDoc.data() as Map<String, dynamic>;
        fullName = data['full_name'] ?? user.displayName ?? 'User';
      } else {
        fullName = user.displayName ?? user.email ?? 'User';

        await userDocRef.set({
          'full_name': fullName,
          'email': user.email ?? '',
          'phone': '',
          'signInProvider': 'google',
          'email_verified': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      const storage = FlutterSecureStorage();
      await storage.write(key: 'isLoggedIn', value: 'true');
      await storage.write(key: 'userEmail', value: user.email ?? '');

      final welcomeMsg = languageProvider.isArabic
          ? "مرحباً، $fullName!"
          : "Welcome, $fullName!";
      
      _showSnackBar(welcomeMsg, Colors.green);
      await _speakForce(welcomeMsg);

      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 500));

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const HomePage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } catch (e, stack) {
      debugPrint('❌ Google login ERROR: $e');
      debugPrint(stack.toString());
      
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      await _showErrorWithSoundAndBanner(
        languageProvider.isArabic
            ? "فشل تسجيل الدخول بـ Google بسبب خطأ غير متوقع. حاول مرة أخرى"
            : "Google login failed due to an unexpected error. Please try again",
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;

    final overlay = Overlay.of(context, rootOverlay: true);

    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          bottom: 80,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    color == Colors.green
                        ? Icons.check_circle
                        : Icons.error_outline,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);

    Future.delayed(const Duration(seconds: 4), () {
      try {
        entry.remove();
      } catch (_) {}
    });
  }

  Future<void> _showErrorWithSoundAndBanner(String errorMessage) async {
    setState(() {
      _currentErrorMessage = errorMessage;
      _showErrorBanner = true;
    });

    await Future.delayed(const Duration(milliseconds: 50));

    SemanticsService.announce(errorMessage, TextDirection.ltr);

    await _speakForce("Error: $errorMessage");

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
  }

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
          ExcludeSemantics(
            child: Icon(Icons.error_outline, color: Colors.white, size: 28),
          ),
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
                ),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
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

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage("assets/images/backk.jpg"),
                fit: BoxFit.cover,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.4),
                    Colors.black.withOpacity(0.1),
                    Colors.black.withOpacity(0.4),
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        const SizedBox(height: 40),

                        // Header
                        ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Semantics(
                                  label: 'Login icon',
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF6B1D73,
                                      ).withOpacity(0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.login_rounded,
                                      size: 48,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  languageProvider.translate('welcomeBack'),
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  languageProvider.translate('loginToContinue'),
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

                        const SizedBox(height: 40),

                        _buildEnhancedTextFormField(
                          controller: _emailController,
                          hint: languageProvider.translate('emailAddress'),
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          ttsMessage: languageProvider.isArabic
                              ? "حقل البريد الإلكتروني. من فضلك اكتب البريد الذي استخدمته لإنشاء حسابك"
                              : "Email field. Please type the email you used to create your account.",
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return languageProvider.isArabic
                                  ? "البريد الإلكتروني مطلوب"
                                  : "Email is required";
                            }
                            final emailRegex = RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            );
                            if (!emailRegex.hasMatch(value.trim())) {
                              return languageProvider.isArabic
                                  ? "من فضلك ادخل بريداً إلكترونياً صحيحاً"
                                  : "Please enter a valid email address";
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 20),

                        _buildPasswordField(
                          controller: _passwordController,
                          hint: languageProvider.translate('password'),
                          obscure: _obscurePassword,
                          onToggle: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          ttsMessage: languageProvider.isArabic
                              ? "حقل كلمة المرور. من فضلك اكتب كلمة مرور حسابك"
                              : "Password field. Please type your account password",
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return languageProvider.isArabic
                                  ? "كلمة المرور مطلوبة"
                                  : "Password is required";
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Semantics(
                                  label: 'Remember me checkbox',
                                  hint: 'Double tap to toggle remember me',
                                  checked: _rememberMe,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    onChanged: (value) {
                                      final newValue = value ?? false;

                                      setState(() {
                                        _rememberMe = newValue;
                                      });

                                      if (newValue) {
                                        _speakForce(
                                          languageProvider.isArabic
                                              ? "تم تفعيل تذكرني. سيتم ملء بريدك تلقائياً في المرة القادمة"
                                              : "Remember me is activated. Your email will be filled in automatically next time.",
                                        );
                                      } else {
                                        _speakForce(
                                          languageProvider.isArabic
                                              ? "تم تعطيل تذكرني. لن يتم تذكر بريدك"
                                              : "Remember me is deactivated. Your email will not be remembered.",
                                        );
                                      }
                                    },
                                    activeColor: Colors.white,
                                    checkColor: const Color(0xFF6B1D73),
                                    side: const BorderSide(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () async {
                                    setState(() {
                                      _rememberMe = !_rememberMe;
                                    });

                                    if (_rememberMe) {
                                      await _speakForce(
                                        languageProvider.isArabic
                                            ? "تم تفعيل تذكرني. سيتم ملء بريدك تلقائياً في المرة القادمة"
                                            : "Remember me is on. Your email will be filled in automatically next time.",
                                      );
                                    } else {
                                      await _speakForce(
                                        languageProvider.isArabic
                                            ? "تم تعطيل تذكرني. لن يتم تذكر بريدك"
                                            : "Remember me is off. Your email will not be remembered.",
                                      );
                                    }
                                  },
                                  child: Text(
                                    languageProvider.translate('rememberMe'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Semantics(
                              button: true,
                              label: 'Forgot password button',
                              hint: 'Double tap to reset your password',
                              child: TextButton(
                                onPressed: () {
                                  _speak(
                                    languageProvider.isArabic
                                        ? "صفحة نسيت كلمة المرور. من فضلك ادخل بريدك لإعادة تعيين كلمة المرور"
                                        : "Forgot Password page. Please enter your email to reset your password",
                                    interrupt: true,
                                  );
                                  Navigator.push(
                                    context,
                                    PageRouteBuilder(
                                      pageBuilder:
                                          (context, animation, secondary) =>
                                              const ForgotPasswordScreen(),
                                      transitionsBuilder:
                                          (
                                            context,
                                            animation,
                                            secondary,
                                            child,
                                          ) {
                                            return SlideTransition(
                                              position: Tween<Offset>(
                                                begin: const Offset(1.0, 0.0),
                                                end: Offset.zero,
                                              ).animate(animation),
                                              child: child,
                                            );
                                          },
                                    ),
                                  );
                                },
                                child: Text(
                                  languageProvider.translate('forgotPassword'),
                                  style: const TextStyle(
                                    color: Color.fromARGB(255, 231, 172, 238),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 30),

                        ScaleTransition(
                          scale: _buttonScaleAnimation,
                          child: Semantics(
                            button: true,
                            label: _isLoading
                                ? (languageProvider.isArabic
                                    ? 'جاري تسجيل الدخول، انتظر من فضلك'
                                    : 'Logging in, please wait')
                                : (languageProvider.isArabic
                                    ? 'زر تسجيل الدخول'
                                    : 'Login button'),
                            hint: _isLoading ? '' : 'Double tap to login',
                            enabled: !_isLoading,
                            child: SizedBox(
                              width: double.infinity,
                              height: 59,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6B1D73),
                                  foregroundColor: Colors.white,
                                  elevation: 12,
                                  shadowColor: const Color(
                                    0xFF6B1D73,
                                  ).withOpacity(0.4),
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
                                    : Text(
                                        languageProvider.translate('logIn'),
                                        style: const TextStyle(
                                          fontSize: 21,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 30),

                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 1,
                                color: Colors.white.withOpacity(0.3),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                languageProvider.translate('or'),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontWeight: FontWeight.w500,
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

                        const SizedBox(height: 30),

                        _buildFullWidthSocialButton(
                          icon: Icons.g_mobiledata,
                          onTap: _loginWithGoogle,
                          label: languageProvider.translate('continueWithGoogle'),
                        ),

                        const SizedBox(height: 40),

                        Semantics(
                          button: true,
                          label: 'Sign up button',
                          hint: 'Double tap to create a new account',
                          child: GestureDetector(
                            onTap: () async {
                              HapticFeedback.selectionClick();
                              await _speakForce(languageProvider.translate('signUp'));
                              if (!mounted) return;
                              Navigator.push(
                                context,
                                PageRouteBuilder(
                                  pageBuilder: (_, __, ___) =>
                                      const SignupScreen(),
                                  transitionsBuilder:
                                      (_, animation, __, child) {
                                        return SlideTransition(
                                          position: Tween<Offset>(
                                            begin: const Offset(1.0, 0.0),
                                            end: Offset.zero,
                                          ).animate(animation),
                                          child: child,
                                        );
                                      },
                                ),
                              );
                            },
                            child: Container(
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
                                    languageProvider.translate('dontHaveAccount'),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    languageProvider.translate('signUp'),
                                    style: const TextStyle(
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
                ),
              ),
            ),
          ),

          Positioned(bottom: 0, left: 0, right: 0, child: _buildErrorBanner()),
        ],
      ),
    );
  }

  Widget _buildEnhancedTextFormField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    String? ttsMessage,
  }) {
    return Semantics(
      label: '$hint input field',
      textField: true,
      child: Container(
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
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(color: Colors.black, fontSize: 18),
          onTap: () {
            if (ttsMessage != null) {
              _speakForce(ttsMessage);
            }
          },
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
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              borderSide: BorderSide(color: Color(0xFF6B1D73), width: 2),
            ),
            fillColor: Colors.white.withOpacity(0.95),
            filled: true,
            contentPadding: const EdgeInsets.all(24),
          ),
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
    String? ttsMessage,
  }) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return Semantics(
      label: 'Password input field',
      textField: true,
      obscured: true,
      child: Container(
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
          style: const TextStyle(color: Colors.black, fontSize: 18),
          onTap: () {
            if (ttsMessage != null) {
              _speakForce(ttsMessage);
            }
          },
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
              button: true,
              label: obscure
                  ? (languageProvider.isArabic ? 'إظهار كلمة المرور' : 'Show password')
                  : (languageProvider.isArabic ? 'إخفاء كلمة المرور' : 'Hide password'),
              hint: 'Double tap to toggle password visibility',
              child: IconButton(
                onPressed: onToggle,
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
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              borderSide: BorderSide(color: Color(0xFF6B1D73), width: 2),
            ),
            fillColor: Colors.white.withOpacity(0.95),
            filled: true,
            contentPadding: const EdgeInsets.all(24),
          ),
        ),
      ),
    );
  }

  Widget _buildFullWidthSocialButton({
    required IconData icon,
    required VoidCallback onTap,
    required String label,
  }) {
    return Semantics(
      button: true,
      label: label,
      hint: 'Double tap to $label',
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
            onPressed: onTap,
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
                ExcludeSemantics(child: Icon(icon, size: 30)),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}