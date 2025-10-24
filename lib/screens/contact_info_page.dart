import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import './reminders.dart';
import './home_page.dart';
import './settings.dart';

class ContactInfoPage extends StatefulWidget {
  const ContactInfoPage({super.key});

  @override
  State<ContactInfoPage> createState() => _ContactInfoPageState();
}

class _ContactInfoPageState extends State<ContactInfoPage>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterTts _tts = FlutterTts();
  late stt.SpeechToText _speech;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _isListening = false;

  // Voice control state
  int _voiceStep = 0;
  String _voiceName = '';
  String _voicePhone = '';
  bool _isVoiceMode = false;
  String? _editingContactId; // For voice edit mode

  AnimationController? _fadeController;
  AnimationController? _slideController;
  late AnimationController _pulseController;

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
    _initSpeech();
    _loadContacts();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> _initSpeech() async {
    _speech = stt.SpeechToText();
    bool available = await _speech.initialize(
      onError: (error) {
        print('Speech error: $error');

        String errorMsg = error.errorMsg.toLowerCase();

        if (errorMsg.contains('no_match') || errorMsg.contains('no match')) {
          print('No speech detected - cancelling voice mode');
          if (mounted && _isVoiceMode) {
            setState(() {
              _isVoiceMode = false;
              _isListening = false;
              _voiceStep = 0;
              _editingContactId = null;
            });
            _speak('Could not hear you clearly. Voice contact cancelled');
          }
        } else if (errorMsg.contains('network')) {
          if (mounted && _isVoiceMode) {
            setState(() {
              _isVoiceMode = false;
              _isListening = false;
              _voiceStep = 0;
              _editingContactId = null;
            });
            _speak('Network error. Voice contact cancelled');
          }
        } else if (errorMsg.contains('permission')) {
          if (mounted && _isVoiceMode) {
            setState(() {
              _isVoiceMode = false;
              _isListening = false;
              _voiceStep = 0;
              _editingContactId = null;
            });
            _speak('Microphone permission denied. Voice contact cancelled');
          }
        } else {
          if (mounted && _isVoiceMode) {
            setState(() {
              _isVoiceMode = false;
              _isListening = false;
              _voiceStep = 0;
              _editingContactId = null;
            });
            _speak('Speech recognition error. Voice contact cancelled');
          }
        }
      },
      onStatus: (status) {
        print('Speech status: $status');
      },
    );

    if (!available) {
      print('Speech recognition not available');
      _speak(
        'Speech recognition is not available on this device. Please install Google Speech Services from Play Store',
      );
    } else {
      print('Speech recognition initialized successfully');
    }
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _tts.stop();
    _speech.stop();
    _searchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _fadeController?.dispose();
    _slideController?.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  bool _isValidSaudiPhoneNumber(String phone) {
    String cleanPhone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    if (cleanPhone.startsWith('+966')) {
      cleanPhone = cleanPhone.substring(4);
      return cleanPhone.length == 9 &&
          RegExp(r'^[5][0-9]{8}$').hasMatch(cleanPhone);
    }

    if (cleanPhone.startsWith('966')) {
      cleanPhone = cleanPhone.substring(3);
      return cleanPhone.length == 9 &&
          RegExp(r'^[5][0-9]{8}$').hasMatch(cleanPhone);
    }

    if (cleanPhone.startsWith('05')) {
      return cleanPhone.length == 10 &&
          RegExp(r'^05[0-9]{8}$').hasMatch(cleanPhone);
    }

    if (cleanPhone.length == 9 && cleanPhone.startsWith('5')) {
      return RegExp(r'^[5][0-9]{8}$').hasMatch(cleanPhone);
    }

    return false;
  }

  String _formatPhoneNumber(String phone) {
    String cleanPhone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    if (cleanPhone.startsWith('+966')) {
      return cleanPhone;
    } else if (cleanPhone.startsWith('966')) {
      return '+$cleanPhone';
    } else if (cleanPhone.startsWith('05')) {
      return '+966${cleanPhone.substring(1)}';
    } else if (cleanPhone.length == 9 && cleanPhone.startsWith('5')) {
      return '+966$cleanPhone';
    }

    return cleanPhone;
  }

  Future<void> _loadContacts() async {
    try {
      final User? user = _auth.currentUser;
      if (user == null) return;

      final QuerySnapshot snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('contacts')
          .orderBy('name')
          .get();

      setState(() {
        _contacts = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;
          return data;
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading contacts: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 🎤 Voice Control Methods
  Future<void> _startVoiceContact({
    String? editContactId,
    String? currentName,
    String? currentPhone,
  }) async {
    if (!_speech.isAvailable) {
      _speak(
        'Speech recognition is not available. Please install Google Speech Services from Play Store',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Speech recognition not available. Install Google Speech Services',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
      return;
    }

    setState(() {
      _isVoiceMode = true;
      _voiceStep = 0;
      _voiceName = currentName ?? '';
      _voicePhone = currentPhone ?? '';
      _editingContactId = editContactId;
    });

    _hapticFeedback();

    if (editContactId != null) {
      await _speak(
        'Starting voice edit for $currentName. Please tell me the new name, or say same to keep it',
      );
    } else {
      await _speak('Starting voice contact. Please tell me the contact name');
    }

    await Future.delayed(const Duration(milliseconds: 3000));
    _listenForVoiceInput();
  }

  Future<void> _listenForVoiceInput() async {
    if (!_speech.isAvailable) {
      _speak('Speech recognition is not available');
      setState(() {
        _isVoiceMode = false;
        _isListening = false;
        _voiceStep = 0;
        _editingContactId = null;
      });
      return;
    }

    setState(() => _isListening = true);

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _processVoiceInput(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 10),
      localeId: 'en_US',
      cancelOnError: false,
      partialResults: false,
    );
  }

  Future<void> _processVoiceInput(String input) async {
    setState(() => _isListening = false);

    if (input.isEmpty) {
      await _speak('Could not hear you clearly. Voice contact cancelled');
      setState(() {
        _isVoiceMode = false;
        _voiceStep = 0;
        _editingContactId = null;
      });
      return;
    }

    switch (_voiceStep) {
      case 0: // Name
        if (_editingContactId != null && input.toLowerCase().contains('same')) {
          // Keep the same name
          await _speak(
            'Keeping the name as $_voiceName. Now, please say the phone number, or say same to keep it',
          );
        } else {
          _voiceName = input;
          await _speak(
            'Got it. Name is: $input. Now, please say the phone number',
          );
        }
        setState(() => _voiceStep = 1);
        await Future.delayed(const Duration(milliseconds: 3500));
        _listenForVoiceInput();
        break;

      case 1: // Phone
        if (_editingContactId != null && input.toLowerCase().contains('same')) {
          // Keep the same phone
          await _speak('Keeping the phone number. Updating contact now');
          await Future.delayed(const Duration(milliseconds: 2000));
          await _saveVoiceContact();
        } else {
          final phoneNumber = _extractPhoneNumber(input);
          if (phoneNumber != null && _isValidSaudiPhoneNumber(phoneNumber)) {
            _voicePhone = phoneNumber;
            await _speak(
              'Perfect. Phone number is $phoneNumber. ${_editingContactId != null ? "Updating" : "Creating"} contact now',
            );
            await Future.delayed(const Duration(milliseconds: 2000));
            await _saveVoiceContact();
          } else {
            await _speak(
              'Sorry, I could not understand the phone number. Please say it again. For example: zero five one two three four five six seven eight',
            );
            await Future.delayed(const Duration(milliseconds: 3500));
            _listenForVoiceInput();
          }
        }
        break;
    }
  }

  String? _extractPhoneNumber(String input) {
    // Remove common words
    String cleaned = input
        .toLowerCase()
        .replaceAll('zero', '0')
        .replaceAll('one', '1')
        .replaceAll('two', '2')
        .replaceAll('three', '3')
        .replaceAll('four', '4')
        .replaceAll('five', '5')
        .replaceAll('six', '6')
        .replaceAll('seven', '7')
        .replaceAll('eight', '8')
        .replaceAll('nine', '9')
        .replaceAll(' ', '');

    // Extract numbers only
    String numbers = cleaned.replaceAll(RegExp(r'[^0-9+]'), '');

    if (numbers.isEmpty) return null;

    return numbers;
  }

  Future<void> _saveVoiceContact() async {
    try {
      final User? user = _auth.currentUser;
      if (user == null) return;

      final formattedPhone = _formatPhoneNumber(_voicePhone);

      if (_editingContactId != null) {
        // Update existing contact
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('contacts')
            .doc(_editingContactId)
            .update({'name': _voiceName, 'phone': formattedPhone});

        await _loadContacts();

        setState(() {
          _isVoiceMode = false;
          _voiceStep = 0;
          _editingContactId = null;
        });

        _hapticFeedback();
        await _speak(
          'Contact updated successfully. Name: $_voiceName, Phone: $formattedPhone',
        );
      } else {
        // Add new contact
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('contacts')
            .add({
              'name': _voiceName,
              'phone': formattedPhone,
              'createdAt': FieldValue.serverTimestamp(),
            });

        await _loadContacts();

        setState(() {
          _isVoiceMode = false;
          _voiceStep = 0;
        });

        _hapticFeedback();
        await _speak(
          'Contact created successfully. Name: $_voiceName, Phone: $formattedPhone',
        );
      }
    } catch (e) {
      print('Error saving voice contact: $e');
      await _speak(
        'Sorry, there was an error saving the contact. Please try again',
      );
      setState(() {
        _isVoiceMode = false;
        _voiceStep = 0;
        _editingContactId = null;
      });
    }
  }

  Future<void> _deleteContact(String contactId, String contactName) async {
    final User? user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('contacts')
          .doc(contactId)
          .delete();

      await _loadContacts();

      if (mounted) {
        _showSnackBar('$contactName deleted successfully!', Colors.green);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error deleting contact: $e', Colors.red);
      }
    }
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

  void _showDeleteConfirmation(String contactId, String contactName) {
    _hapticFeedback();
    _speak('Delete $contactName');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
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
                      'Delete Contact',
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
                        text: '"$contactName"',
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
                          _speak('Cancelled');
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          backgroundColor: deepPurple.withOpacity(0.15),
                          foregroundColor: deepPurple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: vibrantPurple.withOpacity(0.35),
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
                          await _deleteContact(contactId, contactName);
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
        );
      },
    );
  }

  List<Map<String, dynamic>> get _filteredContacts {
    if (_searchQuery.isEmpty) return _contacts;
    return _contacts
        .where(
          (contact) =>
              contact['name'].toString().toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              contact['phone'].toString().toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ),
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
                Expanded(child: _buildContactsList()),
              ],
            ),
          ),
          if (_isVoiceMode || _isListening) _buildVoiceOverlay(),
        ],
      ),
      bottomNavigationBar: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [_buildVoiceAddButton(), _buildFloatingBottomNav()],
          ),
          if (_isVoiceMode || _isListening)
            Positioned.fill(
              child: Container(color: Colors.black.withOpacity(0.85)),
            ),
        ],
      ),
    );
  }

  Widget _buildModernHeader() {
    return FadeTransition(
      opacity: _fadeController ?? const AlwaysStoppedAnimation(1.0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(25, 50, 25, 45),
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
                  label: 'Back to home',
                  button: true,
                  child: GestureDetector(
                    onTap: () {
                      _hapticFeedback();
                      _speak('Going back');
                      Navigator.pop(context);
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
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emergency Contacts',
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
                        '${_contacts.length} Contacts',
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
                        hintText: "Search contacts...",
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

  Widget _buildContactsList() {
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
          : _filteredContacts.isEmpty && _searchQuery.isNotEmpty
          ? _buildEmptySearch()
          : _contacts.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              itemCount: _filteredContacts.length,
              itemBuilder: (context, index) {
                return _buildContactCard(_filteredContacts[index]);
              },
            ),
    );
  }

  Widget _buildContactCard(Map<String, dynamic> contact) {
    return Semantics(
      label:
          'Contact: ${contact['name']}. Phone: ${contact['phone']}. Double tap to edit',
      button: true,
      child: Container(
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
            onTap: () {
              _hapticFeedback();
              _speak('${contact['name']}. ${contact['phone']}');
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
                      radius: 25,
                      backgroundColor: Colors.white,
                      child: Text(
                        contact['name']
                                ?.toString()
                                .substring(0, 1)
                                .toUpperCase() ??
                            '?',
                        style: TextStyle(
                          color: deepPurple,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
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
                          contact['name']?.toString() ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: deepPurple,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.phone,
                              size: 14,
                              color: vibrantPurple.withOpacity(0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              contact['phone']?.toString() ?? 'No phone',
                              style: TextStyle(
                                fontSize: 13,
                                color: deepPurple.withOpacity(0.5),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      _hapticFeedback();
                      _speak('Edit ${contact['name']} with voice');
                      _startVoiceContact(
                        editContactId: contact['id'],
                        currentName: contact['name']?.toString(),
                        currentPhone: contact['phone']?.toString(),
                      );
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
                        Icons.mic,
                        color: vibrantPurple,
                        size: 20,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      _hapticFeedback();
                      _showDeleteConfirmation(
                        contact['id'],
                        contact['name']?.toString() ?? 'Unknown',
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
              "No contacts found",
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
              "No contacts added yet",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: deepPurple,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Tap the button below to add your first contact",
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

  Widget _buildVoiceOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(40),
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: vibrantPurple.withOpacity(0.3),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 + (_pulseController.value * 0.2),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [vibrantPurple, primaryPurple],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: vibrantPurple.withOpacity(0.5),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
              Text(
                _isListening ? 'Listening...' : _getVoiceStepText(),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: deepPurple,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _getVoiceStepHint(),
                style: TextStyle(
                  fontSize: 14,
                  color: deepPurple.withOpacity(0.6),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              Semantics(
                label: 'Cancel voice input',
                button: true,
                child: OutlinedButton(
                  onPressed: () {
                    _hapticFeedback();
                    _speak('Cancelled');
                    _speech.stop();
                    setState(() {
                      _isVoiceMode = false;
                      _isListening = false;
                      _voiceStep = 0;
                      _editingContactId = null;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 16,
                    ),
                    side: const BorderSide(color: vibrantPurple, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: vibrantPurple,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getVoiceStepText() {
    switch (_voiceStep) {
      case 0:
        return _editingContactId != null
            ? 'Update contact name?'
            : 'What\'s the contact name?';
      case 1:
        return _editingContactId != null
            ? 'Update phone number?'
            : 'What\'s the phone number?';
      default:
        return 'Processing...';
    }
  }

  String _getVoiceStepHint() {
    switch (_voiceStep) {
      case 0:
        return _editingContactId != null
            ? 'Say the new name or "same" to keep it\nCurrent: $_voiceName'
            : 'Say the contact\'s full name';
      case 1:
        return _editingContactId != null
            ? 'Say the new phone number or "same" to keep it\nExample: "zero five one two three..."\nCurrent: $_voicePhone'
            : 'Say the phone number digit by digit\nExample: "zero five one two three four five six seven eight"';
      default:
        return '';
    }
  }

  Widget _buildVoiceAddButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 25),
      child: Semantics(
        label: 'Add new contact with voice',
        button: true,
        hint: 'Double tap to add a new contact using voice commands',
        child: GestureDetector(
          onTap: () {
            _hapticFeedback();
            _startVoiceContact();
          },
          child: Container(
            width: double.infinity,
            height: 58,
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
                  child: const Icon(Icons.mic, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Add Voice Contact',
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
      ),
    );
  }

  Widget _buildFloatingBottomNav() {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
      ),
      child: Container(
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavButton(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  onTap: () {
                    _hapticFeedback();
                    _speak('Home');
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const HomePage()),
                    );
                  },
                ),
                _buildNavButton(
                  icon: Icons.notifications_rounded,
                  label: 'Reminders',
                  onTap: () {
                    _hapticFeedback();
                    _speak('Reminders');
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RemindersPage(),
                      ),
                    );
                  },
                ),
                _buildNavButton(
                  icon: Icons.contact_phone,
                  label: 'Emergency',
                  isActive: true,
                  onTap: () {
                    _hapticFeedback();
                    _speak('Emergency Contact');
                  },
                ),
                _buildNavButton(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  onTap: () {
                    _hapticFeedback();
                    _speak('Settings');
                    Navigator.pushReplacement(
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
    );
  }

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
                color: isActive ? Colors.white : Colors.white.withOpacity(0.9),
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
