import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'language_selection_screen.dart';
import 'onboarding_screen.dart';
import 'welcome_screen.dart';
import 'home_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    // عرض الـ splash لمدة 3 ثواني
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    const storage = FlutterSecureStorage();
    
    // 🆕 أول شي نتحقق: هل اختار اللغة؟
    final languageSelected = await storage.read(key: 'language_selected');
    
    // لو ما اختار لغة → روح لصفحة اختيار اللغة
    if (languageSelected == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const LanguageSelectionScreen(),
        ),
      );
      return;
    }

    // لو اختار لغة، نكمل الفلو العادي
    final hasOpenedBefore = await storage.read(key: 'hasOpenedBefore');

    if (hasOpenedBefore == null) {
      // أول مرة بعد اختيار اللغة → روح للـ Onboarding
      await storage.write(key: 'hasOpenedBefore', value: 'true');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const OnboardingScreen()),
      );
    } else {
      // المستخدم فتح التطبيق من قبل → روح للـ AuthWrapper
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthWrapper()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset('assets/images/logo.png', width: 360),
      ),
    );
  }
}

// AuthWrapper للتحقق من حالة تسجيل الدخول
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  Future<bool> _checkStoredLogin() async {
    const storage = FlutterSecureStorage();
    final isLoggedIn = await storage.read(key: 'isLoggedIn');
    return isLoggedIn == 'true';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkStoredLogin(),
      builder: (context, storageSnapshot) {
        if (storageSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF6B1D73)),
            ),
          );
        }

        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(color: Color(0xFF6B1D73)),
                ),
              );
            }

            // إذا مسجل دخول، روح للـ HomePage
            if ((storageSnapshot.data == true) ||
                (snapshot.hasData && snapshot.data != null)) {
              return const HomePage();
            }

            // إذا مو مسجل، روح للـ WelcomeScreen
            return const WelcomeScreen();
          },
        );
      },
    );
  }
}