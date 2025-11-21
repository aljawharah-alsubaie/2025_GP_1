import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'home_page.dart';
import 'accountinfopage.dart';
import 'DeviceAlertsPage .dart';
import 'securitydatapage.dart';
import 'login_screen.dart';
import 'Reminders.dart';
import 'contact_info_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import './sos_screen.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with TickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  late AnimationController _fadeController;
  late AnimationController _slideController;

  // 🎨 نظام ألوان موحد
  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);

  // ✅ تحكم في ظهور خيار تغيير الباسوورد
  bool _canChangePassword = false;
  bool _providerLoaded = false;

  @override
  void initState() {
    super.initState();
    _initTts();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    // ✅ تحديد ما إذا كان المستخدم يستخدم Email/Password أو لا
    _checkUserProvider();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  // ✅ فحص مزوّد تسجيل الدخول (Google ولا Email/Password)
  Future<void> _checkUserProvider() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() {
        _canChangePassword = false;
        _providerLoaded = true;
      });
      return;
    }

    try {
      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      final providers = refreshedUser?.providerData ?? [];

      final hasPasswordProvider = providers.any(
        (p) => p.providerId == 'password',
      ); // Email/Password

      setState(() {
        _canChangePassword = hasPasswordProvider;
        _providerLoaded = true;
      });
    } catch (e) {
      // لو صار خطأ نخفي الخيار احتياطياً
      setState(() {
        _canChangePassword = false;
        _providerLoaded = true;
      });
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _logout(BuildContext context) async {
    final outerContext = context; // نستخدمه لإظهار SnackBar فوق كل شيء

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFD32F2F),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(35),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout, color: Colors.white, size: 52),
            ),
            const SizedBox(height: 20),
            const Text(
              'Logout',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 26,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to log out from your account?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 19,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        actions: [
          Column(
            children: [
              // Confirm (أبيض بنص أحمر)
              SizedBox(
                width: double.infinity,
                height: 75,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: TextButton(
                    onPressed: () async {
                      _hapticFeedback();

                      // 1) سكّر الدايلوج فوراً عشان المسج تطلع فوق الخلفية
                      Navigator.pop(context, true);

                      // 2) أظهر المسج فوراً على Scaffold الخارجي
                      ScaffoldMessenger.of(outerContext)
                        ..clearSnackBars()
                        ..showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Colors.green,
                            elevation: 14,
                            margin: const EdgeInsets.all(16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            duration: const Duration(seconds: 2),
                            content: SizedBox(
                              height: 40,
                              child: Row(
                                children: const [
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Logout successfully',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );

                      // 3) يتكلم
                      try {
                        await _tts.stop();
                        await _tts.setLanguage('en-US');
                        await _tts.setSpeechRate(0.5);
                        await _tts.speak(
                          'Logout successfully. Redirecting to login.',
                        );
                        await Future.delayed(const Duration(milliseconds: 200));
                      } catch (_) {}

                      // 4) نفّذ اللوق آوت ثم انتقل
                      try {
                        const storage = FlutterSecureStorage();
                        await storage.deleteAll();
                        await FirebaseAuth.instance.signOut();

                        if (mounted) {
                          Navigator.of(outerContext).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                            (route) => false,
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(outerContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Failed to logout. Please try again.',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(
                        color: Color(0xFFD32F2F),
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 25),

              // Cancel
              SizedBox(
                width: double.infinity,
                height: 65,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: TextButton(
                    onPressed: () {
                      _hapticFeedback();
                      () async {
                        try {
                          await _tts.stop();
                          await _tts.setLanguage('en-US');
                          await _tts.setSpeechRate(0.5);
                          await _tts.speak('Cancel');
                        } catch (_) {}
                      }();
                      Navigator.pop(context, false);
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
                Expanded(child: _buildSettingsList()),
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
    return FadeTransition(
      opacity: _fadeController,
      child: Container(
        padding: const EdgeInsets.fromLTRB(25, 50, 25, 45),
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
            Semantics(
              label: 'Go back to previous page',
              button: true,
              child: GestureDetector(
                onTap: () {
                  _hapticFeedback();
                  _tts.stop();
                  _speak('Going back');
                  Future.delayed(const Duration(milliseconds: 800), () {
                    Navigator.pop(context);
                  });
                },
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [vibrantPurple, primaryPurple],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: vibrantPurple.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      foreground: Paint()
                        ..shader = const LinearGradient(
                          colors: [deepPurple, vibrantPurple],
                        ).createShader(const Rect.fromLTWH(0, 0, 200, 70)),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage your preferences',
                    style: TextStyle(
                      fontSize: 14,
                      color: deepPurple.withOpacity(0.6),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsList() {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _slideController,
              curve: Curves.easeOutCubic,
            ),
          ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 35, 16, 16),
        children: [
          _buildSettingCard(
            title: 'Account Info',
            subtitle: 'Edit personal info or delete your account',
            icon: Icons.person_outline,
            gradient: const LinearGradient(colors: [deepPurple, vibrantPurple]),
            onTap: () {
              _hapticFeedback();
              _speak(
                'Account Info. Edit your personal details, or delete your account permanently',
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AccountInfoPage(),
                ),
              );
            },
          ),
          _buildSettingCard(
            title: 'Device & Alerts',
            subtitle: 'Set up connections and notifications',
            icon: Icons.notifications_active_outlined,
            gradient: const LinearGradient(
              colors: [vibrantPurple, primaryPurple],
            ),
            onTap: () {
              _hapticFeedback();
              _speak(
                'Device and Alerts. Manage connected devices and customize your notifications',
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DeviceAlertsPage(),
                ),
              );
            },
          ),

          // ✅ يظهر فقط إذا المستخدم مسجل Email/Password
          if (_providerLoaded && _canChangePassword)
            _buildSettingCard(
              title: 'Change Password',
              subtitle: 'Manage your password',
              icon: Icons.lock_outline,
              gradient: const LinearGradient(
                colors: [deepPurple, vibrantPurple],
              ),
              onTap: () {
                _hapticFeedback();
                _speak('Change Password. Update your password securely');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SecurityDataPage(),
                  ),
                );
              },
            ),

          // 🔴 كرت الـ Logout
          _buildSettingCard(
            title: 'Logout',
            subtitle: 'Sign out of your account',
            icon: Icons.logout_outlined,
            gradient: const LinearGradient(
              colors: [Color(0xFFE53935), Color(0xFFD32F2F)],
            ),
            isDanger: true,
            onTap: () {
              _hapticFeedback();
              _speak(
                'Logout. Are you sure you want to log out? Buttons: Confirm on the top, Cancel at the bottom',
              );
              _logout(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Gradient gradient,
    required VoidCallback onTap,
    bool isDanger = false,
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
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: isDanger
                    ? const LinearGradient(
                        colors: [Color(0xFFE53935), Color(0xFFD32F2F)],
                      )
                    : null,
                color: isDanger ? null : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: isDanger
                        ? const Color(0xFFE53935).withOpacity(0.4)
                        : palePurple.withOpacity(0.35),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: isDanger
                        ? const Color(0xFFFF5252).withOpacity(0.3)
                        : Colors.white.withOpacity(0.8),
                    blurRadius: 12,
                    offset: const Offset(-2, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: isDanger ? Colors.white.withOpacity(0.25) : null,
                      gradient: isDanger ? null : gradient,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: isDanger
                          ? []
                          : [
                              BoxShadow(
                                color: gradient.colors.first.withOpacity(0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w700,
                            color: isDanger ? Colors.white : deepPurple,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDanger
                                ? Colors.white.withOpacity(0.95)
                                : deepPurple.withOpacity(0.7),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: isDanger ? Colors.white.withOpacity(0.2) : null,
                      gradient: isDanger
                          ? null
                          : LinearGradient(
                              colors: [
                                gradient.colors.first.withOpacity(0.1),
                                gradient.colors.last.withOpacity(0.1),
                              ],
                            ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios,
                      size: 15,
                      color: isDanger ? Colors.white : gradient.colors.first,
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
                      label: 'Home',
                      isActive: false,
                      onTap: () {
                        _hapticFeedback();
                        _speak('Navigate to Homepage');
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HomePage(),
                          ),
                        );
                      },
                    ),
                    _buildNavButton(
                      icon: Icons.notifications_rounded,
                      label: 'Reminders',
                      isActive: false,
                      onTap: () {
                        _hapticFeedback();
                        _speak(
                          'Reminders, Create and manage reminders, and the app will notify you at the right time',
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
                      label: 'Contacts',
                      isActive: false,
                      onTap: () {
                        _hapticFeedback();
                        _speak('Contacts, Store and manage emergency contacts');
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
                      isActive: true,
                      onTap: () {
                        _hapticFeedback();
                        _speak('You are already on Settings page');
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
          child: Semantics(
            label: 'Emergency SOS button',
            button: true,
            hint: 'Double tap for emergency',
            child: GestureDetector(
              onTap: () {
                _hapticFeedback();
                _speak('Emergency SOS');
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
        ),
      ],
    );
  }

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
                color: isActive ? Colors.white : Colors.white.withOpacity(0.9),
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
