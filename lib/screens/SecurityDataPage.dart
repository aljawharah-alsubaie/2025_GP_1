import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import 'home_page.dart';
import 'reminders.dart';
import 'contact_info_page.dart';
import 'settings.dart';
import './sos_screen.dart';

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

  late VoidCallback _newPwdListener;
  late VoidCallback _confirmPwdListener;

  bool isChangingPassword = false;
  bool isLoading = false;
  bool _currentPasswordVisible = false;
  bool _newPasswordVisible = false;
  bool _confirmPasswordVisible = false;

  bool _showErrorBanner = false;
  String? _currentErrorMessage;

  late AnimationController _fadeController;
  late AnimationController _slideController;

  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);
  static const Color cancelUltraPale = Color(0xFFFBF7FF);

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

    _newPwdListener = () => setState(() {});
    _confirmPwdListener = () => setState(() {});
    _newPasswordController.addListener(_newPwdListener);
    _confirmPasswordController.addListener(_confirmPwdListener);
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
    _currentPasswordController.dispose();
    _newPasswordController.removeListener(_newPwdListener);
    _confirmPasswordController.removeListener(_confirmPwdListener);
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showErrorBannerMessage(String message) {
    setState(() {
      _currentErrorMessage = message;
      _showErrorBanner = true;
    });
    final displaySeconds = message.length > 60 ? 10 : 6;

    Future.delayed(Duration(seconds: displaySeconds), () {
      if (mounted) _hideErrorBanner();
    });
  }

  void _hideErrorBanner() {
    setState(() {
      _showErrorBanner = false;
      _currentErrorMessage = null;
    });
  }

  List<String> _validatePasswordAll(String password) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final List<String> errors = [];

    if (password.length < 8) {
      errors.add(languageProvider.isArabic
          ? 'يجب أن تكون 8 أحرف على الأقل'
          : 'Must be at least 8 characters');
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      errors.add(languageProvider.isArabic
          ? 'يجب أن تحتوي على حرف كبير واحد على الأقل (A-Z)'
          : 'Must contain at least one uppercase letter (A-Z)');
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      errors.add(languageProvider.isArabic
          ? 'يجب أن تحتوي على حرف صغير واحد على الأقل (a-z)'
          : 'Must contain at least one lowercase letter (a-z)');
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      errors.add(languageProvider.isArabic
          ? 'يجب أن تحتوي على رقم واحد على الأقل (0-9)'
          : 'Must contain at least one number (0-9)');
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) {
      errors.add(languageProvider.isArabic
          ? 'يجب أن تحتوي على رمز خاص واحد على الأقل'
          : 'Must contain at least one special character');
    }

    return errors;
  }

  Future<void> _updatePassword() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    final current = _currentPasswordController.text.trim();
    final newer = _newPasswordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();
    
    if (current.isEmpty || newer.isEmpty || confirm.isEmpty) {
      final msg = languageProvider.isArabic
          ? 'من فضلك املأ جميع الحقول المطلوبة'
          : 'Please fill all required fields';
      _showErrorBannerMessage(msg);
      _speak(msg);
      return;
    }

    if (newer != confirm) {
      final msg = languageProvider.isArabic
          ? 'كلمات المرور الجديدة غير متطابقة'
          : 'New passwords do not match';
      _showErrorBannerMessage(msg);
      _speak(msg);
      return;
    }

    if (current == newer) {
      final msg = languageProvider.isArabic
          ? 'يجب أن تكون كلمة المرور الجديدة مختلفة عن الحالية'
          : 'New password must be different from current password';
      _showErrorBannerMessage(msg);
      _speak(msg);
      return;
    }

    final allErrors = _validatePasswordAll(newer);
    if (allErrors.isNotEmpty) {
      final pretty = languageProvider.isArabic
          ? 'من فضلك اصلح التالي:\n• ${allErrors.join('\n• ')}'
          : 'Please fix the following:\n• ${allErrors.join('\n• ')}';
      _showErrorBannerMessage(pretty);
      _speak(
        languageProvider.isArabic
            ? 'كلمة المرور لا تستوفي المتطلبات. ${allErrors.join('. ')}.'
            : 'Password does not meet the requirements. ${allErrors.join('. ')}.',
      );
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
          password: current,
        );

        await user.reauthenticateWithCredential(credential);
        await user.updatePassword(newer);

        _showSuccessSnackBar(languageProvider.isArabic
            ? 'تم تحديث كلمة المرور بنجاح'
            : 'Password updated successfully');
        _speak(languageProvider.isArabic
            ? 'تم تحديث كلمة المرور بنجاح'
            : 'Password updated successfully');

        _clearPasswordForm();
        setState(() {
          isChangingPassword = false;
        });
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = languageProvider.isArabic
          ? 'فشل تحديث كلمة المرور'
          : 'Failed to update password';

      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        errorMessage = languageProvider.isArabic
            ? 'كلمة مرور غير صحيحة. حاول مرة أخرى'
            : 'Invalid password. Please try again';
      } else if (e.code == 'weak-password') {
        errorMessage = languageProvider.isArabic
            ? 'كلمة المرور الجديدة ضعيفة جداً'
            : 'New password is too weak';
      } else if (e.code == 'requires-recent-login') {
        errorMessage = languageProvider.isArabic
            ? 'من فضلك سجل خروج ثم سجل دخول مرة أخرى، ثم حاول'
            : 'Please log out and log back in, then try again';
      } else if (e.code == 'invalid-email') {
        errorMessage = languageProvider.isArabic
            ? 'صيغة البريد الإلكتروني غير صحيحة'
            : 'Invalid email format';
      } else if (e.code == 'user-not-found') {
        errorMessage = languageProvider.isArabic
            ? 'لم يتم العثور على حساب المستخدم'
            : 'User account not found';
      } else {
        errorMessage = languageProvider.isArabic
            ? 'كلمة المرور الحالية غير صحيحة. حاول مرة أخرى'
            : 'Current password is incorrect. Please try again.';
      }

      _showErrorBannerMessage(errorMessage);
      _speak(errorMessage);
    } catch (e) {
      _showErrorBannerMessage(languageProvider.isArabic
          ? 'حدث خطأ غير متوقع'
          : 'An unexpected error occurred');
      _speak(languageProvider.isArabic
          ? 'حدث خطأ غير متوقع'
          : 'An unexpected error occurred');
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
    if (!mounted) return;
    ScaffoldMessenger.of(context)
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
          content: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
          Positioned(left: 0, right: 0, bottom: 0, child: _buildErrorBanner()),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [_buildFloatingBottomNav()],
      ),
    );
  }

  Widget _buildErrorBanner() {
    if (!_showErrorBanner || _currentErrorMessage == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFD32F2F),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(
            child: Icon(Icons.error_outline, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text(
                    _currentErrorMessage!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                    softWrap: true,
                  ),
                ),
              ),
            ),
          ),
          Semantics(
            label: 'Close error message',
            button: true,
            hint: 'Double tap to close error message',
            child: IconButton(
              onPressed: _hideErrorBanner,
              icon: const Icon(Icons.close, color: Colors.white, size: 24),
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
                    languageProvider.isArabic ? 'تغيير كلمة المرور' : 'Change Password',
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
                        ? 'حدّث كلمة مرورك بأمان'
                        : 'Update your password securely',
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
  }Widget _buildContent() {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
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
              languageProvider.isArabic ? 'تحديث كلمة المرور' : 'Update Your Password',
              languageProvider.isArabic
                  ? 'تغيير كلمة مرور حسابك'
                  : 'Change your account password',
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
                      ? (languageProvider.isArabic
                          ? 'تم فتح نموذج كلمة المرور'
                          : 'Password form opened')
                      : (languageProvider.isArabic
                          ? 'تم إغلاق نموذج كلمة المرور'
                          : 'Password form closed'),
                );
              },
            ),
            if (isChangingPassword) ...[
              const SizedBox(height: 30),
              _buildPasswordForm(),
            ],
            const SizedBox(height: 50),
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
          padding: const EdgeInsets.all(24),
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
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.colors.first.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: deepPurple,
                      ),
                      softWrap: true,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: deepPurple.withOpacity(0.7),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                      softWrap: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                isChangingPassword
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: vibrantPurple,
                size: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordForm() {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final newPwd = _newPasswordController.text;
    final confirmPwd = _confirmPasswordController.text;
    final rules = _passwordRulesStatus(newPwd);

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
            languageProvider.isArabic ? 'كلمة المرور الحالية' : 'Current Password',
            _currentPasswordController,
            _currentPasswordVisible,
            (value) => setState(() => _currentPasswordVisible = value),
          ),
          const SizedBox(height: 20),
          _buildPasswordField(
            languageProvider.isArabic ? 'كلمة المرور الجديدة' : 'New Password',
            _newPasswordController,
            _newPasswordVisible,
            (value) => setState(() => _newPasswordVisible = value),
          ),

          const SizedBox(height: 12),
          _buildLiveChecklist(rules),

          const SizedBox(height: 20),
          _buildPasswordField(
            languageProvider.isArabic ? 'تأكيد كلمة المرور الجديدة' : 'Confirm New Password',
            _confirmPasswordController,
            _confirmPasswordVisible,
            (value) => setState(() => _confirmPasswordVisible = value),
          ),
          const SizedBox(height: 8),
          _buildConfirmMatchHint(newPwd, confirmPwd),

          const SizedBox(height: 45),
          Column(
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [vibrantPurple, primaryPurple],
                  ),
                  borderRadius: BorderRadius.circular(18),
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
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 24),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 26,
                          width: 26,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          languageProvider.isArabic
                              ? 'تحديث كلمة المرور'
                              : 'Update Password',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          _hapticFeedback();
                          setState(() {
                            isChangingPassword = false;
                          });
                          _clearPasswordForm();
                          _speak(languageProvider.isArabic
                              ? 'تم إلغاء نموذج كلمة المرور'
                              : 'Password form cancelled');
                        },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: cancelUltraPale,
                    foregroundColor: vibrantPurple,
                    side: BorderSide(
                      color: vibrantPurple.withOpacity(0.5),
                      width: 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    overlayColor: vibrantPurple.withOpacity(0.06),
                  ),
                  child: Text(
                    languageProvider.isArabic ? 'إلغاء' : 'Cancel',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
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
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: deepPurple,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          obscureText: !isVisible,
          style: const TextStyle(
            color: deepPurple,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
          decoration: InputDecoration(
            prefixIcon: const Icon(
              Icons.lock_outline,
              color: vibrantPurple,
              size: 26,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                isVisible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: deepPurple.withOpacity(0.6),
                size: 26,
              ),
              onPressed: () {
                _hapticFeedback();
                onVisibilityChanged(!isVisible);
              },
            ),
            hintText: languageProvider.isArabic
                ? 'ادخل ${label.toLowerCase()}'
                : 'Enter ${label.toLowerCase()}',
            hintStyle: TextStyle(
              color: deepPurple.withOpacity(0.4),
              fontWeight: FontWeight.w500,
              fontSize: 17,
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
              borderSide: const BorderSide(color: vibrantPurple, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 20,
            ),
          ),
        ),
      ],
    );
  }

  Map<String, bool> _passwordRulesStatus(String pwd) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    return {
      languageProvider.isArabic ? '8 أحرف على الأقل' : 'At least 8 characters': pwd.length >= 8,
      languageProvider.isArabic ? 'حرف كبير (A-Z)' : 'Uppercase letter (A-Z)': RegExp(r'[A-Z]').hasMatch(pwd),
      languageProvider.isArabic ? 'حرف صغير (a-z)' : 'Lowercase letter (a-z)': RegExp(r'[a-z]').hasMatch(pwd),
      languageProvider.isArabic ? 'رقم (0-9)' : 'Number (0-9)': RegExp(r'[0-9]').hasMatch(pwd),
      languageProvider.isArabic ? 'رمز خاص' : 'Special character': RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(pwd),
    };
  }

  Widget _buildLiveChecklist(Map<String, bool> rules) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: ultraLightPurple,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palePurple.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rules.entries.map((e) {
          final ok = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  ok ? Icons.check_circle : Icons.cancel,
                  size: 18,
                  color: ok ? const Color(0xFF4CAF50) : const Color(0xFFD32F2F),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e.key,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: ok ? const Color(0xFF2E7D32) : deepPurple,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildConfirmMatchHint(String newPwd, String confirmPwd) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    if (confirmPwd.isEmpty && newPwd.isEmpty) return const SizedBox.shrink();
    final matches = newPwd == confirmPwd && confirmPwd.isNotEmpty;
    
    return Row(
      children: [
        Icon(
          matches ? Icons.check_circle : Icons.error_outline,
          size: 18,
          color: matches ? const Color(0xFF4CAF50) : const Color(0xFFFF9800),
        ),
        const SizedBox(width: 8),
        Text(
          matches
              ? (languageProvider.isArabic ? 'كلمات المرور متطابقة' : 'Passwords match')
              : (languageProvider.isArabic
                  ? 'كلمات المرور غير متطابقة بعد'
                  : 'Passwords do not match yet'),
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: matches ? const Color(0xFF2E7D32) : const Color(0xFFB26A00),
          ),
        ),
      ],
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