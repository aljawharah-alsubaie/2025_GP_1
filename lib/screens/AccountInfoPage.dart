import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'profile.dart';
import 'package:munir_app/screens/login_screen.dart';
import './sos_screen.dart';
import 'home_page.dart';
import 'reminders.dart';
import 'contact_info_page.dart';
import 'settings.dart';
import 'package:google_sign_in/google_sign_in.dart'; // ✅ مضاف: Google Sign-In

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
    await _tts.setLanguage("en-US");
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
      _showErrorSnackBar('Unexpected error, please try again.');
      _speak('Unexpected error, please try again.');
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
                              Navigator.pop(context, true); // لا تنطق هنا
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
                              Navigator.pop(context, false); // لا تنطق هنا
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

  Future<String?> _showPasswordDialog() async {
    final TextEditingController passwordController = TextEditingController();
    bool isPasswordVisible = false;

    return await showDialog<String>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (context) {
        bool announced = false;
        String? errorText;

        return _fixedDialog(
          StatefulBuilder(
            builder: (context, setState) {
              if (!announced) {
                announced = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _speakNow(
                    'Password confirmation. Please enter your password. Buttons: Confirm on the top, Cancel at the bottom.',
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
                    const Text(
                      'Confirm Your Password',
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
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Please enter your password to continue.',
                      style: TextStyle(
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
                      onChanged: (v) {
                        if (errorText != null && v.trim().isNotEmpty) {
                          setState(() => errorText = null);
                        }
                      },
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
                        hintText: 'Enter your password',
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
                        errorText: errorText,
                        errorStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
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
                            onPressed: () {
                              _hapticFeedback();
                              final text = passwordController.text.trim();
                              if (text.isEmpty) {
                                setState(
                                  () => errorText = 'Password is required',
                                );
                                _speakNow('Password is required');
                                return;
                              }
                              Navigator.pop(context, text);
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
                              Navigator.pop(context, null);
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
              );
            },
          ),
        );
      },
    );
  }

  Future<bool> _verifyPassword(String email, String password) async {
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
      _showErrorSnackBar('Network timeout while verifying password.');
      _speak('Network timeout while verifying password.');
      return false;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return false;
      }
      _showErrorSnackBar('Auth error: ${e.code}');
      _speak('Authentication error.');
      return false;
    } catch (_) {
      _showErrorSnackBar('Unexpected error during verification.');
      _speak('Unexpected error during verification.');
      return false;
    }
  }

  Future<bool> _reauthenticateWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        _showErrorSnackBar('Reauthentication cancelled');
        await _speakNow('Reauthentication cancelled.');
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
      _showErrorSnackBar('Network timeout while reauthenticating with Google.');
      await _speakNow('Network timeout while reauthenticating with Google.');
      return false;
    } on FirebaseAuthException catch (e) {
      _showErrorSnackBar('Auth error: ${e.code}');
      await _speakNow(
        'Authentication error while reauthenticating with Google.',
      );
      return false;
    } catch (_) {
      _showErrorSnackBar('Unexpected error during Google reauthentication.');
      await _speakNow('Unexpected error during Google reauthentication.');
      return false;
    }
  }

  // ✅ معدلة بالكامل: تفرّق بين Google و Email/Password
  Future<void> _deleteAccount() async {
    final confirmed = await _showDangerConfirmDialog(
      icon: Icons.delete_forever,
      title: 'Delete Account',
      body:
          'Are you sure you want to delete your account? This action cannot be undone',
      confirmLabel: 'Confirm',
      cancelLabel: 'Cancel',
      ttsIntro:
          'Delete account. Are you sure you want to delete your account? This action cannot be undone. Buttons: Confirm on the top, Cancel at the bottom.',
    );
    if (confirmed != true) {
      _showErrorSnackBar('Deletion cancelled');
      await _speakNow('Deletion cancelled');
      return;
    }

    await _tts.stop();

    final user = _auth.currentUser;
    if (user == null) {
      _showErrorSnackBar('No user is currently signed in');
      await _speakNow('No user is currently signed in');
      return;
    }

    final providers = user.providerData.map((p) => p.providerId).toList();
    final bool isGoogleOnly =
        providers.length == 1 && providers.contains('google.com');
    final bool hasPasswordProvider = providers.contains('password');
    String? password;
    String? email;
    if (hasPasswordProvider && !isGoogleOnly) {
      password = await _showPasswordDialog();
      if (password == null || password.isEmpty) {
        _showErrorSnackBar('Deletion cancelled');
        await _speakNow('Deletion cancelled');
        return;
      }
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
        _showErrorSnackBar('Email not found. Please log in again.');
        await _speakNow('Email not found. Please log in again.');
        return;
      }
    } else if (!isGoogleOnly) {
      _showErrorSnackBar(
        'This sign-in method is not supported for in-app deletion. Please contact support.',
      );
      await _speakNow(
        'This sign-in method is not supported for in-app deletion. Please contact support.',
      );
      return;
    }

    if (isGoogleOnly) {
      await _speakNow(
        'Reauthenticating with Google. Please choose your Google account to confirm deletion.',
      );
    }

    await _withBlocking(() async {
      if (isGoogleOnly) {
        final ok = await _reauthenticateWithGoogle();
        if (!ok) {
          return;
        }
      } else if (hasPasswordProvider) {
        final ok = await _verifyPassword(email!, password!);
        if (!ok) {
          _showErrorSnackBar('Invalid password. Please try again');
          await _speakNow('Invalid password. Please try again.');
          return;
        }
      }

      try {
        final userDoc = _firestore.collection('users').doc(user.uid);
        final snap = await userDoc.get().timeout(const Duration(seconds: 8));
        if (snap.exists) {
          await userDoc.delete().timeout(const Duration(seconds: 8));
        }
      } on TimeoutException {
        _showErrorSnackBar('Network timeout while deleting your data.');
        await _speakNow('Network timeout while deleting your data.');
        return;
      } catch (_) {
        _showErrorSnackBar('Error while deleting your data.');
        await _speakNow('Error while deleting your data.');
        return;
      }

      try {
        await user.delete().timeout(const Duration(seconds: 10));
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          _showErrorSnackBar('Please log out and log back in, then try again.');
          await _speakNow('Please log out and log back in, then try again.');
          return;
        }
        _showErrorSnackBar('Auth error: ${e.code}');
        await _speakNow('Authentication error.');
        return;
      } on TimeoutException {
        _showErrorSnackBar('Network timeout while deleting account.');
        await _speakNow('Network timeout while deleting account.');
        return;
      } catch (_) {
        _showErrorSnackBar('Unexpected error while deleting account.');
        await _speakNow('Unexpected error while deleting account.');
        return;
      }

      try {
        await _auth.signOut().timeout(const Duration(seconds: 6));
      } catch (_) {}

      _showSuccessSnackBar('Account deleted successfully');
      await Future.delayed(const Duration(seconds: 1));
      await _tts.stop();

      await _speakAwait('Account deleted successfully. Redirecting to login.');
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
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
                  _speak('Going back');
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
                    'Account Info',
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
                    'Manage your account settings',
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
            title: 'Personal Information',
            subtitle: 'Edit your account information',
            icon: Icons.person_outline,
            gradient: const LinearGradient(colors: [deepPurple, vibrantPurple]),
            onTap: () {
              _hapticFeedback();
              _speak('Personal Information');
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfilePage()),
              );
            },
          ),
          _buildInfoCard(
            title: 'Delete My Account',
            subtitle: 'Permanently delete your account',
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
                      description: 'Navigate to Homepage',
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
                      description: 'Manage your reminders and notifications',
                      onTap: () {
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
                      description:
                          'Manage your emergency contacts and important people',
                      onTap: () {
                        _speak('Contact, Store and manage emergency contacts');
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
                        _speak(
                          'Settings, Manage your settings and preferences',
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
                'Emergency SOS, Sends an emergency alert to your trusted contacts when you need help',
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
 