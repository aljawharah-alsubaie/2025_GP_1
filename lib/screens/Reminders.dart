import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import './settings.dart';
import './home_page.dart';
import './sos_screen.dart';
import './location_permission_screen.dart';

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
  String _voiceNote = '';
  String _voiceFrequency = 'One time';
  bool _isVoiceMode = false;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  String _selectedFrequency = 'One time';
  String? _editingReminderId;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;

  // 🎨 نظام ألوان موحد
  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color softPurple = Color(0xFFB665BA);
  static const Color lightPurple = Color.fromARGB(255, 217, 163, 227);
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
    // ✅ نضيف completion handler للتأكد من انتهاء الكلام
    _tts.setCompletionHandler(() {
      print('TTS completed');
    });
  }

  Future<void> _initSpeech() async {
    _speech = stt.SpeechToText();
    bool available = await _speech.initialize(
      onError: (error) {
        print('Speech error: $error');
        _speak(
          'Speech recognition error. Please check your microphone permissions',
        );
      },
      onStatus: (status) => print('Speech status: $status'),
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
              note: data['note'] ?? '',
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
    // Check if speech recognition is available
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
      _voiceNote = '';
      _voiceFrequency = 'One time';
    });

    _hapticFeedback();
    await _speak(
      'Starting voice reminder. Please tell me the title of your reminder',
    );
    await Future.delayed(const Duration(milliseconds: 2500));
    await _speak(
      'Starting voice reminder. Please tell me the title of your reminder',
    );
    // ✅ ننتظر 1 ثانية إضافية بعد انتهاء TTS
    await Future.delayed(const Duration(milliseconds: 3500));
    _listenForVoiceInput();
  }

  Future<void> _listenForVoiceInput() async {
    if (!_speech.isAvailable) {
      _speak('Speech recognition is not available');
      return;
    }

    setState(() => _isListening = true);

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _processVoiceInput(result.recognizedWords);
        }
      },
      listenFor: const Duration(
        seconds: 15,
      ), // ✅ زودنا المدة من 10 إلى 15 ثانية
      pauseFor: const Duration(seconds: 5), // ✅ زودنا المدة من 3 إلى 5 ثواني
      localeId: 'en_US',
      cancelOnError: true,
      partialResults: false,
    );
  }

  Future<void> _processVoiceInput(String input) async {
    setState(() => _isListening = false);

    if (input.isEmpty) {
      await _speak('I did not hear anything. Please try again');
      await Future.delayed(const Duration(milliseconds: 2500)); // ✅ زودنا الوقت
      _listenForVoiceInput();
      return;
    }

    switch (_voiceStep) {
      case 0: // Title
        _voiceTitle = input;
        await _speak(
          'Got it. Title is: $input. Now, when would you like to be reminded? Say the date and time',
        );
        setState(() => _voiceStep = 1);
        await Future.delayed(
          const Duration(milliseconds: 4000),
        ); // ✅ زودنا الوقت من 3000 إلى 4000
        _listenForVoiceInput();
        break;

      case 1: // Date & Time
        final dateTime = _parseDateTimeFromVoice(input);
        if (dateTime != null) {
          _voiceDate = '${dateTime.day}/${dateTime.month}/${dateTime.year}';
          _voiceTime = _formatTime(dateTime);
          await _speak(
            'Perfect. Reminder set for ${_formatDateForSpeech(dateTime)} at ${_voiceTime}. Would you like to add a note? Say yes or no',
          );
          setState(() => _voiceStep = 2);
          await Future.delayed(
            const Duration(milliseconds: 4000),
          ); // ✅ زودنا الوقت من 3000 إلى 4000
          _listenForVoiceInput();
        } else {
          await _speak(
            'Sorry, I could not understand the date and time. Please try again. For example, say: tomorrow at 5 PM, or next Monday at 3 PM',
          );
          await Future.delayed(const Duration(milliseconds: 3500));
          await _speak(
            'Sorry, I could not understand the date and time. Please try again. For example, say: tomorrow at 5 PM, or next Monday at 3 PM',
          );
          await Future.delayed(
            const Duration(milliseconds: 4500),
          ); // ✅ زودنا الوقت من 3500 إلى 4500
          _listenForVoiceInput();
        }
        break;

      case 2: // Ask for note
        if (input.toLowerCase().contains('yes')) {
          await _speak('What would you like to add as a note?');
          setState(() => _voiceStep = 3);
          await Future.delayed(
            const Duration(milliseconds: 2500),
          ); // ✅ زودنا الوقت من 2000 إلى 2500
          _listenForVoiceInput();
        } else {
          await _speak(
            'Would you like this reminder to repeat? Say one time, daily, or weekly',
          );
          setState(() => _voiceStep = 4);
          await Future.delayed(
            const Duration(milliseconds: 3500),
          ); // ✅ زودنا الوقت من 2500 إلى 3500
          _listenForVoiceInput();
        }
        break;

      case 3: // Note input
        _voiceNote = input;
        await _speak(
          'Note added. Would you like this reminder to repeat? Say one time, daily, or weekly',
        );
        setState(() => _voiceStep = 4);
        await Future.delayed(
          const Duration(milliseconds: 3500),
        ); // ✅ زودنا الوقت من 2500 إلى 3500
        _listenForVoiceInput();
        break;

      case 4: // Frequency
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

        await _speak(
          'Understood. Frequency is ${_voiceFrequency}. Creating your reminder now',
        );
        await Future.delayed(
          const Duration(milliseconds: 2500),
        ); // ✅ زودنا الوقت من 2000 إلى 2500
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
      date = now; // Default to today
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
        hour += 12; // Assume PM for hours less than 8
      }

      time = TimeOfDay(hour: hour, minute: 0);
    }

    if (date != null && time != null) {
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
        'note': _voiceNote,
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
            note: _voiceNote,
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
      floatingActionButton: _buildVoiceAddButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: _buildFloatingBottomNav(),
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                  _speak('Back');
                  Navigator.pop(context);
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: vibrantPurple.withOpacity(0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: deepPurple,
                    size: 24,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Reminders',
                    style: TextStyle(
                      fontSize: 12,
                      color: deepPurple.withOpacity(0.5),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${reminders.length} Active',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      foreground: Paint()
                        ..shader = LinearGradient(
                          colors: [deepPurple, vibrantPurple],
                        ).createShader(Rect.fromLTWH(0, 0, 200, 70)),
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
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
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
          'Reminder: ${reminder.title}. Date: ${reminder.date.day} ${_getMonthName(reminder.date.month)}, ${reminder.date.year}. Time: ${reminder.time}. ${reminder.note.isNotEmpty ? "Note: ${reminder.note}." : ""} Double tap to see options',
      button: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              _hapticFeedback();
              _speak('${reminder.title}. ${reminder.time}');
              _showReminderOptions(reminder, index);
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: isToday
                    ? Border.all(color: vibrantPurple, width: 2)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: isToday
                        ? vibrantPurple.withOpacity(0.4)
                        : palePurple.withOpacity(0.35),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(0.8),
                    blurRadius: 12,
                    offset: const Offset(-2, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isToday
                            ? [vibrantPurple, primaryPurple]
                            : [deepPurple, vibrantPurple],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: vibrantPurple.withOpacity(0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${reminder.date.day}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          _getMonthName(reminder.date.month).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                reminder.title,
                                style: TextStyle(
                                  fontSize: 15,
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
                                  gradient: LinearGradient(
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
                              color: deepPurple.withOpacity(0.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              reminder.time,
                              style: TextStyle(
                                fontSize: 12,
                                color: deepPurple.withOpacity(0.5),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.repeat,
                              size: 14,
                              color: deepPurple.withOpacity(0.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              reminder.frequency,
                              style: TextStyle(
                                fontSize: 12,
                                color: deepPurple.withOpacity(0.5),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        if (reminder.note.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            reminder.note,
                            style: TextStyle(
                              fontSize: 11,
                              color: deepPurple.withOpacity(0.4),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          vibrantPurple.withOpacity(0.1),
                          primaryPurple.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.more_vert,
                      size: 20,
                      color: vibrantPurple,
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

  void _showReminderOptions(ReminderItem reminder, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildOptionButton(
                        icon: Icons.delete,
                        label: 'Delete Reminder',
                        color: Colors.red,
                        onTap: () {
                          Navigator.pop(context);
                          _deleteReminder(index);
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final buttonColor = color ?? vibrantPurple;

    return Semantics(
      label: '$label button',
      button: true,
      child: GestureDetector(
        onTap: () {
          _hapticFeedback();
          _speak(label);
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: buttonColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: buttonColor.withOpacity(0.3), width: 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: buttonColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: buttonColor,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: buttonColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  deepPurple.withOpacity(0.1),
                  vibrantPurple.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(60),
            ),
            child: Icon(
              Icons.notifications_off_outlined,
              size: 60,
              color: deepPurple.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No reminders yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: deepPurple,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Tap the microphone button and say "Add new reminder"',
              style: TextStyle(
                fontSize: 14,
                color: deepPurple.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // 🎤 Voice Overlay UI
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
              // Animated microphone
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 + (_pulseController.value * 0.2),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
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
                style: TextStyle(
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

              // Cancel button
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
                    side: BorderSide(color: vibrantPurple, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
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
        return 'Add a note?';
      case 3:
        return 'What\'s the note?';
      case 4:
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
        return 'Say "Yes" to add a note, or "No" to skip';
      case 3:
        return 'Speak your note';
      case 4:
        return 'Say "One time", "Daily", or "Weekly"';
      default:
        return '';
    }
  }

  Widget _buildVoiceAddButton() {
    return Semantics(
      label: 'Add new reminder with voice. Press and hold to speak',
      button: true,
      hint: 'Double tap to add a new reminder using voice commands',
      child: GestureDetector(
        onTap: () {
          _startVoiceReminder();
        },
        child: Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [vibrantPurple, primaryPurple]),
            borderRadius: BorderRadius.circular(35),
            boxShadow: [
              BoxShadow(
                color: vibrantPurple.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(Icons.mic, color: Colors.white, size: 36),
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
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    size: 40,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Delete Reminder?',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: deepPurple,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Are you sure you want to delete "${reminder.title}"?',
                  style: TextStyle(
                    fontSize: 14,
                    color: deepPurple.withOpacity(0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: 'Cancel deletion',
                        button: true,
                        child: OutlinedButton(
                          onPressed: () {
                            _hapticFeedback();
                            _speak('Cancelled');
                            Navigator.pop(context);
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(
                              color: Colors.grey.shade300,
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Semantics(
                        label: 'Confirm delete reminder',
                        button: true,
                        child: ElevatedButton(
                          onPressed: () async {
                            _hapticFeedback();
                            Navigator.pop(context);
                            await _deleteReminderFromFirestore(reminder.id);
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Delete',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
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
                  icon: Icons.emergency,
                  label: 'Emergency',
                  onTap: () async {
                    _hapticFeedback();
                    _speak('Emergency');
                    final user = _auth.currentUser;
                    if (user != null) {
                      final doc = await _firestore
                          .collection('users')
                          .doc(user.uid)
                          .get();
                      final data = doc.data();
                      final permissionGranted =
                          data?['location_permission_granted'] ?? false;
                      if (!permissionGranted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LocationPermissionScreen(
                              onPermissionGranted: () async {
                                await _firestore
                                    .collection('users')
                                    .doc(user.uid)
                                    .update({
                                      'location_permission_granted': true,
                                    });
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SosScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SosScreen(),
                          ),
                        );
                      }
                    }
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
                  fontSize: 11,
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
  final String note;
  final String frequency;

  ReminderItem({
    required this.id,
    required this.title,
    required this.time,
    required this.date,
    this.note = '',
    this.frequency = 'One time',
  });
}
