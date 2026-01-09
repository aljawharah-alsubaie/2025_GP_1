import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../services/face_recognition_api.dart';
import 'face_rotation_capture_screen.dart';
import 'home_page.dart';
import 'reminders.dart';
import 'contact_info_page.dart';
import 'settings.dart';
import './sos_screen.dart';

class AddPersonPage extends StatefulWidget {
  const AddPersonPage({super.key});

  @override
  State<AddPersonPage> createState() => _AddPersonPageState();
}

class _AddPersonPageState extends State<AddPersonPage> {
  final TextEditingController _nameController = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  final FocusNode _nameFocusNode = FocusNode();

  List<File> _selectedImages = [];
  bool _isUploading = false;
  bool _isProcessing = false;

  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);

  @override
  void initState() {
    super.initState();
    _initTts();
    _nameFocusNode.addListener(() {
      if (_nameFocusNode.hasFocus) {
        final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
        _speak(languageProvider.isArabic
            ? 'حقل الاسم، ادخل اسم الشخص'
            : 'Name field, enter the person name');
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initTts() async {
    final languageCode = Provider.of<LanguageProvider>(context, listen: false).languageCode;
    await _tts.setLanguage(languageCode == 'ar' ? 'ar-SA' : 'en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  Future<File?> _encryptThumbnail(File imageFile, String userId) async {
    try {
      print('🔐 Starting thumbnail encryption...');

      final imageBytes = await imageFile.readAsBytes();
      print('📸 Image size: ${imageBytes.length} bytes');

      final keyString = userId.padRight(32).substring(0, 32);
      final key = encrypt.Key.fromUtf8(keyString);

      final iv = encrypt.IV.fromSecureRandom(16);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(
          key,
          mode: encrypt.AESMode.cbc,
          padding: 'PKCS7',
        ),
      );

      final encrypted = encrypter.encryptBytes(imageBytes, iv: iv);

      final combinedBytes = <int>[];
      combinedBytes.addAll(iv.bytes);
      combinedBytes.addAll(encrypted.bytes);

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final encryptedFile = File('${tempDir.path}/encrypted_thumb_$timestamp.enc');
      await encryptedFile.writeAsBytes(combinedBytes);

      print('✅ Encryption successful!');
      print('🔑 Key (first 8 chars): ${keyString.substring(0, 8)}...');
      print('🎲 IV (base64): ${iv.base64.substring(0, 12)}...');
      print('📦 Original size: ${imageBytes.length} bytes');
      print('📦 Encrypted size: ${encrypted.bytes.length} bytes');
      print('📦 Total with IV: ${combinedBytes.length} bytes');
      print('💾 Saved to: ${encryptedFile.path}');

      return encryptedFile;
    } catch (e) {
      print('❌ Encryption error: $e');
      return null;
    }
  }

  Future<void> _pickImages() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    if (_nameController.text.trim().isEmpty) {
      final msg = languageProvider.isArabic
          ? 'من فضلك ادخل الاسم أولاً'
          : 'Please enter a name first';
      _showSnackBar(msg, Colors.red);
      _speak(msg);
      return;
    }

    try {
      _speak(languageProvider.isArabic
          ? 'فتح الكاميرا لالتقاط دوران الوجه'
          : 'Opening camera for face rotation capture');

      final List<File>? capturedImages = await Navigator.push<List<File>>(
        context,
        MaterialPageRoute(
          builder: (context) => const FaceRotationCaptureScreen(),
        ),
      );

      if (capturedImages != null && capturedImages.isNotEmpty) {
        setState(() {
          _selectedImages = capturedImages;
        });
        
        final msg = languageProvider.isArabic
            ? 'تم التقاط ${capturedImages.length} صور بنجاح'
            : '${capturedImages.length} photos captured successfully';
        _showSnackBar(msg, Colors.green);
        _speak(msg);
      }
    } catch (e) {
      final msg = languageProvider.isArabic
          ? 'فشل التقاط الصور: $e'
          : 'Failed to capture images: $e';
      _showSnackBar(msg, Colors.red);
      _speak(languageProvider.isArabic ? 'فشل التقاط الصور' : 'Failed to capture images');
    }
  }

  Future<void> _addPerson() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    if (_nameController.text.trim().isEmpty) {
      final msg = languageProvider.isArabic ? 'من فضلك ادخل اسماً' : 'Please enter a name';
      _showSnackBar(msg, Colors.red);
      _speak(msg);
      return;
    }

    if (_selectedImages.length < 3) {
      final msg = languageProvider.isArabic
          ? 'من فضلك التقط صور دوران الوجه أولاً'
          : 'Please capture face rotation photos first';
      _showSnackBar(msg, Colors.red);
      _speak(msg);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_isProcessing) return;

    setState(() {
      _isUploading = true;
      _isProcessing = true;
    });

    File? encryptedThumbnail;
    try {
      final personName = _nameController.text.trim();
      _speak(languageProvider.isArabic
          ? 'تشفير ورفع الصور. انتظر من فضلك'
          : 'Encrypting and uploading photos. Please wait.');

      if (_selectedImages.isNotEmpty) {
        print('');
        print('════════════════════════════════════════');
        print('📸 Encrypting front photo as thumbnail...');
        print('════════════════════════════════════════');

        encryptedThumbnail = await _encryptThumbnail(_selectedImages[0], user.uid);

        if (encryptedThumbnail != null) {
          print('✅ Thumbnail encryption completed!');
          print('📂 File: ${encryptedThumbnail.path}');
          print('💾 Size: ${await encryptedThumbnail.length()} bytes');
        } else {
          print('⚠️ Thumbnail encryption failed, continuing without thumbnail');
        }
        print('════════════════════════════════════════');
        print('');
      }

      print('📤 Uploading to backend...');
      final result = await FaceRecognitionAPI.enrollPerson(
        name: personName,
        userId: user.uid,
        images: _selectedImages,
        encryptedThumbnail: encryptedThumbnail,
      );

      if (mounted) {
        if (result.success) {
          final msg = languageProvider.isArabic
              ? 'تمت إضافة $personName بنجاح مع ${result.successfulImages} صورة'
              : 'Person $personName added successfully with ${result.successfulImages} photo${result.successfulImages > 1 ? 's' : ''}';
          
          _showSnackBar(msg, Colors.green);
          
          await _speak(languageProvider.isArabic
              ? 'تمت إضافة $personName بنجاح مع ${result.successfulImages} صور'
              : 'Person $personName added successfully with ${result.successfulImages} photos');

          await Future.delayed(const Duration(milliseconds: 2000));
          Navigator.pop(context, true);
        } else {
          final msg = result.message ?? (languageProvider.isArabic
              ? 'فشلت إضافة الشخص'
              : 'Failed to add person');
          _showSnackBar(msg, Colors.red);
          _speak(languageProvider.isArabic
              ? 'فشلت إضافة الشخص. ${result.message}'
              : 'Failed to add person. ${result.message}');
        }
      }
    } catch (e) {
      print('❌ Error adding person: $e');
      if (mounted) {
        final msg = languageProvider.isArabic
            ? 'خطأ في إضافة الشخص: $e'
            : 'Error adding person: $e';
        _showSnackBar(msg, Colors.red);
        _speak(languageProvider.isArabic
            ? 'خطأ في إضافة الشخص، حاول مرة أخرى'
            : 'Error adding person, please try again');
      }
    } finally {
      if (encryptedThumbnail != null) {
        try {
          await encryptedThumbnail.delete();
          print('🗑️ Deleted temporary encrypted file');
        } catch (e) {
          print('⚠️ Could not delete temp file: $e');
        }
      }

      if (mounted) {
        setState(() {
          _isUploading = false;
          _isProcessing = false;
        });
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          elevation: 14,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          duration: const Duration(seconds: 2),
          content: SizedBox(
            height: 40,
            child: Row(
              children: [
                Icon(
                  color == Colors.green
                      ? Icons.check_circle
                      : Icons.error_outline,
                  color: Colors.white,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2,
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
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ultraLightPurple,
                  palePurple.withOpacity(0.3),
                  Colors.white,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildForm()),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildFloatingBottomNav(),
    );
  }

  Widget _buildHeader() {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return Container(
      padding: const EdgeInsets.fromLTRB(25, 50, 25, 30),
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
                _speak(languageProvider.isArabic ? 'العودة' : 'Going back');
                Future.delayed(const Duration(milliseconds: 800), () {
                  Navigator.pop(context);
                });
              },
              child: Container(
                width: 53,
                height: 53,
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
                    size: 21,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              languageProvider.isArabic ? 'إضافة شخص جديد' : 'Add New Person',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w900,
                foreground: Paint()
                  ..shader = const LinearGradient(
                    colors: [deepPurple, vibrantPurple],
                  ).createShader(const Rect.fromLTWH(0, 0, 240, 80)),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(27),
              boxShadow: [
                BoxShadow(
                  color: deepPurple.withOpacity(0.13),
                  blurRadius: 25,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name Field
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9.5),
                      decoration: BoxDecoration(
                        color: vibrantPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.badge_outlined,
                        color: vibrantPurple,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      languageProvider.isArabic ? 'الاسم' : "Name",
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 19.5,
                        color: deepPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                Container(
                  decoration: BoxDecoration(
                    color: ultraLightPurple.withOpacity(0.38),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: vibrantPurple.withOpacity(0.58),
                      width: 1.7,
                    ),
                  ),
                  child: TextField(
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    enabled: !_isUploading,
                    style: const TextStyle(
                      fontSize: 17.5,
                      color: deepPurple,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: languageProvider.isArabic ? 'ادخل الاسم' : "Enter name",
                      hintStyle: const TextStyle(
                        color: Color.fromARGB(255, 79, 79, 79),
                        fontSize: 16.5,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(17),
                        borderSide: const BorderSide(
                          color: vibrantPurple,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 19,
                        vertical: 20,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 33),

                // Photo Section Label
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9.5),
                      decoration: BoxDecoration(
                        color: vibrantPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: vibrantPurple,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      languageProvider.isArabic ? 'الصورة' : "Photo",
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 19.5,
                        color: deepPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // Upload Photo Container
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: _selectedImages.isNotEmpty
                        ? vibrantPurple.withOpacity(0.15)
                        : ultraLightPurple.withOpacity(0.38),
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(
                      color: _selectedImages.isNotEmpty
                          ? vibrantPurple
                          : vibrantPurple.withOpacity(0.4),
                      width: 2,
                    ),
                  ),
                  child: InkWell(
                    onTap: _isUploading || _isProcessing
                        ? null
                        : () {
                            _speak(
                              languageProvider.isArabic
                                  ? 'قسم الصورة. اضغط لبدء التقاط دوران الوجه. الكاميرا ستوجهك لالتقاط 5 صور من زوايا مختلفة'
                                  : 'Photo section. Tap to start face rotation capture. The camera will guide you to take 5 photos from different angles.',
                            );
                            _pickImages();
                          },
                    borderRadius: BorderRadius.circular(15),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _selectedImages.isNotEmpty
                                ? Icons.check_circle_outline
                                : Icons.camera_alt_outlined,
                            size: 52,
                            color: _selectedImages.isNotEmpty
                                ? vibrantPurple
                                : vibrantPurple.withOpacity(0.7),
                          ),
                          const SizedBox(height: 11),
                          Text(
                            _selectedImages.isNotEmpty
                                ? (languageProvider.isArabic
                                    ? 'تم التقاط ${_selectedImages.length} صور دوران'
                                    : '${_selectedImages.length} rotation photos captured')
                                : (languageProvider.isArabic
                                    ? 'اضغط لالتقاط دوران الوجه'
                                    : 'Tap to capture face rotation'),
                            style: const TextStyle(
                              fontSize: 17.5,
                              fontWeight: FontWeight.w600,
                              color: deepPurple,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _selectedImages.isNotEmpty
                                ? (languageProvider.isArabic
                                    ? 'اضغط لإعادة الالتقاط'
                                    : 'Tap to retake')
                                : (languageProvider.isArabic
                                    ? 'أمام، يسار، يمين، أعلى، أسفل'
                                    : 'Front, Left, Right, Up, Down'),
                            style: const TextStyle(
                              fontSize: 14.5,
                              color: deepPurple,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 29),
              ],
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 66,
            child: ElevatedButton.icon(
              onPressed: _isUploading ||
                      _isProcessing ||
                      _nameController.text.trim().isEmpty ||
                      _selectedImages.length < 3
                  ? null
                  : () {
                      _hapticFeedback();
                      _speak(
                        languageProvider.isArabic
                            ? 'زر إضافة شخص جديد، معالجة الصور. انتظر من فضلك'
                            : 'Add new person button, processing photos. Please wait.',
                      );
                      _addPerson();
                    },
              icon: _isUploading
                  ? const SizedBox(
                      width: 23,
                      height: 23,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(
                      Icons.person_add_rounded,
                      size: 27,
                      color: Colors.white,
                    ),
              label: Text(
                _isUploading
                    ? (languageProvider.isArabic
                        ? 'معالجة ${_selectedImages.length} صورة...'
                        : 'Processing ${_selectedImages.length} photo${_selectedImages.length > 1 ? 's' : ''}...')
                    : (languageProvider.isArabic ? 'إضافة شخص جديد' : "Add New Person"),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: vibrantPurple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
                disabledBackgroundColor: Colors.grey.shade300,
                elevation: 3.5,
              ),
            ),
          ),
        ],
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
                      isActive: false,
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
                      isActive: false,
                      onTap: () {
                        _speak(languageProvider.isArabic
                            ? 'جهات الاتصال، احفظ وأدر جهات الاتصال الطارئة'
                            : 'Contacts, Store and manage emergency contacts');
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
                      isActive: false,
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
      hint: description,
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