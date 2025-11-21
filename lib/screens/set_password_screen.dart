import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback
import 'package:flutter/semantics.dart'; // SemanticsService
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with TickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _emailSent = false;

  // Error banner state (زي صفحة اللوق إن)
  String? _currentErrorMessage;
  bool _showErrorBanner = false;

  // Animations
  late AnimationController _animationController;
  late AnimationController _successAnimationController;
  late AnimationController _buttonAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _successScaleAnimation;
  late Animation<double> _buttonScaleAnimation;

  // TTS
  final FlutterTts _tts = FlutterTts();
  bool _ttsReady = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initTts();
    _animationController.forward();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage("en-US");
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
      setState(() => _ttsReady = true);

      // تعريف بسيط لأول ما تفتح الشاشة
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _speak(
          "Forgot Password page. Please enter your email then press send reset link",
          interrupt: true,
        );
      });
    } catch (_) {}
  }

  Future<void> _speak(String text, {bool interrupt = true}) async {
    if (!_ttsReady) return;
    if (text.trim().isEmpty) return;
    try {
      if (interrupt) {
        await _tts.stop();
        await Future.delayed(const Duration(milliseconds: 60));
      }
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> _speakForce(String text) async {
    if (!_ttsReady || text.trim().isEmpty) return;
    try {
      await _tts.stop();
      await Future.delayed(const Duration(milliseconds: 60));
      await _tts.speak(text);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tts.stop();
    _animationController.dispose();
    _successAnimationController.dispose();
    _buttonAnimationController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _successAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
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

    _successScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _successAnimationController,
        curve: Curves.elasticOut,
      ),
    );

    _buttonScaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _buttonAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  // ================== ERROR BANNER (زي اللوق إن) ==================
  Future<void> _showErrorWithSoundAndBanner(String errorMessage) async {
    setState(() {
      _currentErrorMessage = errorMessage;
      _showErrorBanner = true;
    });

    await Future.delayed(const Duration(milliseconds: 50));

    // إعلان للمستخدم القارئ شاشة
    SemanticsService.announce(errorMessage, TextDirection.ltr);

    // صوت
    await _speakForce("Error: $errorMessage");

    // هزة بسيطة
    HapticFeedback.heavyImpact();

    // إخفاء بعد 8 ثواني
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
        color: const Color(0xFFD32F2F), // أحمر نفس اللوق إن
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
          IconButton(
            onPressed: _hideErrorBanner,
            icon: const Icon(Icons.close, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    // نستخدم الفاليديشن + نطلّع البانر الأحمر بدل السنك بار
    final isValid = _formKey.currentState?.validate() ?? false;

    if (!isValid) {
      if (email.isEmpty) {
        await _showErrorWithSoundAndBanner(
          "Email is required to send a reset link",
        );
      } else {
        await _showErrorWithSoundAndBanner(
          "Please enter a valid email address",
        );
      }
      return;
    }

    // هنا كل شيء صحيح
    await _speak(
      "Send reset link button pressed. Sending reset link, please wait.",
      interrupt: true,
    );

    setState(() => _loading = true);
    _buttonAnimationController.forward().then((_) {
      _buttonAnimationController.reverse();
    });

    try {
      // 🔥 نستدعي نفس الميثود حقّك في الكلاود فنكشن
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
        'sendCustomPasswordReset',
      );

      final result = await callable.call({'email': email});

      if (result.data['success'] == true) {
        setState(() {
          _emailSent = true;
          _loading = false;
        });

        _successAnimationController.forward();

        _showSnackBar(
          "Password reset link sent to $email",
          Colors.green,
          Icons.check_circle,
        );

        await _speakForce(
          "Password reset link has been sent to $email. Please check your inbox.",
        );

        await _speakForce("Returning to login page in 5 seconds");

        // Auto navigate back after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    const LoginScreen(),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                transitionDuration: const Duration(milliseconds: 500),
              ),
            );
          }
        });
      } else {
        // في حال success رجعت false لأي سبب
        setState(() => _loading = false);
        await _showErrorWithSoundAndBanner(
          "Something went wrong while sending the reset link",
        );
      }
    } on FirebaseFunctionsException catch (e) {
      setState(() => _loading = false);

      String errorMessage = "Something went wrong";

      switch (e.code) {
        case 'not-found':
          // الإيميل مو مسجّل
          errorMessage = "No account found with this email address";
          break;

        case 'invalid-argument':
          // صيغة الإيميل غلط
          errorMessage = "Please enter a valid email address";
          break;

        case 'internal':
          // حالياً الفنكشن ترجع INTERNAL → نترجمها لرسالة مفهومة
          errorMessage = "No account found with this email address";
          break;

        default:
          // أي خطأ ثاني عام
          errorMessage = "Something went wrong. Please try again.";
      }

      await _showErrorWithSoundAndBanner(errorMessage);
    } catch (e) {
      setState(() => _loading = false);
      await _showErrorWithSoundAndBanner("An unexpected error occurred");
    }
  }

  // سنك بار للنجاح فقط
  void _showSnackBar(String message, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

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
                  child: Column(
                    children: [
                      const SizedBox(height: 60),

                      // Header section with animation
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
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF6B1D73,
                                  ).withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _emailSent
                                      ? Icons.mark_email_read
                                      : Icons.lock_reset,
                                  size: 48,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _emailSent
                                    ? "Check Your Email"
                                    : "Forgot Password?",
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _emailSent
                                    ? "We've sent a password reset link to your email"
                                    : "Don't worry! Enter your email and we'll send you a reset link",
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white.withOpacity(0.9),
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Success animation or form
                      if (_emailSent)
                        ScaleTransition(
                          scale: _successScaleAnimation,
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  size: 64,
                                  color: Colors.green,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  "Email Sent Successfully!",
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Please check your inbox and click on the reset link",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.8),
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: Colors.blue.shade300,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          "Check your spam folder if you don't see the email",
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,

                                            color: Colors.white.withOpacity(
                                              0.7,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  "Returning to login in 5 seconds...",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.6),
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              // Email input field
                              _buildEnhancedTextFormField(
                                controller: _emailController,
                                hint: "Enter your email address",
                                icon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                onTap: () {
                                  _speakForce(
                                    "Email field. Enter the email address you used to sign in, then press send reset link button.",
                                  );
                                },
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return "Email is required";
                                  }
                                  final emailRegex = RegExp(
                                    r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                                  );
                                  if (!emailRegex.hasMatch(value.trim())) {
                                    return "Please enter a valid email address";
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 32),

                              // Send reset link button
                              ScaleTransition(
                                scale: _buttonScaleAnimation,
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 59,
                                  child: ElevatedButton(
                                    onPressed: _loading ? null : _resetPassword,
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
                                    child: _loading
                                        ? const SizedBox(
                                            height: 24,
                                            width: 24,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.send, size: 20),
                                              SizedBox(width: 8),
                                              Text(
                                                "Send Reset Link",
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Instructions
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.blue.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.blue.shade300,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        "We'll send you a secure link to reset your password safely",
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 40),

                      // Back to login link
                      if (!_emailSent)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Remember your password? ",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              GestureDetector(
                                onTap: () async {
                                  // 🗣 يتكلم أول
                                  await _speak(
                                    "Returning to login page",
                                    interrupt: true,
                                  );

                                  // ⏳ ينتظر ثانيتين
                                  await Future.delayed(
                                    const Duration(seconds: 1),
                                  );

                                  if (!mounted) return;

                                  // 🎬 يرجع لشاشة اللوق إن بانيميشن سلايد
                                  Navigator.pushReplacement(
                                    context,
                                    PageRouteBuilder(
                                      pageBuilder:
                                          (
                                            context,
                                            animation,
                                            secondaryAnimation,
                                          ) => const LoginScreen(),
                                      transitionsBuilder:
                                          (
                                            context,
                                            animation,
                                            secondaryAnimation,
                                            child,
                                          ) {
                                            return SlideTransition(
                                              position: Tween<Offset>(
                                                // من اليسار لليمين عشان إحساس "رجوع"
                                                begin: const Offset(-1.0, 0.0),
                                                end: Offset.zero,
                                              ).animate(animation),
                                              child: child,
                                            );
                                          },
                                    ),
                                  );
                                },
                                child: const Text(
                                  "Log In",
                                  style: TextStyle(
                                    color: Color.fromARGB(255, 248, 183, 255),
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ✅ البانر الأحمر تحت زي اللوق إن
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
    VoidCallback? onTap,
  }) {
    const primaryPurple = Color(0xFF6B1D73);

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
        keyboardType: keyboardType,
        validator: validator,
        onTap: onTap, // ✅ لما يضغط على الفيلد يتكلم + يركزه
        style: const TextStyle(color: Colors.black, fontSize: 18),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 18),
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: primaryPurple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: primaryPurple, size: 24),
          ),
          // ✅ البوردر البنفسجي الخفيف
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: primaryPurple.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: primaryPurple, width: 2),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          fillColor: Colors.white.withOpacity(0.95),
          filled: true,
          contentPadding: const EdgeInsets.all(24),
        ),
      ),
    );
  }
}
