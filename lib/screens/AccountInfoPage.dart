import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import 'profile.dart';
import 'package:munir_app/screens/signup_screen.dart';
import './sos_screen.dart';
import 'home_page.dart';
import 'reminders.dart';
import 'contact_info_page.dart';
import 'settings.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AccountInfoPage extends StatefulWidget {
  const AccountInfoPage({super.key});

  @override
  State<AccountInfoPage> createState() => _AccountInfoPageState();
}

class _AccountInfoPageState extends State<AccountInfoPage>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterTts _tts = FlutterTts();
  late AnimationController _fadeController;
  late AnimationController _slideController;

  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);

  OverlayEntry? _blockingOverlay;
  bool _isBlockingVisible = false;

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
    final languageCode = Provider.of<LanguageProvider>(context, listen: false).languageCode;
    await _tts.setLanguage(languageCode == 'ar' ? 'ar-SA' : 'en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(false);

    if (Platform.isAndroid) {
      try {
        await _tts.setQueueMode(1);
      } catch (_) {}
    }
    if (Platform.isIOS) {
      try {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.duckOthers,
          ],
          IosTextToSpeechAudioMode.defaultMode,
        );
      } catch (_) {}
    }
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> _speakNow(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> _speakAwait(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
      await Future.delayed(const Duration(seconds: 4));
    } catch (_) {}
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _hideBlockingOverlay();
    super.dispose();
  }

  Duration _autoDurationFor(String message, {int base = 3}) {
    if (message.length > 120) return Duration(seconds: base + 3);
    if (message.length > 80) return Duration(seconds: base + 2);
    if (message.length > 50) return Duration(seconds: base + 1);
    return Duration(seconds: base);
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
          duration: _autoDurationFor(message, base: 2),
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

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFE53935),
          elevation: 14,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          duration: _autoDurationFor(message, base: 3),
          content: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.error_outline,
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
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  void _showBlockingOverlay() {
    if (_isBlockingVisible) return;
    _isBlockingVisible = true;

    _blockingOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              ignoring: false,
              child: Container(color: Colors.black.withOpacity(0.55)),
            ),
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const SizedBox(
                width: 46,
                height: 46,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD32F2F)),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_blockingOverlay!);
  }

  void _hideBlockingOverlay() {
    if (!_isBlockingVisible) return;
    _isBlockingVisible = false;
    try {
      _blockingOverlay?.remove();
    } catch (_) {}
    _blockingOverlay = null;
  }

  Future<T?> _withBlocking<T>(Future<T> Function() action) async {
    _showBlockingOverlay();
    try {
      return await action();
    } catch (e) {
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      final errorMsg = languageProvider.isArabic
          ? 'خطأ غير متوقع، حاول مرة أخرى'
          : 'Unexpected error, please try again';
      _showErrorSnackBar(errorMsg);
      _speak(errorMsg);
      return null;
    } finally {
      _hideBlockingOverlay();
    }
  }

  Widget _fixedDialog(Widget child) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(viewInsets: EdgeInsets.zero),
      child: Align(
        alignment: const Alignment(0, -0.12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: child,
        ),
      ),
    );
  }

  Future<bool?> _showDangerConfirmDialog({
    required IconData icon,
    required String title,
    required String body,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    String? ttsIntro,
  }) async {
    return showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (context) {
        bool announced = false;

        return _fixedDialog(
          StatefulBuilder(
            builder: (context, setState) {
              if (!announced && ttsIntro != null) {
                announced = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _speak(ttsIntro);
                });
              }

              return AlertDialog(
                backgroundColor: const Color(0xFFD32F2F),
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
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
                      child: Icon(icon, color: Colors.white, size: 52),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                content: Text(
                  body,
                  style: const TextStyle(
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
                      SizedBox(
                        width: double.infinity,
                        height: 75,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: TextButton(
                            onPressed: () {
                              _hapticFeedback();
                              Navigator.pop(context, true);
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Text(
                              confirmLabel,
                              style: const TextStyle(
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
                              Navigator.pop(context, false);
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Text(
                              cancelLabel,
                              style: const TextStyle(
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
              );
            },
          ),
        );
      },
    );
  }

  Future<bool> _showPasswordDialog(String email) async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final TextEditingController passwordController = TextEditingController();
    bool isPasswordVisible = false;

    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (context) {
        bool announced = false;
        bool isLoading = false;

        return _fixedDialog(
          StatefulBuilder(
            builder: (context, setState) {
              if (!announced) {
                announced = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _speakNow(
                    languageProvider.isArabic
                        ? 'تأكيد كلمة المرور. من فضلك ادخل كلمة المرور. الأزرار: تأكيد في الأعلى، إلغاء في الأسفل'
                        : 'Password confirmation. Please enter your password. Buttons: Confirm on the top, Cancel at the bottom.',
                  );
                });
              }

              return AlertDialog(
                backgroundColor: const Color(0xFFD32F2F),
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
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
                      child: const Icon(
                        Icons.lock,
                        color: Colors.white,
                        size: 52,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      languageProvider.isArabic
                          ? 'أكد كلمة المرور'
                          : 'Confirm Your Password',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      languageProvider.isArabic
                          ? 'من فضلك ادخل كلمة المرور للمتابعة.'
                          : 'Please enter your password to continue.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 25),
                    TextField(
                      controller: passwordController,
                      obscureText: !isPasswordVisible,
                      style: const TextStyle(
                        color: Color(0xFFD32F2F),
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                          color: Color(0xFFD32F2F),
                          size: 30,
                        ),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => isPasswordVisible = !isPasswordVisible,
                          ),
                          icon: Icon(
                            isPasswordVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: const Color(0xFFD32F2F).withOpacity(0.7),
                            size: 30,
                          ),
                        ),
                        hintText: languageProvider.isArabic
                            ? 'ادخل كلمة المرور'
                            : 'Enter your password',
                        hintStyle: TextStyle(
                          color: const Color(0xFFD32F2F).withOpacity(0.4),
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 22,
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 75,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: TextButton(
                            onPressed: isLoading
                                ? null
                                : () async {
                                    _hapticFeedback();
                                    final text = passwordController.text.trim();

                                    if (text.isEmpty) {
                                      final msg = languageProvider.isArabic
                                          ? 'كلمة المرور مطلوبة'
                                          : 'Password is required';
                                      _showFrontError(msg);
                                      _speakNow(msg);
                                      return;
                                    }

                                    setState(() => isLoading = true);
                                    final ok = await _verifyPassword(email, text);
                                    setState(() => isLoading = false);

                                    if (!ok) {
                                      final msg = languageProvider.isArabic
                                          ? 'كلمة مرور غير صحيحة. حاول مرة أخرى'
                                          : 'Invalid password. Please try again';
                                      _showFrontError(msg);
                                      _speakNow(msg);
                                      return;
                                    }

                                    Navigator.pop(context, true);
                                  },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Text(
                              isLoading
                                  ? (languageProvider.isArabic ? 'انتظر...' : 'Please wait...')
                                  : (languageProvider.isArabic ? 'تأكيد' : 'Confirm'),
                              style: const TextStyle(
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
                              Navigator.pop(context, false);
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Text(
                              languageProvider.isArabic ? 'إلغاء' : 'Cancel',
                              style: const TextStyle(
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
              );
            },
          ),
        );
      },
    );

    return result ?? false;
  }Future<bool> _verifyPassword(String email, String password) async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    try {
      final cred = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await _auth.currentUser!
          .reauthenticateWithCredential(cred)
          .timeout(const Duration(seconds: 12));
      return true;
    } on TimeoutException {
      final msg = languageProvider.isArabic
          ? 'انتهت مهلة الشبكة أثناء التحقق من كلمة المرور'
          : 'Network timeout while verifying password.';
      _showErrorSnackBar(msg);
      _speak(msg);
      return false;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return false;
      }
      final msg = languageProvider.isArabic
          ? 'خطأ في المصادقة: ${e.code}'
          : 'Auth error: ${e.code}';
      _showErrorSnackBar(msg);
      _speak(languageProvider.isArabic ? 'خطأ في المصادقة' : 'Authentication error.');
      return false;
    } catch (_) {
      final msg = languageProvider.isArabic
          ? 'خطأ غير متوقع أثناء التحقق'
          : 'Unexpected error during verification.';
      _showErrorSnackBar(msg);
      _speak(msg);
      return false;
    }
  }

  Future<bool> _reauthenticateWithGoogle() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    try {
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        final msg = languageProvider.isArabic
            ? 'تم إلغاء إعادة المصادقة'
            : 'Reauthentication cancelled';
        _showErrorSnackBar(msg);
        await _speakNow(msg);
        return false;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.currentUser!
          .reauthenticateWithCredential(credential)
          .timeout(const Duration(seconds: 12));
      return true;
    } on TimeoutException {
      final msg = languageProvider.isArabic
          ? 'انتهت مهلة الشبكة أثناء إعادة المصادقة بـ Google'
          : 'Network timeout while reauthenticating with Google.';
      _showErrorSnackBar(msg);
      await _speakNow(msg);
      return false;
    } on FirebaseAuthException catch (e) {
      final msg = languageProvider.isArabic
          ? 'خطأ في المصادقة: ${e.code}'
          : 'Auth error: ${e.code}';
      _showErrorSnackBar(msg);
      await _speakNow(
        languageProvider.isArabic
            ? 'خطأ في المصادقة أثناء إعادة المصادقة بـ Google'
            : 'Authentication error while reauthenticating with Google.',
      );
      return false;
    } catch (_) {
      final msg = languageProvider.isArabic
          ? 'خطأ غير متوقع أثناء إعادة المصادقة بـ Google'
          : 'Unexpected error during Google reauthentication.';
      _showErrorSnackBar(msg);
      await _speakNow(msg);
      return false;
    }
  }

  void _showFrontError(String message) {
    final overlay = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 40,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(overlay);

    Future.delayed(const Duration(seconds: 3)).then((_) {
      overlay.remove();
    });
  }

  Future<void> _deleteAccount() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    final confirmed = await _showDangerConfirmDialog(
      icon: Icons.delete_forever,
      title: languageProvider.isArabic ? 'حذف الحساب' : 'Delete Account',
      body: languageProvider.isArabic
          ? 'هل أنت متأكد من حذف حسابك؟ هذا الإجراء لا يمكن التراجع عنه'
          : 'Are you sure you want to delete your account? This action cannot be undone',
      confirmLabel: languageProvider.isArabic ? 'تأكيد' : 'Confirm',
      cancelLabel: languageProvider.isArabic ? 'إلغاء' : 'Cancel',
      ttsIntro: languageProvider.isArabic
          ? 'حذف الحساب. هل أنت متأكد من حذف حسابك؟ هذا الإجراء لا يمكن التراجع عنه. الأزرار: تأكيد في الأعلى، إلغاء في الأسفل'
          : 'Delete account. Are you sure you want to delete your account? This action cannot be undone. Buttons: Confirm on the top, Cancel at the bottom.',
    );
    
    if (confirmed != true) {
      final msg = languageProvider.isArabic ? 'تم إلغاء الحذف' : 'Deletion cancelled';
      _showErrorSnackBar(msg);
      await _speakNow(msg);
      return;
    }

    await _tts.stop();

    final user = _auth.currentUser;
    if (user == null) {
      final msg = languageProvider.isArabic
          ? 'لا يوجد مستخدم مسجل حالياً'
          : 'No user is currently signed in';
      _showErrorSnackBar(msg);
      await _speakNow(msg);
      return;
    }

    final providers = user.providerData.map((p) => p.providerId).toList();
    final bool isGoogleOnly =
        providers.length == 1 && providers.contains('google.com');
    final bool hasPasswordProvider = providers.contains('password');
    String? email;
    
    if (hasPasswordProvider && !isGoogleOnly) {
      email = user.email;
      if (email == null || email.isEmpty) {
        for (final info in user.providerData) {
          if ((info.email ?? '').isNotEmpty) {
            email = info.email!;
            break;
          }
        }
      }
      if (email == null || email.isEmpty) {
        final msg = languageProvider.isArabic
            ? 'البريد غير موجود. من فضلك سجّل الدخول مرة أخرى'
            : 'Email not found. Please log in again.';
        _showErrorSnackBar(msg);
        await _speakNow(msg);
        return;
      }

      final ok = await _showPasswordDialog(email);
      if (!ok) {
        final msg = languageProvider.isArabic ? 'تم إلغاء الحذف' : 'Deletion cancelled';
        _showErrorSnackBar(msg);
        await _speakNow(msg);
        return;
      }
    } else if (!isGoogleOnly) {
      final msg = languageProvider.isArabic
          ? 'طريقة تسجيل الدخول هذه غير مدعومة للحذف داخل التطبيق. من فضلك تواصل مع الدعم'
          : 'This sign-in method is not supported for in-app deletion. Please contact support.';
      _showErrorSnackBar(msg);
      await _speakNow(msg);
      return;
    }

    if (isGoogleOnly) {
      await _speakNow(
        languageProvider.isArabic
            ? 'إعادة المصادقة بـ Google. من فضلك اختر حساب Google لتأكيد الحذف'
            : 'Reauthenticating with Google. Please choose your Google account to confirm deletion.',
      );
    }

    String userEmail = user.email ?? '';
    String displayName = 'User';

    await _withBlocking(() async {
      if (isGoogleOnly) {
        final ok = await _reauthenticateWithGoogle();
        if (!ok) {
          return;
        }
      }

      try {
        final userDoc = _firestore.collection('users').doc(user.uid);
        final snap = await userDoc.get().timeout(const Duration(seconds: 8));
        if (snap.exists) {
          final data = snap.data();
          if (data != null) {
            if ((data['full_name'] ?? '').toString().isNotEmpty) {
              displayName = data['full_name'];
            }
            if ((data['email'] ?? '').toString().isNotEmpty) {
              userEmail = data['email'];
            }
          }
          await userDoc.delete().timeout(const Duration(seconds: 8));
        }
      } on TimeoutException {
        final msg = languageProvider.isArabic
            ? 'انتهت مهلة الشبكة أثناء حذف بياناتك'
            : 'Network timeout while deleting your data.';
        _showErrorSnackBar(msg);
        await _speakNow(msg);
        return;
      } catch (_) {
        final msg = languageProvider.isArabic
            ? 'خطأ أثناء حذف بياناتك'
            : 'Error while deleting your data.';
        _showErrorSnackBar(msg);
        await _speakNow(msg);
        return;
      }

      try {
        await user.delete().timeout(const Duration(seconds: 10));
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          final msg = languageProvider.isArabic
              ? 'من فضلك سجّل الخروج ثم سجّل الدخول مرة أخرى، ثم حاول مرة أخرى'
              : 'Please log out and log back in, then try again.';
          _showErrorSnackBar(msg);
          await _speakNow(msg);
          return;
        }
        final msg = languageProvider.isArabic
            ? 'خطأ في المصادقة: ${e.code}'
            : 'Auth error: ${e.code}';
        _showErrorSnackBar(msg);
        await _speakNow(languageProvider.isArabic ? 'خطأ في المصادقة' : 'Authentication error.');
        return;
      } on TimeoutException {
        final msg = languageProvider.isArabic
            ? 'انتهت مهلة الشبكة أثناء حذف الحساب'
            : 'Network timeout while deleting account.';
        _showErrorSnackBar(msg);
        await _speakNow(msg);
        return;
      } catch (_) {
        final msg = languageProvider.isArabic
            ? 'خطأ غير متوقع أثناء حذف الحساب'
            : 'Unexpected error while deleting account.';
        _showErrorSnackBar(msg);
        await _speakNow(msg);
        return;
      }

      try {
        if (userEmail.isNotEmpty) {
          final callable = FirebaseFunctions.instance.httpsCallable(
            'sendAccountDeletionEmail',
          );
          await callable.call({'email': userEmail, 'displayName': displayName});
        }
      } catch (e) {
        print('Error sending account deletion email: $e');
      }

      final successMsg = languageProvider.isArabic
          ? 'تم حذف الحساب بنجاح'
          : 'Account deleted successfully';
      _showSuccessSnackBar(successMsg);
      
      await Future.delayed(const Duration(seconds: 1));
      await _tts.stop();

      await _speakAwait(
        languageProvider.isArabic
            ? 'تم حذف الحساب بنجاح. جاري التوجيه لإنشاء حساب'
            : 'Account deleted successfully. Redirecting to sign up'
      );
      
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SignupScreen()),
          (route) => false,
        );
      }
    });
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
                Expanded(child: _buildContentList()),
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
        padding: const EdgeInsets.fromLTRB(25, 50, 25, 60),
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
                    languageProvider.isArabic ? 'معلومات الحساب' : 'Account Info',
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
                        ? 'إدارة إعدادات حسابك'
                        : 'Manage your account settings',
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

  Widget _buildContentList() {
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
          _buildInfoCard(
            title: languageProvider.isArabic ? 'المعلومات الشخصية' : 'Personal Information',
            subtitle: languageProvider.isArabic
                ? 'تعديل معلومات حسابك'
                : 'Edit your account information',
            icon: Icons.person_outline,
            gradient: const LinearGradient(colors: [deepPurple, vibrantPurple]),
            onTap: () {
              _hapticFeedback();
              _speak(languageProvider.isArabic ? 'المعلومات الشخصية' : 'Personal Information');
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfilePage()),
              );
            },
          ),
          _buildInfoCard(
            title: languageProvider.isArabic ? 'حذف حسابي' : 'Delete My Account',
            subtitle: languageProvider.isArabic
                ? 'حذف حسابك نهائياً'
                : 'Permanently delete your account',
            icon: Icons.delete_forever_outlined,
            gradient: const LinearGradient(
              colors: [Color(0xFFE53935), Color(0xFFD32F2F)],
            ),
            isDanger: true,
            onTap: () {
              _hapticFeedback();
              _deleteAccount();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
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
        margin: const EdgeInsets.only(bottom: 40),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(22),
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
                      description: languageProvider.isArabic
                          ? 'الانتقال للصفحة الرئيسية'
                          : 'Navigate to Homepage',
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
                      description: languageProvider.isArabic
                          ? 'إدارة التذكيرات والإشعارات'
                          : 'Manage your reminders and notifications',
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
                      description: languageProvider.isArabic
                          ? 'إدارة جهات الاتصال الطارئة'
                          : 'Manage your emergency contacts and important people',
                      onTap: () {
                        _speak(languageProvider.isArabic
                            ? 'جهات الاتصال، احفظ وأدر جهات الاتصال الطارئة'
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
                      description: languageProvider.isArabic
                          ? 'ضبط إعدادات التطبيق'
                          : 'Adjust app settings and preferences',
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
                    ? 'طوارئ، يرسل تنبيه طوارئ لجهات الاتصال الموثوقة عندما تحتاج مساعدة'
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