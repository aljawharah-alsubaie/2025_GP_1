import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import './sos_screen.dart';
import 'home_page.dart';
import 'reminders.dart';
import 'contact_info_page.dart';
import 'settings.dart';

class DeviceAlertsPage extends StatefulWidget {
  const DeviceAlertsPage({super.key});

  @override
  State<DeviceAlertsPage> createState() => _DeviceAlertsPageState();
}

class _DeviceAlertsPageState extends State<DeviceAlertsPage>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterTts _tts = FlutterTts();

  bool bluetoothEnabled = false;
  bool deviceAlertsEnabled = false;
  bool isLoading = true;

  late AnimationController _fadeController;
  late AnimationController _slideController;

  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadSettings();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  Future<void> _initTts() async {
    final languageCode = Provider.of<LanguageProvider>(context, listen: false).languageCode;
    await _tts.setLanguage(languageCode == 'ar' ? 'ar-SA' : 'en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _tts.stop();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('device_alerts')
            .get();

        if (doc.exists) {
          final data = doc.data()!;
          setState(() {
            bluetoothEnabled = data['bluetooth_enabled'] ?? false;
            deviceAlertsEnabled = data['device_alerts_enabled'] ?? false;
            isLoading = false;
          });
        } else {
          await _saveSettings();
          setState(() {
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading settings: $e');
      setState(() {
        isLoading = false;
      });
      _showErrorSnackBar(languageProvider.isArabic
          ? 'فشل تحميل الإعدادات'
          : 'Failed to load settings');
    }
  }

  Future<void> _saveSettings() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('device_alerts')
            .set({
              'bluetooth_enabled': bluetoothEnabled,
              'device_alerts_enabled': deviceAlertsEnabled,
              'updated_at': FieldValue.serverTimestamp(),
            });

        _showSuccessSnackBar(languageProvider.isArabic
            ? 'تم حفظ الإعدادات بنجاح'
            : 'Settings saved successfully');
      }
    } catch (e) {
      print('Error saving settings: $e');
      _showErrorSnackBar(languageProvider.isArabic
          ? 'فشل حفظ الإعدادات'
          : 'Failed to save settings');
    }
  }

  void _showOverlaySnackBar(String message, Color color, {int seconds = 2}) {
    if (!mounted) return;

    final overlay = Overlay.of(context, rootOverlay: true);

    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          bottom: 120,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    color == Colors.green
                        ? Icons.check_circle
                        : Icons.error_outline,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);

    Future.delayed(Duration(seconds: seconds), () {
      if (mounted) {
        entry.remove();
      }
    });
  }

  void _showSuccessSnackBar(String message) {
    _showOverlaySnackBar(message, Colors.green, seconds: 2);
  }

  void _showErrorSnackBar(String message) {
    _showOverlaySnackBar(message, const Color(0xFFE53935), seconds: 3);
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
                Expanded(
                  child: isLoading
                      ? Center(
                          child: CircularProgressIndicator(
                            color: vibrantPurple,
                            strokeWidth: 3,
                          ),
                        )
                      : _buildContent(),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [_buildFloatingBottomNav()],
      ),
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
                  _speak(languageProvider.isArabic ? 'العودة' : 'Going back');
                  Future.delayed(const Duration(milliseconds: 800), () {
                    Navigator.pop(context);
                  });
                },
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
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
                  child: Center(
                    child: Icon(
                      languageProvider.isArabic
                          ? Icons.arrow_forward_ios
                          : Icons.arrow_back_ios_new,
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
                    languageProvider.isArabic ? 'الجهاز والتنبيهات' : 'Device & Alerts',
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
                    languageProvider.isArabic
                        ? 'إدارة الإشعارات والأجهزة'
                        : 'Manage notifications & devices',
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

  Widget _buildContent() {
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
        padding: const EdgeInsets.fromLTRB(16, 35, 16, 16),
        children: [
          _buildToggleCard(
            title: languageProvider.isArabic ? 'جهاز البلوتوث' : 'Bluetooth Device',
            subtitle: languageProvider.isArabic
                ? 'تفعيل الاتصال التلقائي'
                : 'Enable automatic connection',
            icon: Icons.bluetooth,
            value: bluetoothEnabled,
            gradient: const LinearGradient(colors: [deepPurple, vibrantPurple]),
            onChanged: (value) {
              _hapticFeedback();
              setState(() {
                bluetoothEnabled = value;
              });
              _saveSettings();
              _speak(value
                  ? (languageProvider.isArabic
                      ? 'تم تفعيل البلوتوث'
                      : 'Bluetooth enabled')
                  : (languageProvider.isArabic
                      ? 'تم تعطيل البلوتوث'
                      : 'Bluetooth disabled'));
            },
          ),
          _buildToggleCard(
            title: languageProvider.isArabic ? 'تنبيهات الجهاز' : 'Device Alerts',
            subtitle: languageProvider.isArabic
                ? 'استقبال الإشعارات'
                : 'Receive notifications',
            icon: Icons.notifications_active,
            value: deviceAlertsEnabled,
            gradient: const LinearGradient(
              colors: [vibrantPurple, primaryPurple],
            ),
            onChanged: (value) {
              _hapticFeedback();
              setState(() {
                deviceAlertsEnabled = value;
              });
              _saveSettings();
              _speak(value
                  ? (languageProvider.isArabic
                      ? 'تم تفعيل التنبيهات'
                      : 'Alerts enabled')
                  : (languageProvider.isArabic
                      ? 'تم تعطيل التنبيهات'
                      : 'Alerts disabled'));
            },
          ),
          const SizedBox(height: 20),
          _buildInfoCard(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required Gradient gradient,
    required ValueChanged<bool> onChanged,
  }) {
    return Semantics(
      label: '$title. $subtitle. Currently ${value ? "enabled" : "disabled"}',
      button: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(22),
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
            Container(
              width: 58,
              height: 58,
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
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w700,
                      color: deepPurple,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: deepPurple.withOpacity(0.7),
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
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.white,
              activeTrackColor: vibrantPurple,
              inactiveThumbColor: Colors.grey.shade400,
              inactiveTrackColor: Colors.grey.shade300,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palePurple.withOpacity(0.3), ultraLightPurple],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: deepPurple.withOpacity(0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: palePurple.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [vibrantPurple, primaryPurple],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                languageProvider.isArabic ? 'معلومات' : 'Information',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: deepPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            languageProvider.isArabic
                ? 'اتصال البلوتوث يسمح للتطبيق بالاتصال تلقائياً بنظارتك الذكية. تنبيهات الجهاز ستخطرك بالتذكيرات المهمة!'
                : 'Bluetooth connection allows the app to automatically connect to your smart glass. Device alerts will notify you of important reminders!',
            style: TextStyle(
              fontSize: 14,
              color: deepPurple.withOpacity(0.8),
              fontWeight: FontWeight.w500,
              height: 1.5,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
                      isActive: false,
                      description: 'Navigate to Homepage',
                      onTap: () {
                        _hapticFeedback();
                        _speak(languageProvider.isArabic
                            ? 'الانتقال للصفحة الرئيسية'
                            : 'Navigate to Homepage');
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
                      label: languageProvider.isArabic ? 'التذكيرات' : 'Reminders',
                      description: 'Manage your reminders and notifications',
                      onTap: () {
                        _speak(
                          languageProvider.isArabic
                              ? 'التذكيرات، أنشئ وأدر التذكيرات، وسيخطرك التطبيق في الوقت المناسب'
                              : 'Reminders, Create and manage reminders, and the app will notify you at the right time',
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
                      description:
                          'Manage your emergency contacts and important people',
                      onTap: () {
                        _speak(languageProvider.isArabic
                            ? 'جهات الاتصال، تخزين وإدارة جهات اتصال الطوارئ'
                            : 'Contact, Store and manage emergency contacts');
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
                      description: 'Adjust app settings and preferences',
                      onTap: () {
                        _speak(
                          languageProvider.isArabic
                              ? 'الإعدادات، إدارة الإعدادات والتفضيلات'
                              : 'Settings, Manage your settings and preferences',
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
              _hapticFeedback();
              _speak(
                languageProvider.isArabic
                    ? 'طوارئ، إرسال تنبيه طوارئ لجهات الاتصال الموثوقة عندما تحتاج المساعدة'
                    : 'Emergency SOS, Sends an emergency alert to your trusted contacts when you need help',
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