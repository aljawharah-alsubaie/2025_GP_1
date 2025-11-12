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
    _initTts(); // init TTS (we will speak after first frame inside this)
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

    // Basic settings
    await _tts.setLanguage("en-US"); // Use "ar-SA" for Arabic if you prefer
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    // Ensure we await completion to avoid overlapping speech
    await _tts.awaitSpeakCompletion(true);

    // Optional handlers
    _tts.setStartHandler(() {});
    _tts.setCompletionHandler(() {});
    _tts.setErrorHandler((msg) {});

    setState(() => _ttsReady = true);

    // Speak after first frame is rendered
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

  // ⬇️ يوقف أي كلام جاري، ينتظر 60ms، بعدها ينطق — يفيد جداً لرسائل الأخطاء
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
    setState(() => _isLoading = true);
    _buttonAnimationController.forward().then((_) {
      _buttonAnimationController.reverse();
    });

    // Announce action
    _speak("Logging in, please wait.", interrupt: true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (email.isEmpty) {
        await _showErrorWithSoundAndBanner("Email is required to continue");
        setState(() => _isLoading = false);
        return;
      }

      if (password.isEmpty) {
        await _showErrorWithSoundAndBanner("Password is required to continue");
        setState(() => _isLoading = false);
        return;
      }

      if (!email.contains('@')) {
        await _showErrorWithSoundAndBanner(
          "Please enter a valid email, such as example@domain.com",
        );
        setState(() => _isLoading = false);
        return;
      }
      if (!email.contains('.')) {
        await _showErrorWithSoundAndBanner(
          "Please enter a valid email, such as example@domain.com",
        );
        setState(() => _isLoading = false);
        return;
      }

      final allowedDomains = {
        'gmail.com': 'Gmail',
        'outlook.com': 'Outlook',
        'hotmail.com': 'Hotmail',
        'yahoo.com': 'Yahoo',
      };

      final domain = email.split('@').last.toLowerCase();
      if (!allowedDomains.containsKey(domain)) {
        await _showErrorWithSoundAndBanner("Invalid email or password");
        setState(() => _isLoading = false);
        return;
      }

      // Check user existence
      final usersQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (usersQuery.docs.isEmpty) {
        await _showErrorWithSoundAndBanner(
          "We couldn’t find an account with this email. Please sign up to continue",
        );
        setState(() => _isLoading = false);
        return;
      }

      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      const storage = FlutterSecureStorage();
      await storage.write(key: 'isLoggedIn', value: 'true');
      await storage.write(key: 'userEmail', value: email);

      // Remember Me
      if (_rememberMe) {
        await storage.write(key: 'rememberMe', value: 'true');
        await storage.write(key: 'savedEmail', value: email);
      } else {
        await storage.delete(key: 'rememberMe');
        await storage.delete(key: 'savedEmail');
      }

      User? user = userCredential.user;
      if (user != null) {
        // Get user data from Firestore
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        String fullName = 'User';
        if (userDoc.exists) {
          Map<String, dynamic> userData =
              userDoc.data() as Map<String, dynamic>;
          fullName = userData['full_name'] ?? user.displayName ?? 'User';
        }

        _showSnackBar("Welcome back, $fullName!", Colors.green);
        await _speakForce("Welcome back, $fullName!");

        if (!mounted) return;

        // Smooth navigation
        await Future.delayed(const Duration(milliseconds: 500));

        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => HomePage(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = "Login failed";
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          errorMessage = "Invalid email or password";
          break;
        case 'user-disabled':
          errorMessage = "This account has been disabled";
          break;
        case 'too-many-requests':
          errorMessage = "Too many failed attempts. Please try again later";
          break;
        default:
          errorMessage = e.message ?? "An error occurred";
      }
      await _showErrorWithSoundAndBanner(errorMessage);
    } catch (e) {
      await _showErrorWithSoundAndBanner("An unexpected error occurred");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loginWithGoogle() async {
    try {
      setState(() => _isLoading = true);
      _speak("Continuing with Google", interrupt: true);
      await GoogleSignInHandler.signInWithGoogle(context);
    } catch (e) {
      await _showErrorWithSoundAndBanner("Google sign-in failed");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == Colors.green
                  ? Icons.check_circle
                  : color == Colors.orange
                  ? Icons.warning
                  : Icons.error,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ⬇️ صار async وينطق الخطأ بقوة + يعلن لسكريـن ريدر بعد رسم الرسالة
  Future<void> _showErrorWithSoundAndBanner(String errorMessage) async {
    setState(() {
      _currentErrorMessage = errorMessage;
      _showErrorBanner = true;
    });

    // انتظر فريم واحد لضمان ظهور اللافتة قبل الإعلان/النطق
    await Future.delayed(const Duration(milliseconds: 50));

    // Screen reader live announcement
    SemanticsService.announce(errorMessage, TextDirection.ltr);

    // TTS — يوقف أي كلام جارٍ ثم ينطق الخطأ مباشرة
    await _speakForce("Error: $errorMessage");

    // Haptics
    HapticFeedback.heavyImpact();

    // Auto-hide بعد 8 ثواني (عدلي الرقم إذا تبين)
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
          // Background with gradient overlay
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

          // Main content
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

                        // Email field
                        _buildEnhancedTextFormField(
                          controller: _emailController,
                          hint: "Email Address",
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
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

                        // Password field
                        _buildPasswordField(
                          controller: _passwordController,
                          hint: "Password",
                          obscure: _obscurePassword,
                          onToggle: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
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
                                  hint: 'Double tap to toggle',
                                  checked: _rememberMe,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    onChanged: (value) => setState(
                                      () => _rememberMe = value ?? false,
                                    ),
                                    activeColor: Colors.white,
                                    checkColor: const Color(0xFF6B1D73),
                                    side: const BorderSide(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => setState(
                                    () => _rememberMe = !_rememberMe,
                                  ),
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
                                          (
                                            context,
                                            animation,
                                            secondaryAnimation,
                                          ) => const ForgotPasswordScreen(),
                                      transitionsBuilder:
                                          (
                                            context,
                                            animation,
                                            secondaryAnimation,
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

                        // Login button
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

                        // Google login
                        _buildFullWidthSocialButton(
                          icon: Icons.g_mobiledata,
                          onTap: _loginWithGoogle,
                          label: "Continue with Google",
                        ),

                        const SizedBox(height: 40),

                        // Sign up link
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

          // Error banner
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
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF6B1D73), width: 2),
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
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF6B1D73), width: 2),
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
