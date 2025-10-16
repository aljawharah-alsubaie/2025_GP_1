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
import './location_permission_screen.dart';
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

  String _userName = 'User';
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
    await _tts.setLanguage("en-US");
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
        padding: const EdgeInsets.fromLTRB(
          25,
          45,
          25,
          55,
        ), // زيادة المسافة من الأعلى والأسفل

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
                    width: 52,
                    height: 52,
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
                    child: Center(
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
                      fontSize: 13,
                      color: deepPurple.withOpacity(0.5),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _userName,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      foreground: Paint()
                        ..shader = LinearGradient(
                          colors: [deepPurple, vibrantPurple],
                        ).createShader(Rect.fromLTWH(0, 0, 200, 70)),
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
                  _hapticFeedback();
                  _speak('Profile');
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
        padding: const EdgeInsets.fromLTRB(
          16,
          20,
          16,
          16,
        ), // زيادة المسافة من الأعلى
        children: [
          _buildNeumorphicCard(
            title: 'Face Recognition',
            subtitle: 'Identify people instantly',
            icon: Icons.face_retouching_natural,
            gradient: LinearGradient(colors: [deepPurple, vibrantPurple]),
            onTap: () {
              _hapticFeedback();
              _speak('Face Recognition');
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FaceListPage()),
              );
            },
          ),

          _buildNeumorphicCard(
            title: 'Emergency SOS',
            subtitle: 'Quick emergency contacts',
            icon: Icons.emergency_outlined,
            gradient: LinearGradient(colors: [vibrantPurple, primaryPurple]),
            onTap: () {
              _hapticFeedback();
              _speak('Emergency Contact');
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ContactInfoPage(),
                ),
              );
            },
          ),

          _buildNeumorphicCard(
            title: 'Text Reading',
            subtitle: 'Read any text aloud',
            icon: Icons.record_voice_over,
            gradient: LinearGradient(colors: [deepPurple, vibrantPurple]),
            onTap: () {
              _hapticFeedback();
              _speak('Text Reading');
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
            gradient: LinearGradient(colors: [deepPurple, vibrantPurple]),
            onTap: () {
              _hapticFeedback();
              _speak('Currency Recognition');
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
            gradient: LinearGradient(colors: [vibrantPurple, primaryPurple]),
            onTap: () {
              _hapticFeedback();
              _speak('Color Identification');
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

  // 🎯 كارت Neumorphic مع مسافات أكبر ونص أكبر وسهم على اليمين
  Widget _buildNeumorphicCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: '$title. $subtitle. Double tap to open',
      button: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: palePurple.withOpacity(0.35),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(0.8),
                    blurRadius: 12,
                    offset: const Offset(-2, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // الأيقونة المتدرجة
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: gradient,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: gradient.colors.first.withOpacity(0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 28),
                  ),

                  const SizedBox(width: 14),
                  // النص - أكبر حجماً
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 17, // حجم متوسط
                            fontWeight: FontWeight.w700,
                            color: deepPurple,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13, // حجم متوسط
                            color: deepPurple.withOpacity(0.5),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),
                  // سهم متدرج على اليمين
                  Container(
                    padding: const EdgeInsets.all(6),
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
                      size: 14,
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

  // ⚠️ تنبيه البروفايل
  Widget _buildProfileAlert() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Semantics(
          label: 'Profile incomplete. Complete your profile to unlock features',
          child: Container(
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
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
                    gradient: LinearGradient(
                      colors: [vibrantPurple, primaryPurple],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.person_add_alt_1,
                        color: Colors.white,
                        size: 64,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Complete Your Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    children: [
                      Text(
                        'Add your personal details to unlock all features',
                        style: TextStyle(
                          fontSize: 16,
                          color: deepPurple.withOpacity(0.6),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),

                      Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              label: 'Later button',
                              button: true,
                              child: OutlinedButton(
                                onPressed: () {
                                  _hapticFeedback();
                                  _speak('Dismissed');
                                  setState(() => _isDismissed = true);
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                  side: BorderSide(
                                    color: lightPurple,
                                    width: 2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                child: Text(
                                  'Later',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: vibrantPurple,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: Semantics(
                              label: 'Complete now button',
                              button: true,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
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
                                    _speak('Opening profile');
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const ProfilePage(),
                                      ),
                                    ).then((_) {
                                      _checkProfileCompleteness();
                                      _loadUserName();
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 18,
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
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
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

  // 📍 Bottom Navigation بخلفية موف غامقة
  Widget _buildFloatingBottomNav() {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
      ),
      child: Container(
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavButton(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  isActive: true,
                  onTap: () {
                    _hapticFeedback();
                    _speak('Home');
                  },
                ),
                _buildNavButton(
                  icon: Icons.notifications_rounded,
                  label: 'Reminders',
                  onTap: () {
                    _hapticFeedback();
                    _speak('Reminders');
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RemindersPage(),
                      ),
                    );
                  },
                ),
                _buildNavButton(
                  icon: Icons.emergency,
                  label: 'Emergency',
                  onTap: () async {
                    _hapticFeedback();
                    _speak('Emergency');
                    final user = _auth.currentUser;
                    if (user != null) {
                      final doc = await _firestore
                          .collection('users')
                          .doc(user.uid)
                          .get();
                      final data = doc.data();
                      final permissionGranted =
                          data?['location_permission_granted'] ?? false;
                      if (!permissionGranted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LocationPermissionScreen(
                              onPermissionGranted: () async {
                                await _firestore
                                    .collection('users')
                                    .doc(user.uid)
                                    .update({
                                      'location_permission_granted': true,
                                    });
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SosScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SosScreen(),
                          ),
                        );
                      }
                    }
                  },
                ),
                _buildNavButton(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  onTap: () {
                    _hapticFeedback();
                    _speak('Settings');
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
    );
  }

  // 🔘 زر Navigation بألوان فاتحة للخلفية الغامقة
  Widget _buildNavButton({
    required IconData icon,
    required String label,
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
                  fontSize: 11,
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
