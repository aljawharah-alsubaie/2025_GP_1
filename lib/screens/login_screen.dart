import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/google_signin_handler.dart';
import 'home_page.dart';
import 'signup_screen.dart';
import 'set_password_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_tts/flutter_tts.dart';

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

  // Error banner state
  String? _currentErrorMessage;
  bool _showErrorBanner = false;

  // Animations
  late AnimationController _animationController;
  late AnimationController _buttonAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _buttonScaleAnimation;

  // TTS
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

    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    await _tts.awaitSpeakCompletion(true);

    _tts.setStartHandler(() {});
    _tts.setCompletionHandler(() {});
    _tts.setErrorHandler((msg) {});

    setState(() => _ttsReady = true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speak(
        "Welcome back. Please enter your email and password to continue",
        interrupt: true,
      );
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

  Future<void> _login() async {
    // نشغّل اللودينق وأنيميشن الزر
    setState(() => _isLoading = true);
    _buttonAnimationController.forward().then((_) {
      _buttonAnimationController.reverse();
    });

    // نطق بداية العملية
    _speak("Logging in, please wait.", interrupt: true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      // ========== التحقق من الإدخالات الأساسية ==========
      if (email.isEmpty) {
        await _showErrorWithSoundAndBanner("Email is required to continue");
        return;
      }

      if (password.isEmpty) {
        await _showErrorWithSoundAndBanner("Password is required to continue");
        return;
      }

      // ========== التحقق من صيغة الإيميل والدومين ==========

      // لو ما كتب @ → نعطيه مثال
      if (!email.contains('@')) {
        await _showErrorWithSoundAndBanner(
          "Please enter a valid email in the format example@domain.com.",
        );
        return;
      }

      // تحديد الدومين بعد الـ @
      final domain = email.split('@').last.toLowerCase();

      // الدومينات المسموحه فقط
      const allowedDomains = [
        'gmail.com',
        'outlook.com',
        'hotmail.com',
        'yahoo.com',
      ];

      if (!allowedDomains.contains(domain)) {
        await _showErrorWithSoundAndBanner('Invalid email or password.');
        return;
      }

      // ========== محاولة تسجيل الدخول ==========
      final UserCredential credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      final user = credential.user;

      if (user == null) {
        await _showErrorWithSoundAndBanner("Login failed. Please try again");
        return;
      }

      // التحقق من التفعيل (email verified)
      if (!user.emailVerified) {
        await _showErrorWithSoundAndBanner(
          "Your email is not verified yet. Please check your inbox and verify your email before logging in",
        );
        return;
      }

      // ========== نجاح تسجيل الدخول ==========
      // لو عندك "Remember me" خزّني الإيميل هنا
      if (_rememberMe) {
        try {
          const storage = FlutterSecureStorage();
          await storage.write(key: 'saved_email', value: email);
        } catch (_) {
          // لو صار خطأ في التخزين نتجاهله
        }
      }

      // نطق النجاح
      await _speak(
        "Login successful. Redirecting to homepage",
        interrupt: true,
      );

      // الانتقال للهوم
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    } on FirebaseAuthException catch (e) {
      // للتتبع لو حابة تشوفين الكود في الـ debug console
      debugPrint('Login error code: ${e.code}');

      // حالة: ما فيه حساب بهذا الإيميل (أو invalid-credential من بعض الإصدارات)
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        await _showErrorWithSoundAndBanner(
          'No account found for this email. Please sign up first',
        );
        return;
      }

      // حالة: الباسوورد غلط
      if (e.code == 'wrong-password') {
        await _showErrorWithSoundAndBanner('Invalid email or password');
        return;
      }

      // حالة: صيغة الإيميل غلط من Firebase (احتياط)
      if (e.code == 'invalid-email') {
        await _showErrorWithSoundAndBanner(
          'The email format is invalid. Please enter a valid email address',
        );
        return;
      }

      // حساب معطّل
      if (e.code == 'user-disabled') {
        await _showErrorWithSoundAndBanner(
          'This account has been disabled. Please contact support',
        );
        return;
      }

      // أي خطأ ثاني غير متوقع
      await _showErrorWithSoundAndBanner(
        'Login failed due to an unexpected error. Please try again',
      );
    } catch (e) {
      // أخطاء ثانية (شبكة، أشياء غير متوقعة)
      await _showErrorWithSoundAndBanner(
        'Login failed due to an unexpected error. Please try again',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loginWithGoogle() async {
    if (_isLoading) return;

    try {
      setState(() => _isLoading = true);

      await _speakForce("Google login activated. Please choose your account");
      await Future.delayed(const Duration(milliseconds: 400));

      // 🟦 استخدام الميثود الخاصة بالـ Login فقط
      final cred = await GoogleSignInHandler.signInWithGoogleForLogin(context);

      // المستخدم لغى اختيار الحساب
      if (cred == null) {
        await _showErrorWithSoundAndBanner("Google login was cancelled");
        return;
      }

      final user = cred.user;
      if (user == null) {
        await _showErrorWithSoundAndBanner(
          "Google sign-in failed, please try again.",
        );
        return;
      }

      // 🔎 نجيب بياناته من Firestore عشان الاسم
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = userDoc.data() != null
          ? userDoc.data() as Map<String, dynamic>
          : {};

      String fullName = 'User';
      if (userDoc.exists) {
        fullName = data['full_name'] ?? user.displayName ?? 'User';
      } else {
        fullName = user.displayName ?? user.email ?? 'User';
      }

      // 🧾 نخزّن حالة الدخول
      const storage = FlutterSecureStorage();
      await storage.write(key: 'isLoggedIn', value: 'true');
      await storage.write(key: 'userEmail', value: user.email ?? '');

      _showSnackBar("Welcome back, $fullName!", Colors.green);
      await _speakForce("Welcome back, $fullName!");

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
    } on FirebaseAuthException catch (e) {
      if (e.code == 'app-google-not-registered') {
        await _showErrorWithSoundAndBanner(
          'This Google account hasn’t been registered yet. Please sign up first',
        );
        return;
      }

      await _showErrorWithSoundAndBanner(
        "Google login failed. Please try again",
      );
    } catch (e) {
      await _showErrorWithSoundAndBanner(
        "Google login failed due to an unexpected error. Please try again",
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
          bottom: 120,
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
                                const Text(
                                  "Welcome Back",
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Log in to continue your journey",
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
                          hint: "Email Address",
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          ttsMessage:
                              "Email field. Please type the email you used to create your account.",
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return "Email is required";
                            }
                            final emailRegex = RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            );
                            if (!emailRegex.hasMatch(value.trim())) {
                              return "Please enter a valid email address";
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 20),

                        _buildPasswordField(
                          controller: _passwordController,
                          hint: "Password",
                          obscure: _obscurePassword,
                          onToggle: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          ttsMessage:
                              "Password field. Please type your account password. This field is secure.",
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return "Password is required";
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
                                          "Remember me is activated. Your email will be filled in automatically next time.",
                                        );
                                      } else {
                                        // ✅ لما يطفّيه
                                        _speakForce(
                                          "Remember me is deactivated. Your email will not be remembered.",
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
                                        "Remember me is on. Your email will be filled in automatically next time.",
                                      );
                                    } else {
                                      await _speakForce(
                                        "Remember me is off. Your email will not be remembered.",
                                      );
                                    }
                                  },
                                  child: const Text(
                                    "Remember me",
                                    style: TextStyle(
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
                                    "Forgot Password page. Please enter your email to reset your password",
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
                                child: const Text(
                                  "Forgot Password?",
                                  style: TextStyle(
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
                                ? 'Logging in, please wait'
                                : 'Login button',
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
                                    : const Text(
                                        "Log In",
                                        style: TextStyle(
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
                                "OR",
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
                          label: "Continue with Google",
                        ),

                        const SizedBox(height: 40),

                        Semantics(
                          button: true,
                          label: 'Sign up button',
                          hint: 'Double tap to create a new account',
                          child: GestureDetector(
                            onTap: () async {
                              HapticFeedback.selectionClick();
                              await _speakForce("Sign up");
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
                                    "Don't have an account? ",
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Text(
                                    "Sign Up",
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
              label: obscure ? 'Show password' : 'Hide password',
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
