import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();

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

    _animationController.forward();

    // ✅ تهيئة الـ TTS ثم نطق رسالة الترحيب بعد ما يجهز (تشتغل حتى أول مرة)
    _setupTtsAndSpeak();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _audioPlayer.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  // ✅ خلتها Future عشان نقدر نعمل await لها
  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);

    // يخلي speak ينتظر لين يخلص قبل ما يكمل (مفيد لاحقًا)
    await _flutterTts.awaitSpeakCompletion(true);
  }

  // ✅ دالة تجمع التهيئة + الترحيب
  Future<void> _setupTtsAndSpeak() async {
    // نهيء TTS أول
    await _initTts();

    // ننتظر شوي بسيط بعد التهيئة (خصوصًا أول تشغيل)
    await Future.delayed(const Duration(milliseconds: 200));

    // ثم نطق رسالة الترحيب
    await _speakWelcomeMessage();
  }

  // رسالة الترحيب
  Future<void> _speakWelcomeMessage() async {
    await _flutterTts.speak(
      "Welcome to your new journey. Please choose Create Account or Login",
    );
  }

  Future<void> _playButtonSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/button_click.mp3'));
    } catch (e) {
      print('Error playing sound: $e');
    }
  }

  Future<void> _speakButtonText(String buttonText) async {
    await _flutterTts.speak(buttonText);
  }

  void _navigateWithSoundAndSpeech(Widget screen, String buttonName) async {
    // إيقاف أي كلام سابق
    await _flutterTts.stop();

    // تشغيل الصوت أولاً
    await _playButtonSound();

    // ثم التحدث باسم الزر
    await _speakButtonText(buttonName);

    // الانتقال بعد انتهاء الكلام
    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background same as registration page
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

          // Main content
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 0),

                      // Logo and title section
                      Container(
                        padding: const EdgeInsets.all(0),
                        child: Column(
                          children: [
                            // Logo
                            SizedBox(
                              width: 325,
                              height: 325,
                              child: Image.asset(
                                'assets/images/logo.png',
                                color: Colors.white,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.diamond_outlined,
                                    size: 50,
                                    color: Colors.white,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 0),

                            Text(
                              "Welcome to your new journey",
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withOpacity(0.8),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 25),

                      // Create Account button
                      _buildButton(
                        title: 'Create Account',
                        icon: Icons.person_add_outlined,
                        isPrimary: true,
                        onPressed: () {
                          _navigateWithSoundAndSpeech(
                            const SignupScreen(),
                            'Create Account',
                          );
                        },
                      ),

                      const SizedBox(height: 25),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 1,
                              color: Colors.white.withOpacity(0.3),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),

                      // Login button
                      _buildButton(
                        title: 'Login',
                        icon: Icons.login_outlined,
                        isPrimary: false,
                        onPressed: () {
                          _navigateWithSoundAndSpeech(
                            const LoginScreen(),
                            'Login',
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required String title,
    required IconData icon,
    required bool isPrimary,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      height: 62,
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
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary
              ? const Color.fromARGB(255, 162, 68, 172)
              : Colors.white.withOpacity(0.1),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: isPrimary
                ? BorderSide.none
                : BorderSide(color: Colors.white.withOpacity(0.3), width: 1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
