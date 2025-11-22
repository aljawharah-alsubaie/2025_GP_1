import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleSignInHandler {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// 🟣 تستخدم في صفحة Sign up
  /// تسمح بإنشاء حساب جديد + إنشاء doc في Firestore
  static Future<UserCredential?> signInWithGoogleForSignup(
    BuildContext context,
  ) async {
    // ✨ مهم: نحاول نضمن ما فيه جلسة سابقة عشان يطلع الـ account picker
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
    } catch (_) {}

    // يفتح شاشة اختيار حساب
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      // المستخدم رجع بدون اختيار
      return null;
    }

    final googleAuth = await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // يسوّي signIn (لو أول مره بيعتبره newUser)
    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user == null) return null;

    final userDocRef = _firestore.collection('users').doc(user.uid);
    final snap = await userDocRef.get();

    // ننشئ بيانات المستخدم لو أول مرة
    if (!snap.exists) {
      await userDocRef.set({
        'full_name': user.displayName ?? 'User',
        'email': user.email ?? '',
        'phone': '',
        'signInProvider': 'google',
        'email_verified': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    return userCredential;
  }

  /// 🔵 تستخدم في صفحة Login
  /// 🔥 تسمح بدخول Google حتى لو أول مرة — وتسوّي له تسجيل جديد تلقائيًا
  static Future<UserCredential?> signInWithGoogleForLogin(
    BuildContext context,
  ) async {
    try {
      // نضمن خروج الجلسة القديمة
      try {
        if (await _googleSignIn.isSignedIn()) {
          await _googleSignIn.signOut();
        }
      } catch (_) {}

      // يفتح اختيار الحساب
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // ألغي

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // يسوي تسجيل دخول Firebase
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      final userDocRef = _firestore.collection('users').doc(user.uid);
      final snap = await userDocRef.get();

      // ✨✨ إذا ما له doc → أول مرة يدخل → نعتبرها Sign up تلقائيًا
      if (!snap.exists) {
        await userDocRef.set({
          'full_name': user.displayName ?? 'User',
          'email': user.email ?? '',
          'phone': '',
          'signInProvider': 'google',
          'email_verified': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // رجعي الـ UserCredential
      return userCredential;
    } catch (e) {
      debugPrint("🔥 Google login error: $e");
      rethrow;
    }
  }
}
