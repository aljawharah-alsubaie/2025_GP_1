import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart' as encrypt;
import '../services/face_recognition_api.dart';
import 'home_page.dart';
import 'reminders.dart';
import 'contact_info_page.dart';
import 'settings.dart';
import 'add_person_page.dart';
import 'edit_person_page.dart';
import './sos_screen.dart';

class FaceManagementPage extends StatefulWidget {
  const FaceManagementPage({super.key});

  @override
  State<FaceManagementPage> createState() => _FaceManagementPageState();
}

class _FaceManagementPageState extends State<FaceManagementPage>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  List<Map<String, dynamic>> _people = [];
  bool _isLoading = true;
  String _searchQuery = '';

  AnimationController? _fadeController;
  AnimationController? _slideController;

  // 🎨 Purple color scheme matching HomePage
  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color lightPurple = Color.fromARGB(255, 217, 163, 227);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadPeople();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tts.stop();
    _fadeController?.dispose();
    _slideController?.dispose();
    super.dispose();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
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

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  Future<void> _loadPeople() async {
    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final persons = await FaceRecognitionAPI.listPersons(user.uid);
      
      // 🔍 Debug: طباعة الـ response
      print('=====================================');
      print('📋 Total persons loaded: ${persons.length}');
      print('=====================================');
      
      for (var person in persons) {
        print('');
        print('👤 Person Name: ${person.name}');
        print('🆔 Person ID: ${person.personId}');
        print('🖼️ Thumbnail URL: ${person.thumbnailUrl}');
        print('📸 Number of photos: ${person.numPhotos}');
        print('---');
      }
      print('=====================================');
      
      if (mounted) {
        setState(() {
          _people = persons.map((person) {
            final personData = {
              'id': person.personId,
              'name': person.name,
              'photoUrls': person.thumbnailUrl != null ? [person.thumbnailUrl] : [],
              'numPhotos': person.numPhotos,
            };
            
            // 🔍 Debug: طباعة البيانات المحفوظة
            print('💾 Saved person data: $personData');
            
            return personData;
          }).toList();
          _isLoading = false;
        });

        if (persons.isEmpty) {
          _speak('No persons found. Add someone to get started.');
        } else {
          _speak('${persons.length} person${persons.length > 1 ? 's' : ''} found');
        }
      }
    } catch (e) {
      print('❌ Error loading people: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Error loading list: $e', Colors.red);
      }
    }
  }

  Future<String?> _deletePerson(String personId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      // جلب اسم الشخص قبل الحذف
      String personName = 'Unknown';
      
      // البحث عن الشخص في القائمة
      for (var p in _people) {
        if (p['id'] == personId) {
          personName = p['name'] as String? ?? 'Unknown';
          break;
        }
      }

      final success = await FaceRecognitionAPI.deletePerson(
        userId: user.uid,
        personId: personId,
      );

      if (success) {
        await _loadPeople();
        return personName;
      } else {
        _showSnackBar('Failed to delete person', Colors.red);
        return null;
      }
    } catch (e) {
      print('❌ Error deleting person: $e');
      _showSnackBar('Error deleting person: $e', Colors.red);
      return null;
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

  Future<void> _showDeleteConfirmation(
    String personId,
    String personName,
  ) async {
    _hapticFeedback();

    final safeName = (personName.isNotEmpty) ? personName : 'this person';

    await showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (dialogContext) {
        bool announced = false;
        bool isDeleting = false;

        return _fixedDialog(
          StatefulBuilder(
            builder: (context, setState) {
              if (!announced) {
                announced = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _speakNow(
                    'Delete person. Are you sure you want to delete $safeName? '
                    'This action cannot be undone. Buttons: Confirm on the top, Cancel at the bottom.',
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
                        Icons.delete_forever,
                        color: Colors.white,
                        size: 52,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Delete Person',
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
                content: Text(
                  'Are you sure you want to delete "$safeName"? '
                  'This action cannot be undone.',
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
                            onPressed: isDeleting
                                ? null
                                : () async {
                                    _hapticFeedback();
                                    setState(() => isDeleting = true);

                                    await _speakNow(
                                      'Deleting $safeName, please wait.',
                                    );

                                    final deletedName = await _deletePerson(
                                      personId,
                                    );

                                    if (!mounted) return;

                                    if (deletedName != null) {
                                      final showName = deletedName.isNotEmpty
                                          ? deletedName
                                          : safeName;

                                      _showSnackBar(
                                        '$showName deleted successfully!',
                                        Colors.green,
                                      );

                                      await _speak(
                                        'Person $showName deleted successfully.',
                                      );

                                      Navigator.pop(dialogContext);
                                    } else {
                                      setState(() => isDeleting = false);
                                      await _speak(
                                        'Failed to delete $safeName, please try again.',
                                      );
                                    }
                                  },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: isDeleting
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Color(0xFFD32F2F),
                                              ),
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Text(
                                        'Deleting...',
                                        style: TextStyle(
                                          color: Color(0xFFD32F2F),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 20,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  )
                                : const Text(
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
                            onPressed: isDeleting
                                ? null
                                : () {
                                    _hapticFeedback();
                                    Navigator.pop(dialogContext);
                                    _showSnackBar(
                                      'Deletion cancelled',
                                      Colors.red,
                                    );
                                    _speak('Deletion cancelled');
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

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;

    final overlay = Overlay.of(context, rootOverlay: true);

    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          bottom: 130,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        entry.remove();
      }
    });
  }

  List<Map<String, dynamic>> get _filteredPeople {
    if (_searchQuery.isEmpty) return _people;
    return _people
        .where(
          (person) => person['name'].toString().toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ),
        )
        .toList();
  }

  // ============================================================
  // 🔐 Build Encrypted & Decrypted Image Widget
  // ============================================================
  Widget _buildEncryptedImage(String? thumbnailUrl) {
    if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
      return Icon(
        Icons.person,
        color: deepPurple.withOpacity(0.5),
        size: 32,
      );
    }

    // تحميل وفك تشفير الصورة
    return FutureBuilder<Uint8List?>(
      future: _downloadAndDecryptImage(thumbnailUrl),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && 
            snapshot.hasData && 
            snapshot.data != null) {
          return CircleAvatar(
            radius: 32,
            backgroundColor: Colors.white,
            backgroundImage: MemoryImage(snapshot.data!),
          );
        }
        
        // Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(vibrantPurple),
            ),
          );
        }
        
        // Error or no data
        return Icon(
          Icons.person,
          color: deepPurple.withOpacity(0.5),
          size: 32,
        );
      },
    );
  }

  // ============================================================
  // 🔽 Download and Decrypt Image
  // ============================================================
  Future<Uint8List?> _downloadAndDecryptImage(String url) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      
      print('🔽 Downloading encrypted image from: $url');
      
      // 1️⃣ تحميل الملف المشفر
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode != 200) {
        print('❌ Failed to download: ${response.statusCode}');
        return null;
      }
      
      final encryptedBytes = response.bodyBytes;
      print('📦 Downloaded ${encryptedBytes.length} bytes (encrypted)');
      
      // 2️⃣ فك التشفير
      final decryptedBytes = _decryptThumbnail(encryptedBytes, user.uid);
      
      if (decryptedBytes != null) {
        print('✅ Decrypted ${decryptedBytes.length} bytes');
        return decryptedBytes;
      }
      
      print('❌ Decryption failed');
      return null;
      
    } catch (e) {
      print('❌ Error downloading/decrypting image: $e');
      return null;
    }
  }

  // ============================================================
  // 🔓 Decrypt Thumbnail (AES-256-CBC)
  // ============================================================
  Uint8List? _decryptThumbnail(Uint8List encryptedBytes, String userId) {
    try {
      print('🔓 Starting decryption...');
      
      // 1️⃣ فصل IV عن البيانات المشفرة
      if (encryptedBytes.length < 16) {
        print('❌ File too small (${encryptedBytes.length} bytes)');
        return null;
      }
      
      final iv = encrypt.IV(encryptedBytes.sublist(0, 16));
      final encryptedData = encryptedBytes.sublist(16);
      
      print('📦 IV: ${iv.bytes.length} bytes');
      print('📦 Encrypted data: ${encryptedData.length} bytes');
      
      // 2️⃣ إنشاء Key من user_id (نفس الطريقة في التشفير)
      final keyString = userId.padRight(32).substring(0, 32);
      final key = encrypt.Key.fromUtf8(keyString);
      
      print('🔑 Key (first 8 chars): ${keyString.substring(0, 8)}...');
      
      // 3️⃣ فك التشفير باستخدام AES-CBC
      final encrypter = encrypt.Encrypter(
        encrypt.AES(
          key,
          mode: encrypt.AESMode.cbc,
          padding: 'PKCS7',
        ),
      );
      
      final encrypted = encrypt.Encrypted(encryptedData);
      final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
      
      print('✅ Decryption successful! Size: ${decrypted.length} bytes');
      return Uint8List.fromList(decrypted);
      
    } catch (e) {
      print('❌ Decryption error: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
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
                  _buildModernHeader(),
                  Expanded(child: _buildPeopleList()),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [_buildAddButton(), _buildFloatingBottomNav()],
        ),
      ),
    );
  }

  Widget _buildModernHeader() {
    return FadeTransition(
      opacity: _fadeController ?? const AlwaysStoppedAnimation(1.0),
      child: Container(
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
        child: Column(
          children: [
            Row(
              children: [
                Semantics(
                  label: 'Go back to previous page',
                  button: true,
                  child: GestureDetector(
                    onTap: () {
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
                      child: const Center(
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
                        'Face Management',
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
                        'Manage saved faces',
                        style: TextStyle(
                          fontSize: 13,
                          color: deepPurple.withOpacity(0.8),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),
            Container(
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    lightPurple.withOpacity(0.3),
                    palePurple.withOpacity(0.4),
                  ],
                ),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: deepPurple.withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: vibrantPurple.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.search, color: vibrantPurple, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      decoration: InputDecoration(
                        hintText: "Search people...",
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                          color: deepPurple.withOpacity(0.7),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: const TextStyle(
                        color: deepPurple,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
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

  Widget _buildPeopleList() {
    return SlideTransition(
      position: _slideController != null
          ? Tween<Offset>(
              begin: const Offset(0, 0.15),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: _slideController!,
                curve: Curves.easeOutCubic,
              ),
            )
          : const AlwaysStoppedAnimation(Offset.zero),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: vibrantPurple))
          : _filteredPeople.isEmpty && _searchQuery.isNotEmpty
          ? _buildEmptySearch()
          : _people.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              itemCount: _filteredPeople.length,
              itemBuilder: (context, index) {
                return _buildPersonCard(_filteredPeople[index]);
              },
            ),
    );
  }

  Widget _buildPersonCard(Map<String, dynamic> person) {
    // 🔍 Debug: طباعة بيانات الشخص عند بناء الكارت
    print('🎨 Building card for: ${person['name']}');
    print('🖼️ Photo URLs: ${person['photoUrls']}');
    
    final hasPhoto = person['photoUrls'] != null && 
                     (person['photoUrls'] as List).isNotEmpty;
    
    print('✅ Has photo: $hasPhoto');
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: palePurple.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            _hapticFeedback();
            _speak(person['name'] ?? 'Unknown');
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EditPersonPage(person: person),
              ),
            );
            _loadPeople();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [vibrantPurple, primaryPurple],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromARGB(76, 142, 58, 149),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(3),
                  child: hasPhoto
                      ? _buildEncryptedImage(person['photoUrls'][0])  // ✅ فك التشفير
                      : CircleAvatar(
                          radius: 32,
                          backgroundColor: Colors.white,
                          child: Icon(
                            Icons.person,
                            color: deepPurple.withOpacity(0.5),
                            size: 32,
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person['name'] ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: deepPurple,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${person['numPhotos'] ?? 0} photo${(person['numPhotos'] ?? 0) > 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: deepPurple.withOpacity(0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    _hapticFeedback();
                    _speak('Edit ${person['name']}');
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditPersonPage(person: person),
                      ),
                    );
                    _loadPeople();
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: vibrantPurple.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: vibrantPurple.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.edit_outlined,
                      color: vibrantPurple,
                      size: 20,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    _hapticFeedback();
                    _showDeleteConfirmation(
                      person['id'],
                      person['name'] ?? 'Unknown',
                    );
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.red.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySearch() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: deepPurple.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              "No people found",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: deepPurple,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Try a different search term",
              style: TextStyle(
                fontSize: 14,
                color: deepPurple.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    vibrantPurple.withOpacity(0.2),
                    primaryPurple.withOpacity(0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.person_add_outlined,
                size: 50,
                color: vibrantPurple,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "No people added yet",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: deepPurple,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Tap the button below to add your first person",
              style: TextStyle(
                fontSize: 14,
                color: deepPurple.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Semantics(
        label: 'Add new person',
        button: true,
        hint: 'Double tap to add a new person',
        child: GestureDetector(
          onTap: () async {
            _hapticFeedback();
            _speak('Add New Person');
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddPersonPage()),
            );
            _loadPeople();
          },
          child: Container(
            width: double.infinity,
            height: 70,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [deepPurple, vibrantPurple],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: vibrantPurple.withOpacity(0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_add,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Add New Person',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
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