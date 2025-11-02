import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'welcome_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final FlutterTts _flutterTts = FlutterTts();
  int _currentPage = 0;
  bool _isSpeaking = false;

  final List<String> images = [
    'assets/images/onboarding1.png',
    'assets/images/onboarding2.png',
  ];

  final List<String> titles = ["Welcome to Munir", "Smart Assistance for You"];

  final List<String> subtitles = [
    "Your AI-powered companion for easier daily life.",
    "Read text, recognize faces, and get real-time feedback.",
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
    _startAutoPlay();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _pageController.dispose();
    super.dispose();
  }

  void _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);

    // تحدث تلقائي عند بدء التطبيق
    _speakCurrentPage();
  }

  void _speakCurrentPage() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
    }

    setState(() {
      _isSpeaking = true;
    });

    String fullText = "${titles[_currentPage]}. ${subtitles[_currentPage]}";

    await _flutterTts.speak(fullText);

    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
      // الانتقال للصفحة التالية بعد انتهاء الكلام
      _autoNextPage();
    });
  }

  void _autoNextPage() {
    Future.delayed(const Duration(seconds: 1), () {
      if (_currentPage < images.length - 1) {
        _nextPage();
      } else {
        _goToWelcomeScreen();
      }
    });
  }

  void _startAutoPlay() {
    // يمكن إضافة منطق للتحكم التلقائي هنا إذا لزم الأمر
  }

  void _nextPage() {
    if (_currentPage < images.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    } else {
      _goToWelcomeScreen();
    }
  }

  void _goToWelcomeScreen() {
    _flutterTts.stop();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    );
  }

  void _onPageTap() {
    // عند النقر على الشاشة، تخطي الكلام الحالي والانتقال للصفحة التالية
    _flutterTts.stop();
    _nextPage();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
    // تحدث بالكلام الجديد عند تغيير الصفحة
    _speakCurrentPage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: _onPageTap,
        child: PageView.builder(
          controller: _pageController,
          itemCount: images.length,
          onPageChanged: _onPageChanged,
          physics:
              const ClampingScrollPhysics(), // لمنع المستخدم من التمرير يدوياً
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${index + 1}/${images.length}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // مؤشر التحدث بدلاً من زر Skip
                      if (_isSpeaking && _currentPage == index)
                        Row(
                          children: [
                            Text(
                              "Speaking...",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: const Color(0xFFB14ABA),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        )
                      else
                        const SizedBox(width: 100), // للحفاظ على التوازن
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ✅ الصورة مع تأثير للجذب البصري
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOut,
                      child: Image.asset(images[index], fit: BoxFit.contain),
                    ),
                  ),

                  // ✅ العنوان مع تأثير الظهور
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 500),
                    opacity: 1.0,
                    child: Text(
                      titles[index],
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ✅ الوصف مع تأثير الظهور
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 500),
                    opacity: 1.0,
                    child: Text(
                      subtitles[index],
                      style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 30),

                  // ✅ مؤشرات التقدم فقط (بدون أزرار)
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(images.length, (i) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _currentPage ? 30 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _currentPage
                                ? const Color(0xFFB14ABA)
                                : Colors.grey[400],
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ✅ تعليمات للمستخدم
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 500),
                    opacity: _isSpeaking ? 0.0 : 1.0,
                    child: const Text(
                      "Tap anywhere to continue",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
