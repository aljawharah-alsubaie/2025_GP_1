import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import './settings.dart';
import './home_page.dart';
import './contact_info_page.dart';

class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key});

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterTts _tts = FlutterTts();
  late stt.SpeechToText _speech;

  List<ReminderItem> reminders = [];
  bool isLoading = true;
  bool _isListening = false;

  // Voice control state
  int _voiceStep = 0;
  String _voiceTitle = '';
  String _voiceDate = '';
  String _voiceTime = '';
  String _voiceFrequency = 'One time';
  bool _isVoiceMode = false;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;

  // 🎨 نظام ألوان موحد
  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);

  @override
  void initState() {
    super.initState();
    _initTts();
    _initSpeech();
    _loadReminders();

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
    _tts.setCompletionHandler(() {
      print('TTS completed');
    });
  }

  Future<void> _initSpeech() async {
    _speech = stt.SpeechToText();
    bool available = await _speech.initialize(
      onError: (error) {
        print('Speech error: $error');
        
        // 🔍 التعامل مع أنواع الأخطاء المختلفة
        String errorMsg = error.errorMsg.toLowerCase();
        
        if (errorMsg.contains('no_match') || errorMsg.contains('no match')) {
          // ❌ لم يتم التعرف على أي كلام
          print('No speech detected - cancelling voice mode');
          if (mounted && _isVoiceMode) {
            setState(() {
              _isVoiceMode = false;
              _isListening = false;
              _voiceStep = 0;
            });
            _speak('Could not hear you clearly. Voice reminder cancelled');
          }
        } else if (errorMsg.contains('network')) {
          if (mounted && _isVoiceMode) {
            setState(() {
              _isVoiceMode = false;
              _isListening = false;
              _voiceStep = 0;
            });
            _speak('Network error. Voice reminder cancelled');
          }
        } else if (errorMsg.contains('permission')) {
          if (mounted && _isVoiceMode) {
            setState(() {
              _isVoiceMode = false;
              _isListening = false;
              _voiceStep = 0;
            });
            _speak('Microphone permission denied. Voice reminder cancelled');
          }
        } else {
          // خطأ عام - نلغي الـ voice mode
          if (mounted && _isVoiceMode) {
            setState(() {
              _isVoiceMode = false;
              _isListening = false;
              _voiceStep = 0;
            });
            _speak('Speech recognition error. Voice reminder cancelled');
          }
        }
      },
      onStatus: (status) {
        print('Speech status: $status');
        
        // 📊 تتبع حالة الاستماع
        if (status == 'done' || status == 'notListening') {
          print('Listening session ended');
        }
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

  Future<void> _loadReminders() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final querySnapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('reminders')
            .orderBy('date')
            .get();

        setState(() {
          reminders = querySnapshot.docs.map((doc) {
            final data = doc.data();
            return ReminderItem(
              id: doc.id,
              title: data['title'] ?? '',
              time: data['time'] ?? '',
              date: (data['date'] as Timestamp).toDate(),
              frequency: data['frequency'] ?? 'One time',
            );
          }).toList();
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading reminders: $e');
      setState(() => isLoading = false);
    }
  }

  // 🎤 Voice Control Methods
  Future<void> _startVoiceReminder() async {
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
      _voiceTitle = '';
      _voiceDate = '';
      _voiceTime = '';
      _voiceFrequency = 'One time';
    });

    _hapticFeedback();
    await _speak(
      'Starting voice reminder. Please tell me the title of your reminder',
    );
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
      await _speak('Could not hear you clearly. Voice reminder cancelled');
      setState(() {
        _isVoiceMode = false;
        _voiceStep = 0;
      });
      return;
    }

    switch (_voiceStep) {
      case 0: // Title
        _voiceTitle = input;
        await _speak(
          'Got it. Title is: $input. Now, when would you like to be reminded? Say the date and time',
        );
        setState(() => _voiceStep = 1);
        await Future.delayed(const Duration(milliseconds: 4000));
        _listenForVoiceInput();
        break;

      case 1: // Date & Time
        final dateTime = _parseDateTimeFromVoice(input);
        if (dateTime != null) {
          _voiceDate = '${dateTime.day}/${dateTime.month}/${dateTime.year}';
          _voiceTime = _formatTime(dateTime);
          await _speak(
            'Perfect. Reminder set for ${_formatDateForSpeech(dateTime)} at ${_voiceTime}. Would you like this reminder to repeat? Say one time, daily, or weekly',
          );
          setState(() => _voiceStep = 2);
          await Future.delayed(const Duration(milliseconds: 4000));
          _listenForVoiceInput();
        } else {
          await _speak(
            'Sorry, I could not understand the date and time. Please try again. For example, say: tomorrow at 5 PM, or next Monday at 3 PM',
          );
          await Future.delayed(const Duration(milliseconds: 3500));
          _listenForVoiceInput();
        }
        break;

      case 2: // Frequency
        if (input.toLowerCase().contains('daily')) {
          _voiceFrequency = 'Daily';
        } else if (input.toLowerCase().contains('weekly')) {
          _voiceFrequency = 'Weekly';
        } else {
          _voiceFrequency = 'One time';
        }

        await _speak(
          'Understood. Frequency is ${_voiceFrequency}. Creating your reminder now',
        );
        await Future.delayed(const Duration(milliseconds: 2000));
        await _saveVoiceReminder();
        break;
    }
  }

  DateTime? _parseDateTimeFromVoice(String input) {
    final now = DateTime.now();
    final lowerInput = input.toLowerCase();
    DateTime? date;
    TimeOfDay? time;

    // Parse date
    if (lowerInput.contains('today')) {
      date = now;
    } else if (lowerInput.contains('tomorrow')) {
      date = now.add(const Duration(days: 1));
    } else if (lowerInput.contains('next monday') ||
        lowerInput.contains('monday')) {
      int daysToAdd = (DateTime.monday - now.weekday + 7) % 7;
      if (daysToAdd == 0) daysToAdd = 7;
      date = now.add(Duration(days: daysToAdd));
    } else if (lowerInput.contains('next tuesday') ||
        lowerInput.contains('tuesday')) {
      int daysToAdd = (DateTime.tuesday - now.weekday + 7) % 7;
      if (daysToAdd == 0) daysToAdd = 7;
      date = now.add(Duration(days: daysToAdd));
    } else if (lowerInput.contains('next wednesday') ||
        lowerInput.contains('wednesday')) {
      int daysToAdd = (DateTime.wednesday - now.weekday + 7) % 7;
      if (daysToAdd == 0) daysToAdd = 7;
      date = now.add(Duration(days: daysToAdd));
    } else if (lowerInput.contains('next thursday') ||
        lowerInput.contains('thursday')) {
      int daysToAdd = (DateTime.thursday - now.weekday + 7) % 7;
      if (daysToAdd == 0) daysToAdd = 7;
      date = now.add(Duration(days: daysToAdd));
    } else if (lowerInput.contains('next friday') ||
        lowerInput.contains('friday')) {
      int daysToAdd = (DateTime.friday - now.weekday + 7) % 7;
      if (daysToAdd == 0) daysToAdd = 7;
      date = now.add(Duration(days: daysToAdd));
    } else if (lowerInput.contains('next saturday') ||
        lowerInput.contains('saturday')) {
      int daysToAdd = (DateTime.saturday - now.weekday + 7) % 7;
      if (daysToAdd == 0) daysToAdd = 7;
      date = now.add(Duration(days: daysToAdd));
    } else if (lowerInput.contains('next sunday') ||
        lowerInput.contains('sunday')) {
      int daysToAdd = (DateTime.sunday - now.weekday + 7) % 7;
      if (daysToAdd == 0) daysToAdd = 7;
      date = now.add(Duration(days: daysToAdd));
    } else {
      date = now;
    }

    // Parse time
    final timeRegex = RegExp(
      r'(\d{1,2})\s*(am|pm|a\.m\.|p\.m\.)?',
      caseSensitive: false,
    );
    final match = timeRegex.firstMatch(lowerInput);

    if (match != null) {
      int hour = int.parse(match.group(1)!);
      final period = match.group(2)?.toLowerCase() ?? '';

      if (period.contains('pm') && hour != 12) {
        hour += 12;
      } else if (period.contains('am') && hour == 12) {
        hour = 0;
      } else if (period.isEmpty &&
          hour < 12 &&
          lowerInput.contains('evening')) {
        hour += 12;
      } else if (period.isEmpty && hour < 8) {
        hour += 12;
      }

      time = TimeOfDay(hour: hour, minute: 0);
    }

    if (time != null) {
      return DateTime(date.year, date.month, date.day, time.hour, time.minute);
    }

    return null;
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour > 12
        ? dateTime.hour - 12
        : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')} $period';
  }

  String _formatDateForSpeech(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'today';
    } else if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day + 1) {
      return 'tomorrow';
    } else {
      return '${_getWeekdayName(date.weekday)}, ${_getMonthName(date.month)} ${date.day}';
    }
  }

  String _getWeekdayName(int weekday) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return weekdays[weekday - 1];
  }

  Future<void> _saveVoiceReminder() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final parts = _voiceDate.split('/');
      final date = DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );

      final reminderData = {
        'title': _voiceTitle,
        'time': _voiceTime,
        'date': Timestamp.fromDate(date),
        'frequency': _voiceFrequency,
        'created_at': FieldValue.serverTimestamp(),
      };

      final docRef = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('reminders')
          .add(reminderData);

      setState(() {
        reminders.add(
          ReminderItem(
            id: docRef.id,
            title: _voiceTitle,
            time: _voiceTime,
            date: date,
            frequency: _voiceFrequency,
          ),
        );
        reminders.sort((a, b) => a.date.compareTo(b.date));
        _isVoiceMode = false;
        _voiceStep = 0;
      });

      _hapticFeedback();
      await _speak(
        'Reminder created successfully. Title: $_voiceTitle, Time: $_voiceTime, Frequency: $_voiceFrequency',
      );
    } catch (e) {
      print('Error saving voice reminder: $e');
      await _speak(
        'Sorry, there was an error creating your reminder. Please try again',
      );
      setState(() {
        _isVoiceMode = false;
        _voiceStep = 0;
      });
    }
  }

  Future<void> _deleteReminderFromFirestore(String reminderId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('reminders')
          .doc(reminderId)
          .delete();

      setState(() {
        reminders.removeWhere((reminder) => reminder.id == reminderId);
      });

      _speak('Reminder deleted');
      _hapticFeedback();
    } catch (e) {
      print('Error deleting reminder: $e');
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _speech.stop();
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ultraLightPurple,
      body: Stack(
        children: [
          _buildGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildModernHeader(),
                Expanded(child: _buildRemindersList()),
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

  Widget _buildGradientBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ultraLightPurple, palePurple.withOpacity(0.3), Colors.white],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  Widget _buildModernHeader() {
    return FadeTransition(
      opacity: _fadeController,
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
        child: Row(
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
                    'My Reminders',
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
                    '${reminders.length} Active Reminders',
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
      ),
    );
  }

  Widget _buildRemindersList() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: vibrantPurple),
      );
    }

    if (reminders.isEmpty) {
      return _buildEmptyState();
    }

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
          .animate(
        CurvedAnimation(
          parent: _slideController,
          curve: Curves.easeOutCubic,
        ),
      ),
      child: RefreshIndicator(
        onRefresh: _loadReminders,
        color: vibrantPurple,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          itemCount: reminders.length,
          itemBuilder: (context, index) {
            final reminder = reminders[index];
            return _buildReminderCard(reminder, index);
          },
        ),
      ),
    );
  }

  Widget _buildReminderCard(ReminderItem reminder, int index) {
    final isToday = _isToday(reminder.date);

    return Semantics(
      label:
          'Reminder: ${reminder.title}. Date: ${reminder.date.day} ${_getMonthName(reminder.date.month)}, ${reminder.date.year}. Time: ${reminder.time}. Double tap to delete',
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
            onTap: () {
              _hapticFeedback();
              _speak('${reminder.title}. ${reminder.time}');
            },
            borderRadius: BorderRadius.circular(20),
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
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${reminder.date.day}',
                            style: TextStyle(
                              color: deepPurple,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            _getMonthName(reminder.date.month).toUpperCase(),
                            style: TextStyle(
                              color: deepPurple.withOpacity(0.6),
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                reminder.title,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: deepPurple,
                                ),
                              ),
                            ),
                            if (isToday)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [vibrantPurple, primaryPurple],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'TODAY',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: vibrantPurple.withOpacity(0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              reminder.time,
                              style: TextStyle(
                                fontSize: 13,
                                color: deepPurple.withOpacity(0.5),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.repeat,
                              size: 14,
                              color: vibrantPurple.withOpacity(0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              reminder.frequency,
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
                      _deleteReminder(index);
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
                Icons.notifications_off_outlined,
                size: 50,
                color: vibrantPurple,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No reminders added yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: deepPurple,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the button below to add your first reminder',
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
        return 'What\'s the reminder title?';
      case 1:
        return 'When to remind you?';
      case 2:
        return 'How often to repeat?';
      default:
        return 'Processing...';
    }
  }

  String _getVoiceStepHint() {
    switch (_voiceStep) {
      case 0:
        return 'Say the title of your reminder';
      case 1:
        return 'Say the date and time\nExample: "Tomorrow at 5 PM" or "Next Monday at 3 PM"';
      case 2:
        return 'Say "One time", "Daily", or "Weekly"';
      default:
        return '';
    }
  }

  Widget _buildVoiceAddButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 25),
      child: Semantics(
        label: 'Add new reminder with voice',
        button: true,
        hint: 'Double tap to add a new reminder using voice commands',
        child: GestureDetector(
          onTap: _startVoiceReminder,
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
                  'Add Voice Reminder',
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

  void _deleteReminder(int index) {
    final reminder = reminders[index];
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
                    const Text(
                      'Delete Reminder',
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: deepPurple,
                    ),
                    children: [
                      TextSpan(
                        text: '"${reminder.title}"',
                        style: const TextStyle(
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
                          await _deleteReminderFromFirestore(reminder.id);
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

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
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
                  isActive: true,
                  onTap: () {
                    _hapticFeedback();
                    _speak('Reminders');
                  },
                ),
                _buildNavButton(
                  icon: Icons.contact_phone,
                  label: 'Emergency',
                  onTap: () {
                    _hapticFeedback();
                    _speak('Emergency Contact');
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

class ReminderItem {
  final String id;
  final String title;
  final String time;
  final DateTime date;
  final String frequency;

  ReminderItem({
    required this.id,
    required this.title,
    required this.time,
    required this.date,
    this.frequency = 'One time',
  });
}
