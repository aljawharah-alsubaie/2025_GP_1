import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';

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

  // 🎨 نظام ألوان موحد (نفس الألوان من SettingsPage)
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

  @override
  void dispose() {
    _tts.stop();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
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
      _showErrorSnackBar('Failed to load settings');
    }
  }

  Future<void> _saveSettings() async {
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

        _showSuccessSnackBar('Settings saved successfully');
      }
    } catch (e) {
      print('Error saving settings: $e');
      _showErrorSnackBar('Failed to save settings');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF4CAF50),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFF44336),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              label: 'Back to settings',
              button: true,
              child: GestureDetector(
                onTap: () {
                  _hapticFeedback();
                  _speak('Going back');
                  Navigator.pop(context);
                },
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [vibrantPurple, primaryPurple],
                    ),
                    borderRadius: BorderRadius.all(Radius.circular(18)),
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromARGB(76, 142, 58, 149),
                        blurRadius: 12,
                        offset: Offset(0, 4),
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
                    'Device & Alerts',
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
                    'Manage notifications & devices',
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
            title: 'Bluetooth Device',
            subtitle: 'Enable automatic connection',
            icon: Icons.bluetooth,
            value: bluetoothEnabled,
            gradient: const LinearGradient(colors: [deepPurple, vibrantPurple]),
            onChanged: (value) {
              _hapticFeedback();
              setState(() {
                bluetoothEnabled = value;
              });
              _saveSettings();
              _speak(value ? 'Bluetooth enabled' : 'Bluetooth disabled');
            },
          ),
          _buildToggleCard(
            title: 'Device Alerts',
            subtitle: 'Receive notifications',
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
              _speak(value ? 'Alerts enabled' : 'Alerts disabled');
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
        padding: const EdgeInsets.all(18),
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
                'Information',
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
            'Bluetooth connection allows the app to automatically connect to your smart glass. Device alerts will notify you of important reminders!',
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
}
