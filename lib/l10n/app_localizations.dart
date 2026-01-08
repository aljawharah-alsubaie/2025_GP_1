import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';import 'package:intl/intl.dart';
import 'l10n_en.dart';
import 'l10n_ar.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ar'),
  ];

  late Map<String, String> _localizedStrings;

  Future<bool> load() async {
    if (locale.languageCode == 'ar') {
      _localizedStrings = arStrings;
    } else {
      _localizedStrings = enStrings;
    }
    return true;
  }

  String translate(String key) {
    return _localizedStrings[key] ?? key;
  }

  String get welcomeToMunir => translate('welcomeToMunir');
  String get smartAssistance => translate('smartAssistance');
  String get aiCompanion => translate('aiCompanion');
  String get readTextRecognize => translate('readTextRecognize');
  String get chooseLanguage => translate('chooseLanguage');
  String get english => translate('english');
  String get arabic => translate('arabic');
  String get continueBtn => translate('continue');
  String get createAccount => translate('createAccount');
  String get login => translate('login');
  String get welcomeBack => translate('welcomeBack');
  String get email => translate('email');
  String get password => translate('password');
  String get rememberMe => translate('rememberMe');
  String get forgotPassword => translate('forgotPassword');
  String get orContinueWith => translate('orContinueWith');
  String get continueWithGoogle => translate('continueWithGoogle');
  String get dontHaveAccount => translate('dontHaveAccount');
  String get signUp => translate('signUp');
  String get alreadyHaveAccount => translate('alreadyHaveAccount');
  String get logIn => translate('logIn');
  String get name => translate('name');
  String get mobileNumber => translate('mobileNumber');
  String get confirmPassword => translate('confirmPassword');
  String get passwordRequirements => translate('passwordRequirements');
  String get atLeast8Chars => translate('atLeast8Chars');
  String get oneUppercase => translate('oneUppercase');
  String get oneLowercase => translate('oneLowercase');
  String get oneNumber => translate('oneNumber');
  String get oneSpecialChar => translate('oneSpecialChar');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'ar'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    AppLocalizations localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}