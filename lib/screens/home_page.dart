import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_tts/flutter_tts.dart';
import './profile.dart';
import './face_list.dart';
import './camera.dart';
import './settings.dart';
import './reminders.dart';
import './sos_screen.dart';
import './contact_info_page.dart';
import './currency_camera.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final FlutterTts _tts = FlutterTts();

  bool _isProfileIncomplete = false;
  bool _isLoading = true;
  bool _isDismissed = false;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _floatController;

  String _userName = '';
  // 🎨 نظام ألوان موف جديد
  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color lightPurple = Color.fromARGB(255, 217, 163, 227);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadUserName();
    _checkProfileCompleteness();

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
    await _tts.setLanguage("eUSn-");
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

  // ✅ دالة جديدة لشرح كل خيار
  Future<void> _explainFeature(String featureName, String description) async {
    _hapticFeedback();
    await _speak('$featureName. $description');
  }

  Future<void> _checkProfileCompleteness() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data();
          final bool isIncomplete =
              (data?['full_name']?.toString().trim().isEmpty ?? true) ||
              (data?['phone']?.toString().trim().isEmpty ?? true);

          final lastShown = data?['profile_reminder_last_shown'] as Timestamp?;
          final now = DateTime.now();

          bool shouldShow = false;
          if (isIncomplete) {
            if (lastShown == null) {
              shouldShow = true;
            } else {
              final daysSinceLastShown = now
                  .difference(lastShown.toDate())
                  .inDays;
              shouldShow = daysSinceLastShown >= 3;
            }
          }

          setState(() {
            _isProfileIncomplete = shouldShow;
            _isLoading = false;
          });

          if (shouldShow) {
            await _firestore.collection('users').doc(user.uid).update({
              'profile_reminder_last_shown': Timestamp.now(),
            });
          }
        } else {
          setState(() {
            _isProfileIncomplete = true;
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error checking profile: $e');
      setState(() {
        _isLoading = false;
      });
    }
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
          // 🎨 خلفية متدرجة
          _buildGradientBackground(),

          // 🎯 الهيدر الجديد فوق تماماً
          SafeArea(
            child: Column(
              children: [
                _buildModernHeader(),
                Expanded(child: _buildFeaturesList()),
              ],
            ),
          ),

          if (!_isLoading && _isProfileIncomplete && !_isDismissed)
            _buildProfileAlert(),
        ],
      ),

      bottomNavigationBar: _buildFloatingBottomNav(),
    );
  }

  // 🎨 خلفية متدرجة
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

  // 🎯 هيدر جديد - أكبر حجماً
  Widget _buildModernHeader() {
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
            // 🕶️ نظارة متحركة على اليسار - أكبر
            AnimatedBuilder(
              animation: _floatController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, -5 * _floatController.value),
                  child: Container(
                    width: 54,
                    height: 54,
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
                      child: Text('🕶️', style: TextStyle(fontSize: 32)),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(width: 16),

            // النص في المنتصف - أكبر
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome Back',
                    style: TextStyle(
                      fontSize: 14,
                      color: deepPurple.withOpacity(0.7),
                      fontWeight: FontWeight.w800,
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

            // زر البروفايل ثابت على اليمين - أكبر
            Semantics(
              label: 'Profile settings',
              button: true,
              child: GestureDetector(
                onTap: () {
                  _explainFeature(
                    'Profile',
                    'Manage your personal information',
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfilePage(),
                    ),
                  ).then((_) {
                    _checkProfileCompleteness();
                    _loadUserName();
                  });
                },
                child: Container(
                  width: 53,
                  height: 53,
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
                    size: 25,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 📜 قائمة الميزات - مسافات أكبر
  Widget _buildFeaturesList() {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _slideController,
              curve: Curves.easeOutCubic,
            ),
          ),
      child: ListView(
        // كان: EdgeInsets.fromLTRB(16, 35, 16, 20)
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 36),
        children: [
          _buildNeumorphicCard(
            title: 'Text Reading',
            subtitle: 'Read any text aloud',
            icon: Icons.record_voice_over,
            gradient: const LinearGradient(colors: [deepPurple, vibrantPurple]),
            description:
                'This feature reads text from documents, signs, or any written material using your camera',
            onTap: () {
              _explainFeature(
                'Text Reading',
                'Point your camera at any text. The app will detect it and read it aloud for you.',
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CameraScreen(mode: 'text'),
                ),
              );
            },
          ),
          _buildNeumorphicCard(
            title: 'Currency Scanner',
            subtitle: 'Identify money instantly',
            icon: Icons.monetization_on,
            gradient: const LinearGradient(colors: [deepPurple, vibrantPurple]),
            description:
                'This feature helps you identify different currency notes and their values',
            onTap: () {
              _explainFeature(
                'Currency Recognition',
                'Point your camera at a banknote and the app will tell you its value',
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
            title: 'Color Detector',
            subtitle: 'Identify colors around you',
            icon: Icons.palette,
            gradient: const LinearGradient(
              colors: [vibrantPurple, primaryPurple],
            ),
            description:
                'This feature detects and announces colors of objects around you using your camera',
            onTap: () {
              _explainFeature(
                'Color Identification',
                'Point your camera at an object and the app will describe it and tell you its color',
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

  // 🎯 كارت Neumorphic أكبر + مسافات أوسع
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
        // كان: EdgeInsets.only(bottom: 30)
        margin: const EdgeInsets.only(bottom: 36),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              // كان: EdgeInsets.all(18)
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: palePurple.withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(0.85),
                    blurRadius: 14,
                    offset: const Offset(-2, -2),
                  ),
                ],
              ),
              // ✅ أقل ارتفاع للكرت عشان يكبر بصريًا
              constraints: const BoxConstraints(minHeight: 112),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // الأيقونة المتدرجة (أكبر)
                  Container(
                    // كان: 58x58
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      gradient: gradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: gradient.colors.first.withOpacity(0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    // كان: size 30
                    child: Icon(icon, color: Colors.white, size: 34),
                  ),

                  const SizedBox(width: 18),

                  // النصوص أكبر
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            // كان: 17.5
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: deepPurple,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(
                            // كان: 13
                            fontSize: 14.5,
                            color: deepPurple.withOpacity(0.55),
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // سهم أكبر ومساحة لمس أوسع
                  Container(
                    // كان: padding 7
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          gradient.colors.first.withOpacity(0.12),
                          gradient.colors.last.withOpacity(0.12),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios,
                      // كان: 15
                      size: 18,
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

  Widget _buildProfileAlert() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Semantics(
          label: 'Profile incomplete. Complete your profile to unlock features',
          hint: 'Double tap to hear details',
          liveRegion: true,
          child: Container(
            margin: const EdgeInsets.all(31),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: vibrantPurple, width: 2),
              boxShadow: [
                BoxShadow(
                  color: vibrantPurple.withOpacity(0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [vibrantPurple, primaryPurple],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: Semantics(
                    header: true,
                    child: Column(
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            Icons.person_add_alt_1,
                            color: Colors.white,
                            size: 70,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Complete Your Profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    children: [
                      Text(
                        'Add your personal details to unlock all features',
                        style: TextStyle(
                          fontSize: 18,
                          color: deepPurple.withOpacity(0.7),
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      Column(
                        children: [
                          // الزر الأساسي
                          Semantics(
                            label: 'Complete now button. Go to profile page',
                            hint: 'Double tap to open profile',
                            button: true,
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [vibrantPurple, primaryPurple],
                                ),
                                borderRadius: BorderRadius.circular(15),
                                boxShadow: [
                                  BoxShadow(
                                    color: vibrantPurple.withOpacity(0.4),
                                    blurRadius: 15,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: () {
                                  _hapticFeedback();
                                  _explainFeature(
                                    'Profile',
                                    'Opening profile page to complete your information',
                                  );
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const ProfilePage(),
                                    ),
                                  ).then((_) {
                                    _checkProfileCompleteness();
                                    _loadUserName();
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 22,
                                  ),
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                child: const Text(
                                  'Complete Now',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          // زر Later
                          Semantics(
                            label: 'Later button. Dismiss this alert',
                            hint: 'Double tap to dismiss',
                            button: true,
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () {
                                  _hapticFeedback();
                                  _speak('Dismissed');
                                  setState(() => _isDismissed = true);
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 22,
                                  ),
                                  side: BorderSide(
                                    color: lightPurple,
                                    width: 2.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                child: const Text(
                                  'Later',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: vibrantPurple,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBottomNav() {
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none, // مهم عشان الدائرة تطلع فوق
      children: [
        // الفوتر الأساسي
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          child: Container(
            height: 90, // ارتفاع أكبر للفوتر
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildNavButton(
                      icon: Icons.home_rounded,
                      label: 'Home',
                      isActive: true,
                      description: 'You are on the home screen',
                      onTap: () {
                        _hapticFeedback();
                        _explainFeature(
                          'Home',
                          'You are already on the home screen',
                        );
                      },
                    ),
                    _buildNavButton(
                      icon: Icons.notifications_rounded,
                      label: 'Reminders',
                      description: 'Manage your reminders and notifications',
                      onTap: () {
                        _explainFeature(
                          'Reminders',
                          'Create and manage reminders, and the app will notify you at the right time.',
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RemindersPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 60), // مساحة للدائرة
                    // ✅ زر Contact - يودي لصفحة جهات الاتصال
                    _buildNavButton(
                      icon: Icons.contacts_rounded,
                      label: 'Contacts',
                      description:
                          'Manage your emergency contacts and important people',
                      onTap: () {
                        _explainFeature(
                          'Contact',
                          'Store and manage emergency contacts',
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
                      label: 'Settings',
                      description: 'Adjust app settings and preferences',
                      onTap: () {
                        _explainFeature(
                          'Settings',
                          'Manage your app settings and preferences',
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

        // 🔴 الدائرة الكبيرة للطوارئ - تودي لصفحة SOS
        Positioned(
          bottom: 35, // نزلت من 45 إلى 35
          child: GestureDetector(
            onTap: () {
              _hapticFeedback();
              _explainFeature(
                'Emergency SOS',
                'Sends an emergency alert to your trusted contacts when you need help',
              );
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SosScreen()),
              );
            },
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.red.shade400, Colors.red.shade700],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.6),
                    blurRadius: 25,
                    spreadRadius: 3,
                  ),
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 40,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.emergency_outlined,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 🔘 زر Navigation بألوان فاتحة للخلفية الغامقة
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                size: 22,
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
