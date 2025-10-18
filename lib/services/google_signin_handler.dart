import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';
import '../screens/home_page.dart';

class GoogleSignInHandler {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  static Future<void> signInWithGoogle(BuildContext context) async {
    try {
      // Sign out first to ensure clean sign-in
      await _googleSignIn.signOut();

      // ✅ الطريقة الجديدة - signIn() أصبحت تُرجع Future<GoogleSignInAccount?>
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        print("User cancelled Google Sign-In");
        return;
      }

      print("Google user signed in: ${googleUser.email}");

      // ✅ الحصول على Authentication بالطريقة الصحيحة
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // ✅ استخدام الـ tokens مباشرة كـ String?
      final String? accessToken = googleAuth.accessToken;
      final String? idToken = googleAuth.idToken;

      print("🔑 Access Token: ${accessToken != null ? 'Available' : 'NULL'}");
      print("🔑 ID Token: ${idToken != null ? 'Available' : 'NULL'}");

      if (accessToken == null && idToken == null) {
        throw Exception('Failed to get authentication tokens');
      }

      // Create Firebase credential
      final credential = GoogleAuthProvider.credential(
        accessToken: accessToken,
        idToken: idToken,
      );

      print("Created Firebase credential");

      // Sign in to Firebase
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        print("Firebase user signed in: ${user.uid}");

        // Check if user document exists
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        String fullName = user.displayName ?? "User";

        if (!userDoc.exists) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
                'full_name': fullName,
                'email': user.email,
                'photo_url': user.photoURL,
                'provider': 'google',
                'created_at': Timestamp.now(),
                'last_login': Timestamp.now(),
                'email_verified': true,
                'profile_completed': false,
              });
          print("Created new user document");
        } else {
          fullName = userDoc.data()?['full_name'] ?? fullName;
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'last_login': Timestamp.now()});
          print("Updated existing user document");
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text("Welcome, $fullName!")),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 3),
            ),
          );

          await Future.delayed(const Duration(milliseconds: 500));
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  HomePage(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
              transitionDuration: const Duration(milliseconds: 500),
            ),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      print("❌ Firebase Auth Error: ${e.code} - ${e.message}");
      String errorMessage = "Authentication failed";

      switch (e.code) {
        case 'account-exists-with-different-credential':
          errorMessage =
              "An account already exists with a different sign-in method";
          break;
        case 'invalid-credential':
          errorMessage = "Invalid credentials provided";
          break;
        case 'operation-not-allowed':
          errorMessage = "Google sign-in is not enabled";
          break;
        case 'user-disabled':
          errorMessage = "This account has been disabled";
          break;
        default:
          errorMessage = e.message ?? "Authentication failed";
      }

      if (context.mounted) {
        _showErrorSnackBar(context, errorMessage);
      }
    } catch (e) {
      print("❌ Error signing in with Google: $e");

      String errorMessage = "Google sign-in failed";
      if (e.toString().contains('PlatformException')) {
        errorMessage = "Configuration error. Please check app setup.";
      } else if (e.toString().contains('network')) {
        errorMessage = "Network error. Please check your connection.";
      }

      if (context.mounted) {
        _showErrorSnackBar(context, errorMessage);
      }
    }
  }

  static void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  static Future<void> signOut() async {
    try {
      await Future.wait([
        FirebaseAuth.instance.signOut(),
        _googleSignIn.signOut(),
      ]);
      print("✅ User signed out successfully");
    } catch (e) {
      print("❌ Error signing out: $e");
    }
  }

  // ✅ استخدام Firebase Auth للتحقق من حالة المستخدم
  static bool isUserSignedIn() {
    return FirebaseAuth.instance.currentUser != null;
  }
}

// ✅ دالة تسجيل الدخول بالإيميل والباسورد
Future<void> checkEmailProviderAndLogin(
  String email,
  String password,
  BuildContext context,
) async {
  try {
    // ✅ محاولة تسجيل الدخول مباشرة
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text("Welcome back!"),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }

    // TODO: Navigate to home page
  } on FirebaseAuthException catch (e) {
    String error = "Login failed";

    switch (e.code) {
      case 'user-not-found':
        error = "No user found with this email.";
        break;
      case 'wrong-password':
        error = "Incorrect password.";
        break;
      case 'invalid-email':
        error = "Invalid email address.";
        break;
      case 'user-disabled':
        error = "This account has been disabled.";
        break;
      case 'invalid-credential':
        // هذا يعني الحساب مسجل عبر Google
        error =
            "This email is registered with Google. Please use the Google Sign-In button.";
        break;
      default:
        error = e.message ?? "Login failed";
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(error)),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text("An unexpected error occurred")),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }
}
