import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';

import 'home_page.dart';
import 'Reminders.dart';
import 'settings.dart';
import 'contact_info_page.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with TickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterTts _tts = FlutterTts();

  String _userName = 'User';
  bool _isLoadingUserData = true;
  StreamSubscription<DocumentSnapshot>? _userDataSubscription;

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

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeController.forward();
    _slideController.forward();

    _initTts();
    _loadUserData();
  }

  Future<void> _initTts() async {
    final languageCode = Provider.of<LanguageProvider>(context, listen: false).languageCode;
    await _tts.setLanguage(languageCode == 'ar' ? 'ar-SA' : 'en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _tts.stop();
    _userDataSubscription?.cancel();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    try {
      final User? user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _userName = 'Guest';
          _isLoadingUserData = false;
        });
        return;
      }

      _userDataSubscription = _firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen(
            (DocumentSnapshot userDoc) {
              if (!mounted) return;
              if (userDoc.exists) {
                final Map<String, dynamic>? userData =
                    userDoc.data() as Map<String, dynamic>?;
                setState(() {
                  _userName =
                      userData?['full_name'] as String? ??
                      userData?['displayName'] as String? ??
                      userData?['name'] as String? ??
                      user.displayName ??
                      user.email?.split('@')[0] ??
                      'User';
                  _isLoadingUserData = false;
                });
              } else {
                _setUserNameFromAuth(user);
              }
            },
            onError: (error) {
              if (!mounted) return;
              final User? currentUser = _auth.currentUser;
              if (currentUser != null) _setUserNameFromAuth(currentUser);
            },
          );
    } catch (_) {}
  }

  void _setUserNameFromAuth(User user) {
    if (!mounted) return;
    setState(() {
      _userName = user.displayName ?? user.email?.split('@')[0] ?? 'User';
      _isLoadingUserData = false;
    });
  }

  void _onNavTap(BuildContext context, int index) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    _hapticFeedback();
    
    if (index == 0) {
      _speak(languageProvider.isArabic ? 'الرئيسية' : 'Home');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } else if (index == 1) {
      _speak(languageProvider.isArabic ? 'التذكيرات' : 'Reminders');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RemindersPage()),
      );
    } else if (index == 2) {
      _speak(languageProvider.isArabic ? 'الطوارئ' : 'Emergency');
    } else if (index == 3) {
      _speak(languageProvider.isArabic ? 'الإعدادات' : 'Settings');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SettingsPage()),
      );
    }
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
                Expanded(child: _buildContent()),
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
        padding: const EdgeInsets.fromLTRB(30, 50, 20, 40),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withOpacity(0.9),
              Colors.white.withOpacity(0.7),
              const Color.fromARGB(165, 255, 255, 255),
              const Color.fromARGB(82, 240, 224, 245),
            ],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    languageProvider.isArabic ? 'مرحباً!' : 'Hey!',
                    style: TextStyle(
                      fontSize: 21,
                      color: deepPurple.withOpacity(0.7),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _isLoadingUserData
                      ? Container(
                          width: 120,
                          height: 32,
                          decoration: BoxDecoration(
                            color: palePurple.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )
                      : Text(
                          _userName,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            foreground: Paint()
                              ..shader = const LinearGradient(
                                colors: [deepPurple, vibrantPurple],
                              ).createShader(const Rect.fromLTWH(0, 0, 200, 70)),
                          ),
                          overflow: TextOverflow.ellipsis,
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
    
    return Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Text(
                  languageProvider.isArabic
                      ? 'المساعدة على بُعد نقرة واحدة!'
                      : 'Help is just a click away!',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    color: deepPurple.withOpacity(0.9),
                    letterSpacing: 0.5,
                    shadows: [
                      Shadow(
                        color: Colors.white.withOpacity(0.8),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  languageProvider.isArabic
                      ? 'اضغط على زر الطوارئ لطلب المساعدة.'
                      : 'Tap the SOS button to call for help.',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: deepPurple.withOpacity(0.75),
                    height: 1.5,
                    shadows: [
                      Shadow(
                        color: Colors.white.withOpacity(0.6),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 60),
          const Spacer(),
          SosButton(onSuccess: _showSuccessDialog),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildFloatingBottomNav() {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
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
                  label: languageProvider.isArabic ? 'الرئيسية' : 'Home',
                  isActive: true,
                  onTap: () => _onNavTap(context, 0),
                ),
                _buildNavButton(
                  icon: Icons.notifications_rounded,
                  label: languageProvider.isArabic ? 'التذكيرات' : 'Reminders',
                  onTap: () => _onNavTap(context, 1),
                ),
                _buildNavButton(
                  icon: Icons.contact_phone,
                  label: languageProvider.isArabic ? 'الطوارئ' : 'Emergency',
                  onTap: () {
                    _hapticFeedback();
                    _speak(languageProvider.isArabic
                        ? 'جهات اتصال الطوارئ'
                        : 'Emergency Contact');
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
                  onTap: () => _onNavTap(context, 3),
                ),
              ],
            ),
          ),
        ),
      ),
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

  void _showSuccessDialog(BuildContext context) async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    _hapticFeedback();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(languageProvider.isArabic
            ? 'تم إرسال تنبيه الطوارئ لجميع جهات الاتصال'
            : 'Emergency alert sent to all contacts'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        Timer(const Duration(seconds: 4), () {
          if (Navigator.canPop(ctx)) Navigator.of(ctx).pop();
        });

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          child: Container(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade400, Colors.green.shade600],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.white,
                    size: 60,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  languageProvider.isArabic
                      ? 'المساعدة في الطريق!'
                      : 'Help is on the way!',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: deepPurple,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  languageProvider.isArabic
                      ? 'تم إرسال تنبيه الطوارئ لجميع جهات الاتصال'
                      : 'Emergency alert sent to all contacts',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF5E275F)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SosButton extends StatefulWidget {
  final Function(BuildContext) onSuccess;

  const SosButton({super.key, required this.onSuccess});

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  bool _isProcessing = false;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initTts();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.4,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  Future<void> _initTts() async {
    final languageCode = Provider.of<LanguageProvider>(context, listen: false).languageCode;
    await _tts.setLanguage(languageCode == 'ar' ? 'ar-SA' : 'en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  void _hapticFeedback() {
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _tts.stop();
    _controller.dispose();
    super.dispose();
  }

  Widget _buildPulse({required double scale, required double opacity}) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 200,
        height: 180,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.red.withOpacity(opacity),
        ),
      ),
    );
  }

  Future<void> _handleSosPress() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    if (_isProcessing) return;

    _hapticFeedback();
    await Future.delayed(const Duration(milliseconds: 100));
    _hapticFeedback();
    await Future.delayed(const Duration(milliseconds: 100));
    _hapticFeedback();

    setState(() => _isProcessing = true);

    try {
      await _speak(languageProvider.isArabic
          ? 'تم إرسال تنبيه الطوارئ لجميع جهات الاتصال'
          : 'Emergency alert sent to all contacts');
      await Future.delayed(const Duration(milliseconds: 250));
      if (mounted) widget.onSuccess(context);
    } catch (e) {
      if (!mounted) return;
      await _speak(languageProvider.isArabic
          ? 'فشل إرسال تنبيه الطوارئ'
          : 'Failed to send emergency alert');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(languageProvider.isArabic
              ? 'فشلت معالجة الطلب. حاول مرة أخرى.'
              : 'Failed to process request. Please try again.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return Semantics(
      label: languageProvider.isArabic
          ? 'زر طوارئ. اضغط لإرسال تنبيه طوارئ'
          : 'Emergency SOS button. Press to send emergency alert',
      button: true,
      hint: languageProvider.isArabic
          ? 'انقر نقراً مزدوجاً لتفعيل طوارئ'
          : 'Double tap to activate emergency SOS',
      child: Center(
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                if (!_isProcessing) ...[
                  _buildPulse(scale: _pulseAnimation.value * 1.2, opacity: 0.1),
                  _buildPulse(scale: _pulseAnimation.value * 1.0, opacity: 0.15),
                  _buildPulse(scale: _pulseAnimation.value * 0.8, opacity: 0.2),
                ],
                GestureDetector(
                  onTap: _isProcessing ? null : _handleSosPress,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isProcessing ? Colors.grey : Colors.red,
                      boxShadow: [
                        BoxShadow(
                          color: (_isProcessing ? Colors.grey : Colors.red)
                              .withOpacity(0.5),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: _isProcessing
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : const Center(
                            child: Text(
                              'SOS',
                              style: TextStyle(
                                fontSize: 48,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 8,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}