import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_tts/flutter_tts.dart';
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
    await _tts.speak(text);
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

<<<<<<< HEAD
  // 🔗 تهيئة الاتصال بالـ API
  Future<void> _initializeAPI() async {
    try {
      _apiConnected = await FaceRecognitionAPI.testConnection();
      if (_apiConnected) {
        print('✅ API Connected Successfully');
        if (mounted) {
          _showSnackBar('API Connected Successfully!', Colors.green);
        }
      } else {
        print('❌ API Connection Failed');
        if (mounted) {
          _showSnackBar('API Connection Failed', Colors.red);
        }
      }
    } catch (e) {
      print('❌ API Initialization Error: $e');
      _apiConnected = false;
    }
    setState(() {});
  }

  // 🔍 البحث باستخدام الـ API
  Future<void> _searchFacesWithAPI(String query) async {
    if (query.length < 2) return;

    try {
      // يمكنك إضافة دالة بحث في الـ API إذا كانت متوفرة
      setState(() {
        _searchQuery = query;
      });
    } catch (e) {
      print('❌ API Search Error: $e');
    }
  }

=======
>>>>>>> 8d88700b34ef62aa22e05db0d80f9531710f18e3
  Future<void> _loadPeople() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('people')
          .orderBy('createdAt', descending: true)
          .get();

      setState(() {
        _people = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading people: $e')));
      }
    }
  }

  Future<void> _deletePerson(String personId, String personName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // حذف من Firebase فقط
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('people')
          .doc(personId)
          .delete();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('face_embeddings')
          .doc(personName)
          .delete();

      await _loadPeople();

      if (mounted) {
        _showSnackBar('$personName deleted successfully!', Colors.green);
        _speak('$personName deleted successfully');
      }
    } catch (e) {
      _showSnackBar('Error deleting person: $e', Colors.red);
      _speak('Error deleting person');
    }
  }

  void _showDeleteConfirmation(String personId, String personName) {
    _hapticFeedback();
    _speak('Are you sure you want to delete $personName');

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Text(
                    'Delete Person',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: deepPurple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  text: 'Are you sure you want to delete ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: deepPurple,
                  ),
                  children: [
                    TextSpan(
                      text: '"$personName"',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: deepPurple,
                        fontSize: 17,
                      ),
                    ),
                    const TextSpan(text: '?'),
                  ],
                ),
              ),
              const SizedBox(height: 60),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _hapticFeedback();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        backgroundColor: deepPurple.withOpacity(0.15),
                        foregroundColor: deepPurple,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: deepPurple.withOpacity(0.35),
                            width: 1.3,
                          ),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        _hapticFeedback();
                        Navigator.pop(context);
                        await _deletePerson(personId, personName);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

<<<<<<< HEAD
  // 🔗 اختبار التعرف باستخدام الـ API
  Future<void> _testAPIRecognition() async {
    _hapticFeedback();
    _speak('Testing face recognition');

    try {
      _showSnackBar('Testing API Recognition...', Colors.blue);

      // هنا يمكنك إضافة كود لالتقاط صورة أو استخدام صورة اختبار
      // مثال: يمكنك استبدال هذا بكود الالتقاط الفعلي
      // final result = await FaceRecognitionAPI.recognizeFace(testImageBytes);

      // _showSnackBar(
      //   'API Result: ${result.personId} (${result.similarity.toStringAsFixed(1)}%)',
      //   result.isMatch ? Colors.green : Colors.orange,
      // );

      // _speak('Recognized as ${result.personId} with ${result.similarity.toStringAsFixed(1)} percent accuracy');

      _showSnackBar('Face recognition test initiated', Colors.blue);
      _speak('Recognition test started');
    } catch (e) {
      _showSnackBar('Recognition test failed: $e', Colors.red);
      _speak('Recognition test failed');
    }
  }

  // 🔗 الحصول على قائمة الوجوه من الـ API
  Future<void> _loadFacesFromAPI() async {
    try {
      final facesList = await FaceRecognitionAPI.getFacesList();
      print('📋 Faces from API: $facesList');

      if (facesList.isNotEmpty) {
        _showSnackBar(
          'Loaded ${facesList.length} faces from API',
          Colors.green,
        );
      }
    } catch (e) {
      print('❌ Error loading faces from API: $e');
    }
  }

