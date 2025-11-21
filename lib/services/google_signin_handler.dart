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
  /// ما تسمح بدخول أي حساب Google جديد ما له record في Firestore
  static Future<UserCredential?> signInWithGoogleForLogin(
    BuildContext context,
  ) async {
    // ✨ نفس الفكرة: نمسح الجلسة القديمة عشان يطلع الـ account picker قد ما نقدر
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
    } catch (_) {}

    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      // ألغى
      return null;
    }

    final googleAuth = await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user == null) return null;

    // 🔍 نتحقق هل هذا المستخدم مسجّل سابقًا في Firestore؟
    final userDocRef = _firestore.collection('users').doc(user.uid);
    final snap = await userDocRef.get();

    final bool hasFirestoreRecord = snap.exists;
    final bool isNewUser =
        userCredential.additionalUserInfo?.isNewUser ?? false;

    // لو ما له doc أو اعتبره Firebase newUser → نمنع الدخول
    if (!hasFirestoreRecord || isNewUser) {
      try {
        await user.delete(); // نحذفه من Auth عشان ما يبقى حساب غير معروف
      } catch (_) {}

      try {
        await _auth.signOut();
      } catch (_) {}

      // نرمي خطأ مخصص نلتقطه في login_screen
      throw FirebaseAuthException(
        code: 'app-google-not-registered',
        message:
            'No existing Google account found in the app. Please sign up with Google first.',
      );
    }

    // ✅ هنا نعرف أنه مسجل من قبل (Sign up with Google)
    return userCredential;
  }
}
