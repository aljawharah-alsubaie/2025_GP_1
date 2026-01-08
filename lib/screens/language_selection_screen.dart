import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../providers/language_provider.dart';
import 'onboarding_screen.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({Key? key}) : super(key: key);

  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen>
    with TickerProviderStateMixin {
  final FlutterTts _flutterTts = FlutterTts();
  String? _selectedLanguage;
  bool _isLoading = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initTts();
    _animationController.forward();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutBack,
      ),
    );
  }

  void _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 500));
      await _flutterTts.speak(
        "Welcome. Please choose your language. English or Arabic",
      );

      await Future.delayed(const Duration(milliseconds: 1500));

      await _flutterTts.setLanguage("ar-SA");
      await _flutterTts.speak("مرحبا. من فضلك اختر لغتك. انجليزي او عربي");
      await _flutterTts.setLanguage("en-US");
    });
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _selectLanguage(String code, String languageName) async {
    setState(() {
      _selectedLanguage = code;
      _isLoading = true;
    });

    await _flutterTts.setLanguage(code == 'ar' ? 'ar-SA' : 'en-US');
    await _flutterTts.speak(languageName);

    await Provider.of<LanguageProvider>(context, listen: false)
        .setLanguage(code);

    const storage = FlutterSecureStorage();
    await storage.write(key: 'language_selected', value: 'true');

    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const OnboardingScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF6B1D73),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // الخلفية
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF6B1D73),
                  Color(0xFF4A1250),
                  Color(0xFF2D0B30),
                ],
              ),
            ),
          ),

          // المحتوى مع Scroll
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: SingleChildScrollView(  // ← 🆕 هذا المهم!
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 40),

                      // الأيقونة والعنوان
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            // أيقونة اللغة
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.language_rounded,
                                size: 60,
                                color: Colors.white,
                              ),
                            ),

                            const SizedBox(height: 16),

                            const Text(
                              "Choose Your Language",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),

                            const SizedBox(height: 6),

                            const Text(
                              "اختر لغتك",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),

                            const SizedBox(height: 10),

                            Text(
                              "Select your preferred language\nاختر لغتك المفضلة",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),

                      // زر الإنجليزي
                      _buildLanguageButton(
                        language: 'English',
                        flag: '🇬🇧',
                        code: 'en',
                        isSelected: _selectedLanguage == 'en',
                      ),

                      const SizedBox(height: 16),

                      // زر العربي
                      _buildLanguageButton(
                        language: 'العربية',
                        flag: '🇸🇦',
                        code: 'ar',
                        isSelected: _selectedLanguage == 'ar',
                      ),

                      const SizedBox(height: 40),

                      // ملاحظة صغيرة
                      if (!_isLoading)
                        Text(
                          "You can change this later in settings\nيمكنك تغيير ذلك لاحقًا في الإعدادات",
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.7),
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLanguageButton({
    required String language,
    required String flag,
    required String code,
    required bool isSelected,
  }) {
    return Semantics(
      button: true,
      label: 'Select $language language',
      hint: 'Double tap to select $language as your language',
      child: GestureDetector(
        onTap: _isLoading ? null : () => _selectLanguage(code, language),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withOpacity(0.25)
                : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? Colors.white
                  : Colors.white.withOpacity(0.3),
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              Text(
                flag,
                style: const TextStyle(fontSize: 40),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Text(
                  language,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),

              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Color(0xFF6B1D73),
                    size: 24,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}