=======
>>>>>>> 8d88700b34ef62aa22e05db0d80f9531710f18e3
  List<Map<String, dynamic>> get _filteredPeople {
    if (_searchQuery.isEmpty) return _people;
    return _people
        .where(
          (person) =>
              person['name'].toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
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
                GestureDetector(
                  onTap: () {
                    _hapticFeedback();
                    _tts.stop(); // ✅ يوقف الكلام فوراً
                    _speak('Going back');
                    Future.delayed(const Duration(milliseconds: 800), () {
                      Navigator.pop(context);
                    });
                  },
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [vibrantPurple, primaryPurple],
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(18)),
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromARGB(76, 142, 58, 149),
                          blurRadius: 12,
                          offset: Offset(0, 4),
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
<<<<<<< HEAD
                // 🔗 مؤشر حالة الـ API
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _apiConnected
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _apiConnected ? Colors.green : Colors.red,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _apiConnected ? Icons.cloud_done : Icons.cloud_off,
                        size: 12,
                        color: _apiConnected ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _apiConnected ? 'API Connected' : 'API Offline',
                        style: TextStyle(
                          fontSize: 10,
                          color: _apiConnected ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
=======
>>>>>>> 8d88700b34ef62aa22e05db0d80f9531710f18e3
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
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    backgroundImage:
                        person['photoUrls'] != null &&
                            (person['photoUrls'] as List).isNotEmpty
                        ? NetworkImage(person['photoUrls'][0])
                        : null,
                    child:
                        person['photoUrls'] == null ||
                            (person['photoUrls'] as List).isEmpty
                        ? Icon(
                            Icons.person,
                            color: deepPurple.withOpacity(0.5),
                            size: 32,
                          )
                        : null,
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
<<<<<<< HEAD
                      // 🔗 حالة الـ API
                      Row(
                        children: [
                          Icon(
                            _apiConnected ? Icons.cloud_done : Icons.cloud_off,
                            size: 14,
                            color: _apiConnected ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _apiConnected ? 'API Ready' : 'API Offline',
                            style: TextStyle(
                              fontSize: 12,
                              color: _apiConnected
                                  ? Colors.green
                                  : Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
=======
>>>>>>> 8d88700b34ef62aa22e05db0d80f9531710f18e3
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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
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
          height: 58,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [deepPurple, vibrantPurple]),
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
                child: const Icon(Icons.add, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                'Add New Person',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 📍 Bottom Navigation - الفوتر الجديد مع الدائرة الحمراء
  Widget _buildFloatingBottomNav() {
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        // الفوتر الأساسي
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          child: Container(
            height: 90,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildNavButton(
                      icon: Icons.home_rounded,
                      label: 'Home',
                      isActive: true,
                      onTap: () {
                        _hapticFeedback();
                        _speak('Home');
                        Navigator.pushReplacement(
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
                      onTap: () {
                        _hapticFeedback();
                        _speak('Reminders');
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RemindersPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 60), // مساحة للدائرة
                    _buildNavButton(
                      icon: Icons.contacts_rounded,
                      label: 'Contacts',
                      onTap: () {
                        _hapticFeedback();
                        _speak('Contact');
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
                      onTap: () {
                        _hapticFeedback();
                        _speak('Settings');
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

        // 🔴 الدائرة الكبيرة للطوارئ
        Positioned(
          bottom: 35,
          child: Semantics(
            label: 'Emergency SOS button',
            button: true,
            hint: 'Double tap for emergency',
            child: GestureDetector(
              onTap: () {
                _hapticFeedback();
                _speak('Emergency SOS');
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SosScreen()),
                );
              },
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.red.shade400, Colors.red.shade700],
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.6),
                      blurRadius: 25,
                      spreadRadius: 3,
                    ),
                    BoxShadow(
                      color: Colors.red.withOpacity(0.3),
                      blurRadius: 40,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.emergency_outlined,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 🔘 Navigation button
  Widget _buildNavButton({
    required IconData icon,
    required String label,
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                size: 22,
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
