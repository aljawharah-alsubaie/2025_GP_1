import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'welcome_screen.dart';
import '../providers/language_provider.dart';

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
    final languageCode = Provider.of<LanguageProvider>(context, listen: false).languageCode;
    
    // تحديد اللغة بناءً على اختيار المستخدم
    await _flutterTts.setLanguage(
      languageCode == 'ar' ? 'ar-SA' : 'en-US',
    );
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);

    _speakCurrentPage();
  }

  void _speakCurrentPage() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
    }

    setState(() {
      _isSpeaking = true;
    });

    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    String fullText;
    
    if (_currentPage == 0) {
      fullText = "${languageProvider.translate('welcomeToMunir')}. ${languageProvider.translate('aiCompanion')}";
    } else {
      fullText = "${languageProvider.translate('smartAssistance')}. ${languageProvider.translate('readTextRecognize')}";
    }

    await _flutterTts.speak(fullText);

    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
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

  void _startAutoPlay() {}

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
    _flutterTts.stop();
    _nextPage();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
    _speakCurrentPage();
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    final titles = [
      languageProvider.translate('welcomeToMunir'),
      languageProvider.translate('smartAssistance'),
    ];
    
    final subtitles = [
      languageProvider.translate('aiCompanion'),
      languageProvider.translate('readTextRecognize'),
    ];

    return Scaffold(
      body: GestureDetector(
        onTap: _onPageTap,
        child: PageView.builder(
          controller: _pageController,
          itemCount: images.length,
          onPageChanged: _onPageChanged,
          physics: const ClampingScrollPhysics(),
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
                              decoration: const BoxDecoration(
                                color: Color(0xFFB14ABA),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        )
                      else
                        const SizedBox(width: 100),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOut,
                      child: Image.asset(images[index], fit: BoxFit.contain),
                    ),
                  ),
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
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 500),
                    opacity: _isSpeaking ? 0.0 : 1.0,
                    child: Text(
                      languageProvider.translate('tapToContinue'),
                      style: const TextStyle(
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