import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider with ChangeNotifier {
  String _languageCode = 'en';

  String get languageCode => _languageCode;
  bool get isArabic => _languageCode == 'ar';

  LanguageProvider() {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    _languageCode = prefs.getString('language_code') ?? 'en';
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    if (_languageCode == code) return;
    
    _languageCode = code;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', code);
    
    notifyListeners();
  }

 String translate(String key) {
  final translations = {
    'en': {
      // موجودة أصلاً
      'welcomeToMunir': 'Welcome to Munir',
      'smartAssistance': 'Smart Assistance for You',
      'aiCompanion': 'Your AI-powered companion for easier daily life.',
      'readTextRecognize': 'Read text, recognize faces, and get real-time feedback.',
      'tapToContinue': 'Tap anywhere to continue',
      
      // 🆕 WelcomeScreen
      'welcomeToJourney': 'Welcome to your new journey',
      'createAccount': 'Create Account',
      'login': 'Login',
      
      // 🆕 LoginScreen
      'welcomeBack': 'Welcome Back',
      'loginToContinue': 'Log in to continue your journey',
      'emailAddress': 'Email Address',
      'password': 'Password',
      'rememberMe': 'Remember me',
      'forgotPassword': 'Forgot Password?',
      'or': 'OR',
      'continueWithGoogle': 'Continue with Google',
      'dontHaveAccount': "Don't have an account? ",
      'signUp': 'Sign Up',
      'logIn': 'Log In',
      
      // 🆕 SignupScreen
      'joinUs': 'Join us and start your journey',
      'name': 'Name',
      'mobileNumber': 'Mobile Number (05XXXXXXXX)',
      'confirmPassword': 'Confirm Password',
      'passwordRequirements': 'Password Requirements:',
      'atLeast8Chars': 'At least 8 characters',
      'oneUppercase': 'Uppercase letter (A-Z)',
      'oneLowercase': 'Lowercase letter (a-z)',
      'oneNumber': 'Number (0-9)',
      'oneSpecialChar': 'Special character',
      'passwordStrength': 'Password Strength',
      'alreadyHaveAccount': 'Already have an account? ',
      
      // Email Verification
      'checkYourEmail': 'Check Your Email',
      'emailVerified': 'Email Verified!',
      'redirectingToHome': 'Redirecting to home...',
      'weSentEmail': 'We sent an email to',
      'important': 'IMPORTANT!',
      'checkSpam': 'Check your SPAM/JUNK folder!',
      'nextSteps': 'Next Steps',
      'resendEmail': 'Resend Verification Email',
      'resendIn': 'Resend in',
      'seconds': 'seconds',
      'backToLogin': 'Back to Login',
    },
    'ar': {
      // موجودة أصلاً
      'welcomeToMunir': 'مرحبًا بك في منير',
      'smartAssistance': 'مساعدة ذكية من أجلك',
      'aiCompanion': 'رفيقك الذكي لحياة يومية أسهل.',
      'readTextRecognize': 'قراءة النصوص، التعرف على الوجوه، والحصول على ملاحظات فورية.',
      'tapToContinue': 'اضغط في أي مكان للمتابعة',
      
      // 🆕 WelcomeScreen
      'welcomeToJourney': 'مرحبًا بك في رحلتك الجديدة',
      'createAccount': 'إنشاء حساب',
      'login': 'تسجيل الدخول',
      
      // 🆕 LoginScreen
      'welcomeBack': 'مرحبًا بعودتك',
      'loginToContinue': 'سجّل الدخول لمتابعة رحلتك',
      'emailAddress': 'البريد الإلكتروني',
      'password': 'كلمة المرور',
      'rememberMe': 'تذكرني',
      'forgotPassword': 'نسيت كلمة المرور؟',
      'or': 'أو',
      'continueWithGoogle': 'المتابعة باستخدام Google',
      'dontHaveAccount': 'ليس لديك حساب؟ ',
      'signUp': 'إنشاء حساب',
      'logIn': 'تسجيل الدخول',
      
      // 🆕 SignupScreen
      'joinUs': 'انضم إلينا وابدأ رحلتك',
      'name': 'الاسم',
      'mobileNumber': 'رقم الجوال (05XXXXXXXX)',
      'confirmPassword': 'تأكيد كلمة المرور',
      'passwordRequirements': 'متطلبات كلمة المرور:',
      'atLeast8Chars': '8 أحرف على الأقل',
      'oneUppercase': 'حرف كبير (A-Z)',
      'oneLowercase': 'حرف صغير (a-z)',
      'oneNumber': 'رقم (0-9)',
      'oneSpecialChar': 'رمز خاص',
      'passwordStrength': 'قوة كلمة المرور',
      'alreadyHaveAccount': 'لديك حساب بالفعل؟ ',
      
      // Email Verification
      'checkYourEmail': 'تحقق من بريدك الإلكتروني',
      'emailVerified': 'تم التحقق من البريد!',
      'redirectingToHome': 'جارٍ التوجيه للصفحة الرئيسية...',
      'weSentEmail': 'أرسلنا رسالة إلى',
      'important': 'مهم!',
      'checkSpam': 'تحقق من مجلد البريد المزعج!',
      'nextSteps': 'الخطوات التالية',
      'resendEmail': 'إعادة إرسال رسالة التحقق',
      'resendIn': 'إعادة الإرسال خلال',
      'seconds': 'ثانية',
      'backToLogin': 'العودة لتسجيل الدخول',
    },
  };

  return translations[_languageCode]?[key] ?? key;
}
}