import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import './profile.dart';
import './face_list.dart';
import './camera.dart';
import './settings.dart';
import './reminders.dart';
import './sos_screen.dart';
import './contact_info_page.dart';
import './currency_camera.dart';
import 'camera_text_screen.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final FlutterTts _tts = FlutterTts();

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _floatController;

  String _userName = '';
  
  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadUserName();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  Future<void> _initTts() async {
    final languageCode = Provider.of<LanguageProvider>(context, listen: false).languageCode;
    await _tts.setLanguage(languageCode == 'ar' ? 'ar-SA' : 'en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> _loadUserName() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data();
          setState(() {
            _userName = data?['full_name']?.toString().trim() ?? 'User';
            if (_userName.isEmpty) _userName = 'User';
          });
        }
      }
    } catch (e) {
      print('Error loading user name: $e');
    }
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  Future<void> _explainFeature(String featureName, String description) async {
    _hapticFeedback();
    await _speak('$featureName. $description');
  }

  @override
  void dispose() {
    _tts.stop();
    _fadeController.dispose();
    _slideController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ultraLightPurple,
      body: Stack(
        children: [
          _buildGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildModernHeader(),
                Expanded(child: _buildFeaturesList()),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildFloatingBottomNav(),
    );
  }

  Widget _buildGradientBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ultraLightPurple, palePurple.withOpacity(0.3), Colors.white],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  Widget _buildModernHeader() {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return FadeTransition(
      opacity: _fadeController,
      child: Container(
        padding: const EdgeInsets.fromLTRB(25, 45, 25, 55),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withOpacity(0.9),
              Colors.white.withOpacity(0.7),
              const Color.fromARGB(198, 255, 255, 255),
              const Color.fromARGB(195, 240, 224, 245),
            ],
          ),
        ),
        child: Row(
          children: [
            // 🕶️ نظارة متحركة
            AnimatedBuilder(
              animation: _floatController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, -5 * _floatController.value),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: vibrantPurple.withOpacity(0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text('🕶️', style: TextStyle(fontSize: 35)),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(width: 16),

            // النص
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    languageProvider.isArabic ? 'مرحباً بعودتك' : 'Welcome Back',
                    style: TextStyle(
                      fontSize: 14,
                      color: deepPurple.withOpacity(0.7),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _userName,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      foreground: Paint()
                        ..shader = LinearGradient(
                          colors: [deepPurple, vibrantPurple],
                        ).createShader(const Rect.fromLTWH(0, 0, 200, 70)),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // زر البروفايل
            Semantics(
              label: 'Profile settings',
              button: true,
              child: GestureDetector(
                onTap: () {
                  final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
                  _explainFeature(
                    languageProvider.isArabic ? 'الملف الشخصي' : 'Profile',
                    languageProvider.isArabic
                        ? 'إدارة معلوماتك الشخصية'
                        : 'Manage your personal information',
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfilePage(),
                    ),
                  ).then((_) {
                    _loadUserName();
                  });
                },
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [vibrantPurple, primaryPurple],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: vibrantPurple.withOpacity(0.3),
                        blurRadius: 5,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesList() {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _slideController,
              curve: Curves.easeOutCubic,
            ),
          ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 25, 20, 36),
        children: [
          _buildNeumorphicCard(
            title: languageProvider.isArabic ? 'التعرف على الوجوه' : 'Face Recognition',
            subtitle: languageProvider.isArabic
                ? 'تعرّف على الأشخاص فوراً'
                : 'Identify people instantly',
            icon: Icons.face_retouching_natural,
            gradient: LinearGradient(colors: [deepPurple, vibrantPurple]),
            description: languageProvider.isArabic
                ? 'هذه الميزة تساعدك على التعرف على الوجوه والأشخاص من حولك باستخدام الكاميرا'
                : 'This feature helps you recognize faces and identify people around you using camera',
            onTap: () {
              _explainFeature(
                languageProvider.isArabic ? 'التعرف على الوجوه' : 'Face Recognition',
                '',
              );
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FaceListPage()),
              );
            },
          ),

          _buildNeumorphicCard(
            title: languageProvider.isArabic ? 'قراءة النصوص' : 'Text Reading',
            subtitle: languageProvider.isArabic
                ? 'قراءة النص بصوت عالٍ'
                : 'Read text aloud',
            icon: Icons.record_voice_over,
            gradient: const LinearGradient(colors: [deepPurple, vibrantPurple]),
            description: languageProvider.isArabic
                ? 'هذه الميزة تقرأ النصوص من المستندات واللافتات أو أي مادة مكتوبة باستخدام الكاميرا'
                : 'This feature reads text from documents, signs, or any written material using your camera',
            onTap: () {
              _explainFeature(
                languageProvider.isArabic ? 'قراءة النصوص' : 'Text Reading',
                languageProvider.isArabic
                    ? 'وجّه الكاميرا إلى أي نص. التطبيق سيكتشفه ويقرأه بصوت عالٍ'
                    : 'Point your camera at any text. The app will detect it and read it aloud for you.',
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CameraTextScreen(),
                ),
              );
            },
          ),

          _buildNeumorphicCard(
            title: languageProvider.isArabic ? 'التعرف على العملات' : 'Currency Recognition',
            subtitle: languageProvider.isArabic
                ? 'تعرّف على العملة فوراً'
                : 'Recognize currency instantly',
            icon: Icons.monetization_on,
            gradient: const LinearGradient(colors: [deepPurple, vibrantPurple]),
            description: languageProvider.isArabic
                ? 'هذه الميزة تساعدك على التعرف على الأوراق النقدية المختلفة وقيمها'
                : 'This feature helps you identify different currency notes and their values',
            onTap: () {
              _explainFeature(
                languageProvider.isArabic ? 'التعرف على العملات' : 'Currency Recognition',
                languageProvider.isArabic
                    ? 'وجّه الكاميرا إلى ورقة نقدية وسيخبرك التطبيق بقيمتها'
                    : 'Point your camera at a banknote and the app will tell you its value',
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CurrencyCameraScreen(),
                ),
              );
            },
          ),

          _buildNeumorphicCard(
            title: languageProvider.isArabic ? 'تحديد الألوان' : 'Color Identification',
            subtitle: languageProvider.isArabic
                ? 'تعرّف على الألوان من حولك'
                : 'Identify colors around you',
            icon: Icons.palette,
            gradient: const LinearGradient(
              colors: [vibrantPurple, primaryPurple],
            ),
            description: languageProvider.isArabic
                ? 'هذه الميزة تكتشف وتعلن عن ألوان الأشياء من حولك باستخدام الكاميرا'
                : 'This feature detects and announces colors of objects around you using your camera',
            onTap: () {
              _explainFeature(
                languageProvider.isArabic ? 'تحديد الألوان' : 'Color Identification',
                languageProvider.isArabic
                    ? 'وجّه الكاميرا إلى شيء وسيصفه التطبيق ويخبرك بلونه'
                    : 'Point your camera at an object and the app will describe it and tell you its color',
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CameraScreen(mode: 'color'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNeumorphicCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Gradient gradient,
    required String description,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: '$title. $subtitle. Double tap to open',
      button: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 26),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 23),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: palePurple.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(0.9),
                    blurRadius: 8,
                    offset: const Offset(-2, -2),
                  ),
                ],
              ),
              constraints: const BoxConstraints(minHeight: 90),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 55,
                    height: 55,
                    decoration: BoxDecoration(
                      gradient: gradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: gradient.colors.first.withOpacity(0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 28),
                  ),

                  const SizedBox(width: 16),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: deepPurple,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: deepPurple.withOpacity(0.6),
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          gradient.colors.first.withOpacity(0.1),
                          gradient.colors.last.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: gradient.colors.first,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBottomNav() {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          child: Container(
            height: 95,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  deepPurple.withOpacity(0.95),
                  vibrantPurple.withOpacity(0.98),
                  primaryPurple,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: deepPurple.withOpacity(0.3),
                  blurRadius: 25,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildNavButton(
                      icon: Icons.home_rounded,
                      label: languageProvider.isArabic ? 'الرئيسية' : 'Home',
                      isActive: true,
                      description: languageProvider.isArabic
                          ? 'أنت في الصفحة الرئيسية'
                          : 'You are on the home screen',
                      onTap: () {
                        _hapticFeedback();
                        _speak(languageProvider.isArabic
                            ? 'أنت بالفعل في الصفحة الرئيسية'
                            : 'You are already on homepage');
                      },
                    ),
                    _buildNavButton(
                      icon: Icons.notifications_rounded,
                      label: languageProvider.isArabic ? 'التذكيرات' : 'Reminders',
                      description: languageProvider.isArabic
                          ? 'إدارة التذكيرات والإشعارات'
                          : 'Manage your reminders and notifications',
                      onTap: () {
                        _explainFeature(
                          languageProvider.isArabic ? 'التذكيرات' : 'Reminders',
                          languageProvider.isArabic
                              ? 'أنشئ وأدر التذكيرات، وسيخطرك التطبيق في الوقت المناسب'
                              : 'Create and manage reminders, and the app will notify you at the right time',
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RemindersPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 60),
                    _buildNavButton(
                      icon: Icons.contacts_rounded,
                      label: languageProvider.isArabic ? 'جهات الاتصال' : 'Contacts',
                      description: languageProvider.isArabic
                          ? 'إدارة جهات الاتصال الطارئة والأشخاص المهمين'
                          : 'Manage your emergency contacts and important people',
                      onTap: () {
                        _explainFeature(
                          languageProvider.isArabic ? 'جهات الاتصال' : 'Contact',
                          languageProvider.isArabic
                              ? 'احفظ وأدر جهات الاتصال الطارئة'
                              : 'Store and manage emergency contacts',
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ContactInfoPage(),
                          ),
                        );
                      },
                    ),
                    _buildNavButton(
                      icon: Icons.settings_rounded,
                      label: languageProvider.isArabic ? 'الإعدادات' : 'Settings',
                      description: languageProvider.isArabic
                          ? 'ضبط إعدادات التطبيق والتفضيلات'
                          : 'Adjust app settings and preferences',
                      onTap: () {
                        _explainFeature(
                          languageProvider.isArabic ? 'الإعدادات' : 'Settings',
                          languageProvider.isArabic
                              ? 'إدارة الإعدادات والتفضيلات'
                              : 'Manage your settings and preferences',
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        Positioned(
          bottom: 40,
          child: GestureDetector(
            onTap: () {
              final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
              _hapticFeedback();
              _explainFeature(
                languageProvider.isArabic ? 'طوارئ' : 'Emergency SOS',
                languageProvider.isArabic
                    ? 'يرسل تنبيه طوارئ لجهات الاتصال الموثوقة عندما تحتاج مساعدة'
                    : 'Sends an emergency alert to your trusted contacts when you need help',
              );
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SosScreen()),
              );
            },
            child: Container(
              width: 75,
              height: 75,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.red.shade400, Colors.red.shade700],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.6),
                    blurRadius: 25,
                    spreadRadius: 5,
                  ),
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 40,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: const Icon(
                Icons.emergency_outlined,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String label,
    required String description,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: '$label button',
      button: true,
      selected: isActive,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white.withOpacity(0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isActive
                ? Border.all(color: Colors.white.withOpacity(0.3), width: 1.5)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive
                    ? Colors.white
                    : const Color.fromARGB(255, 255, 253, 253).withOpacity(0.9),
                size: 25,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withOpacity(0.9),
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}