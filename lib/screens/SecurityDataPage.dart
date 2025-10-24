import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SecurityDataPage extends StatefulWidget {
  const SecurityDataPage({super.key});

  @override
  State<SecurityDataPage> createState() => _SecurityDataPageState();
}

class _SecurityDataPageState extends State<SecurityDataPage>
    with TickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterTts _tts = FlutterTts();

  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool isChangingPassword = false;
  bool isLoading = false;
  bool _currentPasswordVisible = false;
  bool _newPasswordVisible = false;
  bool _confirmPasswordVisible = false;

  late AnimationController _fadeController;
  late AnimationController _slideController;

  // 🎨 نظام ألوان موحد
  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);

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
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ✅ التحقق من قوة كلمة المرور
  String? _validatePassword(String password) {
    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }

    if (!password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain uppercase letters';
    }

    if (!password.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain lowercase letters';
    }

    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain numbers';
    }

    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Password must contain special characters';
    }

    return null;
  }

  Future<void> _updatePassword() async {
    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showErrorSnackBar('New passwords do not match');
      _speak('New passwords do not match');
      return;
    }

    // التحقق من أن كلمة المرور الجديدة مختلفة عن القديمة
    if (_currentPasswordController.text == _newPasswordController.text) {
      _showErrorSnackBar(
        'New password must be different from current password',
      );
      _speak('New password must be different from current password');
      return;
    }

    // التحقق من قوة كلمة المرور الجديدة
    String? passwordError = _validatePassword(_newPasswordController.text);
    if (passwordError != null) {
      _showErrorSnackBar(passwordError);
      _speak(passwordError);
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final user = _auth.currentUser;
      if (user != null && user.email != null) {
        final credential = EmailAuthProvider.credential(
          email: user.email!,
          password: _currentPasswordController.text,
        );

        await user.reauthenticateWithCredential(credential);
        await user.updatePassword(_newPasswordController.text);

        _showSuccessSnackBar('Password updated successfully');
        _speak('Password updated successfully');

        _clearPasswordForm();
        setState(() {
          isChangingPassword = false;
        });
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Failed to update password';

      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        errorMessage = 'Current password is incorrect';
      } else if (e.code == 'weak-password') {
        errorMessage = 'New password is too weak';
      } else if (e.code == 'requires-recent-login') {
        errorMessage = 'Please log out and log back in, then try again';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'Invalid email format';
      } else if (e.code == 'user-not-found') {
        errorMessage = 'User account not found';
      } else {
        errorMessage = 'Current password is incorrect. Please try again.';
      }

      _showErrorSnackBar(errorMessage);
      _speak(errorMessage);
    } catch (e) {
      print('Error updating password: $e');
      _showErrorSnackBar('An unexpected error occurred');
      _speak('An unexpected error occurred');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _clearPasswordForm() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
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
                Expanded(child: _buildContent()),
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
                    'Security & Data',
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
                    'Manage your account security',
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 35, 16, 16),
        child: Column(
          children: [
            _buildSecurityCard(
              'Update Your Password',
              'Change your account password',
              Icons.lock_outline,
              const LinearGradient(colors: [deepPurple, vibrantPurple]),
              onTap: () {
                _hapticFeedback();
                setState(() {
                  isChangingPassword = !isChangingPassword;
                });
                if (!isChangingPassword) {
                  _clearPasswordForm();
                }
                _speak(
                  isChangingPassword
                      ? 'Password form opened'
                      : 'Password form closed',
                );
              },
            ),
            if (isChangingPassword) ...[
              const SizedBox(height: 30),
              _buildPasswordForm(),
            ],
            const SizedBox(height: 30),
            _buildSecurityTipsCard(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityCard(
    String title,
    String subtitle,
    IconData icon,
    Gradient gradient, {
    VoidCallback? onTap,
  }) {
    return Semantics(
      label: '$title. $subtitle',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
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
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: deepPurple,
                      ),
                      softWrap: false,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: deepPurple.withOpacity(0.7),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                      softWrap: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                isChangingPassword
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: vibrantPurple,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: palePurple.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildPasswordField(
            'Current Password',
            _currentPasswordController,
            _currentPasswordVisible,
            (value) => setState(() => _currentPasswordVisible = value),
          ),
          const SizedBox(height: 20),
          _buildPasswordField(
            'New Password',
            _newPasswordController,
            _newPasswordVisible,
            (value) => setState(() => _newPasswordVisible = value),
          ),
          const SizedBox(height: 20),
          _buildPasswordField(
            'Confirm New Password',
            _confirmPasswordController,
            _confirmPasswordVisible,
            (value) => setState(() => _confirmPasswordVisible = value),
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          _hapticFeedback();
                          setState(() {
                            isChangingPassword = false;
                          });
                          _clearPasswordForm();
                          _speak('Password form cancelled');
                        },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: vibrantPurple.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: vibrantPurple,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [vibrantPurple, primaryPurple],
                    ),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: vibrantPurple.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () {
                            _hapticFeedback();
                            _updatePassword();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Update',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
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

  Widget _buildPasswordField(
    String label,
    TextEditingController controller,
    bool isVisible,
    ValueChanged<bool> onVisibilityChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: deepPurple,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          obscureText: !isVisible,
          style: const TextStyle(
            color: deepPurple,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(
              Icons.lock_outline,
              color: vibrantPurple,
              size: 22,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                isVisible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: deepPurple.withOpacity(0.6),
                size: 22,
              ),
              onPressed: () {
                _hapticFeedback();
                onVisibilityChanged(!isVisible);
              },
            ),
            hintText: 'Enter ${label.toLowerCase()}',
            hintStyle: TextStyle(
              color: deepPurple.withOpacity(0.4),
              fontWeight: FontWeight.w500,
            ),
            filled: true,
            fillColor: ultraLightPurple,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palePurple.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: vibrantPurple, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityTipsCard() {
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
                  Icons.security,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Password Requirements',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: deepPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _buildSecurityTip('At least 8 characters long'),
          _buildSecurityTip('Contains uppercase letters (A-Z)'),
          _buildSecurityTip('Contains lowercase letters (a-z)'),
          _buildSecurityTip('Contains numbers (0-9)'),
          _buildSecurityTip('Contains special characters (!@#\$%^&*)'),
        ],
      ),
    );
  }

  Widget _buildSecurityTip(String tip) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 7),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [vibrantPurple, primaryPurple],
              ),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tip,
              style: TextStyle(
                fontSize: 14,
                color: deepPurple.withOpacity(0.8),
                fontWeight: FontWeight.w500,
                height: 1.5,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
