import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:telephony/telephony.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'contact_info_page.dart';

class LocationSelectionPage extends StatefulWidget {
  const LocationSelectionPage({super.key});

  @override
  State<LocationSelectionPage> createState() => _LocationSelectionPageState();
}

class _LocationSelectionPageState extends State<LocationSelectionPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  
  // Telephony & TTS
  final Telephony _telephony = Telephony.instance;
  final FlutterTts _tts = FlutterTts();
  
  // Controllers
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();

  // Location variables
  GoogleMapController? _mapController;
  LatLng? _currentLatLng;
  final Set<Marker> _markers = <Marker>{};

  // State variables
  bool _isLocationLoaded = false;
  bool _isLoadingLocation = false;
  String _locationStatus = 'Tap to get location';
  bool _hasLocationPermission = false;
  double _currentAccuracy = 0.0;
  bool _isSendingLocation = false;

  // User data
  String _userName = 'User';
  bool _isLoadingUserData = true;
  List<Map<String, dynamic>> _contacts = [];
  StreamSubscription<DocumentSnapshot>? _userDataSubscription;

  // Firebase instances
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Map controller
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();

  // Animation controllers
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

  // Initial camera position - Riyadh
  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(24.7136, 46.6753),
    zoom: 14,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initTts();
    _initializeSMS();
    _initializeApp();

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
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
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

  @override
  void dispose() {
    _tts.stop();
    WidgetsBinding.instance.removeObserver(this);
    _userDataSubscription?.cancel();
    _cityController.dispose();
    _streetController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkInitialPermissions();
    }
  }

  void _initializeSMS() {
    try {
      debugPrint('Telephony SMS initialized successfully');
    } catch (e) {
      debugPrint('Error initializing telephony SMS: $e');
    }
  }

  Future<void> _initializeApp() async {
    try {
      await _loadUserData();
      await _loadUserContacts();
      await _checkInitialPermissions();
    } catch (e) {
      debugPrint('App initialization error: $e');
      if (mounted) {
        setState(() {
          _isLoadingUserData = false;
          _locationStatus = 'Initialization failed';
        });
      }
    }
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    try {
      final User? user = _auth.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _userName = 'Guest';
            _isLoadingUserData = false;
          });
        }
        return;
      }

      _userDataSubscription = _firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen(
        (DocumentSnapshot userDoc) {
          if (mounted) {
            if (userDoc.exists) {
              final Map<String, dynamic>? userData = userDoc.data() as Map<String, dynamic>?;
              setState(() {
                _userName = userData?['full_name'] as String? ??
                    userData?['displayName'] as String? ??
                    userData?['name'] as String? ??
                    user.displayName ??
                    user.email?.split('@')[0] ??
                    'User';
                _isLoadingUserData = false;
              });
            } else {
              _setUserNameFromAuth(user);
            }
          }
        },
        onError: (error) {
          debugPrint('Firestore user data listener error: $error');
          if (mounted) {
            final User? currentUser = _auth.currentUser;
            if (currentUser != null) {
              _setUserNameFromAuth(currentUser);
            }
          }
        },
      );
    } catch (e) {
      debugPrint('Load user data error: $e');
    }
  }

  void _setUserNameFromAuth(User user) {
    if (mounted) {
      setState(() {
        _userName = user.displayName ??
            user.email?.split('@')[0] ??
            'User';
        _isLoadingUserData = false;
      });
    }
  }

  Future<void> _loadUserContacts() async {
    if (!mounted) return;
    try {
      final User? user = _auth.currentUser;
      if (user == null) return;

      final QuerySnapshot contactsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('contacts')
          .get()
          .timeout(const Duration(seconds: 8));

      if (mounted) {
        setState(() {
          _contacts = contactsSnapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;
            return data;
          }).toList();
        });
        debugPrint('Loaded ${_contacts.length} contacts');
      }
    } catch (e) {
      debugPrint('Error loading contacts: $e');
    }
  }

  Future<bool> _sendLocationSMS() async {
    if (_currentLatLng == null || _contacts.isEmpty) {
      _speak(_contacts.isEmpty
          ? 'No contacts found'
          : 'No location available');
      _showSnackBar(
        _contacts.isEmpty
            ? 'No contacts found. Add contacts first.'
            : 'No location available to share',
        isError: true,
      );
      return false;
    }

    bool? permissionsGranted = await _telephony.requestPhoneAndSmsPermissions;
    if (permissionsGranted != true) {
      _speak('SMS permissions required');
      _showSnackBar('SMS permissions required to send emergency messages', isError: true);
      return false;
    }

    setState(() {
      _isSendingLocation = true;
    });

    try {
      final String locationText = '🚨 EMERGENCY: My current location: ${_cityController.text}, ${_streetController.text}';
      final String mapsUrl = 'https://maps.google.com/?q=${_currentLatLng!.latitude},${_currentLatLng!.longitude}';
      final String messageBody = '$locationText\n\n📍 View on map: $mapsUrl\n\nSent from Emergency Location Tracker - $_userName';

      int successCount = 0;
      int failCount = 0;

      for (var contact in _contacts) {
        try {
          final String phoneNumber = contact['phone'] ?? '';
          if (phoneNumber.isNotEmpty) {
            String cleanPhoneNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
            
            if (cleanPhoneNumber.startsWith('05')) {
              cleanPhoneNumber = '+966${cleanPhoneNumber.substring(1)}';
            } else if (cleanPhoneNumber.startsWith('5') && cleanPhoneNumber.length == 9) {
              cleanPhoneNumber = '+966$cleanPhoneNumber';
            }
            
            await _telephony.sendSms(
              to: cleanPhoneNumber,
              message: messageBody,
            );
            
            successCount++;
            await Future.delayed(const Duration(milliseconds: 1000));
          } else {
            failCount++;
          }
        } catch (e) {
          failCount++;
          debugPrint('Error sending SMS: $e');
        }
      }

      setState(() {
        _isSendingLocation = false;
      });

      if (successCount > 0) {
        _speak('Emergency location sent successfully');
        _showSnackBar(
          '✅ Emergency location sent to $successCount contact(s)${failCount > 0 ? ' ($failCount failed)' : ''}',
          isError: false,
        );
        return true;
      } else {
        _speak('Failed to send location');
        _showSnackBar('❌ Failed to send location to contacts', isError: true);
        return false;
      }
    } catch (e) {
      setState(() {
        _isSendingLocation = false;
      });
      _speak('Error sending location');
      _showSnackBar('Error sending location: ${e.toString()}', isError: true);
      return false;
    }
  }

  Future<void> _confirmAndSendLocation() async {
    if (_contacts.isEmpty) {
      _speak('No contacts found');
      _showSnackBar('No contacts found. Add contacts first.', isError: true);
      return;
    }

    _hapticFeedback();
    final bool? shouldSend = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
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
                  Icons.emergency_share,
                  size: 40,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Send Emergency SMS?',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: deepPurple,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This will send an emergency SMS with your location to all your contacts.',
                style: TextStyle(
                  fontSize: 14,
                  color: deepPurple.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ultraLightPurple,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palePurple),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: vibrantPurple),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${_cityController.text}, ${_streetController.text}',
                            style: TextStyle(
                              fontSize: 12,
                              color: deepPurple,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.contacts, size: 16, color: vibrantPurple),
                        const SizedBox(width: 4),
                        Text(
                          '${_contacts.length} Contact(s)',
                          style: TextStyle(
                            fontSize: 12,
                            color: deepPurple,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _hapticFeedback();
                        _speak('Cancelled');
                        Navigator.of(context).pop(false);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Colors.grey.shade300, width: 2),
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
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.red, Color.fromARGB(255, 200, 30, 30)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.4),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          _hapticFeedback();
                          Navigator.of(context).pop(true);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Send SMS',
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
      ),
    );

    if (shouldSend == true) {
      final bool smsSuccess = await _sendLocationSMS();
      if (mounted) {
        Navigator.of(context).pop(smsSuccess);
      }
    }
  }

  Future<void> _checkInitialPermissions() async {
    if (!mounted) return;
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final LocationPermission permission = await Geolocator.checkPermission();

      if (mounted) {
        setState(() {
          _hasLocationPermission = serviceEnabled &&
              (permission == LocationPermission.always ||
                  permission == LocationPermission.whileInUse);
          _locationStatus = _hasLocationPermission
              ? 'Tap "Get Location" to find your location'
              : 'Location permission needed';
        });
      }
    } catch (e) {
      debugPrint('Permission check error: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    if (_isLoadingLocation || !mounted) return;

    _hapticFeedback();
    _speak('Getting your location');

    try {
      setState(() {
        _isLoadingLocation = true;
        _locationStatus = 'Checking location services...';
      });

      final bool hasPermissions = await _checkAndRequestPermissions();
      if (!hasPermissions) return;

      setState(() {
        _locationStatus = 'Getting your current location...';
      });

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      ).timeout(const Duration(seconds: 35));

      if (mounted && _isValidLocation(position)) {
        await _updateLocationData(position);
      } else if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationStatus = 'Location accuracy too low, please try again';
        });
        _speak('Location accuracy too low');
      }
    } catch (e) {
      debugPrint('Error getting current location: $e');
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationStatus = 'Failed to get location';
        });
        _speak('Failed to get location');
      }
    }
  }

  bool _isValidLocation(Position position) {
    if (position.latitude.toStringAsFixed(4) == '37.4220' &&
        position.longitude.toStringAsFixed(4) == '-122.0841') {
      return false;
    }
    if (position.accuracy > 100) {
      return false;
    }
    if (position.latitude == 0.0 && position.longitude == 0.0) {
      return false;
    }
    return true;
  }

  Future<bool> _checkAndRequestPermissions() async {
    if (!mounted) return false;

    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationStatus = 'Location services are disabled';
        });
      }
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _isLoadingLocation = false;
            _locationStatus = 'Location permission denied';
          });
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationStatus = 'Location permission permanently denied';
        });
      }
      return false;
    }

    return true;
  }

  Future<void> _updateLocationData(Position position) async {
    if (!mounted) return;
    try {
      final LatLng latLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentLatLng = latLng;
        _isLocationLoaded = true;
        _isLoadingLocation = false;
        _currentAccuracy = position.accuracy;
        _locationStatus = 'Location found successfully';
        _markers.clear();
        _markers.add(
          Marker(
            markerId: const MarkerId('currentLocation'),
            position: latLng,
            infoWindow: InfoWindow(
              title: 'Current Location',
              snippet: 'Accuracy: ${position.accuracy.toStringAsFixed(0)}m',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          ),
        );
      });

      _speak('Location found');
      await _updateMapCamera(latLng);
      await _reverseGeocodeSafely(position);
      await _saveLocationToFirebase(latLng);
    } catch (e) {
      debugPrint('Error updating location data: $e');
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationStatus = 'Error processing location';
        });
      }
    }
  }

  Future<void> _updateMapCamera(LatLng position) async {
    try {
      if (_controller.isCompleted) {
        final GoogleMapController controller = await _controller.future;
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: position, zoom: 16),
          ),
        );
      }
    } catch (e) {
      debugPrint('Map camera update error: $e');
    }
  }

  Future<void> _reverseGeocodeSafely(Position position) async {
    if (!mounted) return;
    try {
      final List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 10));

      if (mounted && placemarks.isNotEmpty) {
        final Placemark place = placemarks.first;
        final String city = place.locality ??
            place.subAdministrativeArea ??
            place.administrativeArea ??
            'Riyadh';
        final String street = place.street ??
            place.thoroughfare ??
            place.subThoroughfare ??
            place.name ??
            'Near $city';

        setState(() {
          _cityController.text = city;
          _streetController.text = street;
        });
      }
    } catch (e) {
      debugPrint('Reverse geocoding error: $e');
      if (mounted) {
        setState(() {
          _cityController.text = 'Riyadh';
          _streetController.text = 'Current Location';
        });
      }
    }
  }

  Future<void> _saveLocationToFirebase(LatLng latLng) async {
    try {
      final User? user = _auth.currentUser;
      if (user == null) return;

      final Map<String, dynamic> locationData = <String, dynamic>{
        'userId': user.uid,
        'userEmail': user.email,
        'userName': _userName,
        'latitude': latLng.latitude,
        'longitude': latLng.longitude,
        'accuracy': _currentAccuracy,
        'city': _cityController.text.isNotEmpty ? _cityController.text : 'Riyadh',
        'street': _streetController.text.isNotEmpty ? _streetController.text : 'Current Location',
        'timestamp': FieldValue.serverTimestamp(),
        'devicePlatform': Platform.isAndroid ? 'Android' : Platform.isIOS ? 'iOS' : 'Unknown',
        'locationType': 'emergency',
      };

      final WriteBatch batch = _firestore.batch();
      final DocumentReference currentLocationRef = _firestore
          .collection('userLocations')
          .doc(user.uid);
      final DocumentReference historyRef = _firestore
          .collection('userLocations')
          .doc(user.uid)
          .collection('history')
          .doc();

      batch.set(currentLocationRef, {
        'currentLocation': locationData,
        'lastUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(historyRef, locationData);
      await batch.commit().timeout(const Duration(seconds: 10));
      debugPrint('Location saved to Firebase');
    } catch (e) {
      debugPrint('Firebase save error: $e');
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: isError ? 4 : 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
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
                Expanded(
                  child: _buildContent(),
                ),
              ],
            ),
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
          colors: [
            ultraLightPurple,
            palePurple.withOpacity(0.3),
            Colors.white,
          ],
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
              label: 'Back',
              button: true,
              child: GestureDetector(
                onTap: () {
                  _hapticFeedback();
                  _speak('Back');
                  Navigator.pop(context, false);
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
                    'Emergency Location',
                    style: TextStyle(
                      fontSize: 12,
                      color: deepPurple.withOpacity(0.5),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _isLoadingUserData
                      ? Container(
                          width: 100,
                          height: 24,
                          decoration: BoxDecoration(
                            color: palePurple.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )
                      : Text(
                          _userName,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            foreground: Paint()
                              ..shader = LinearGradient(
                                colors: [deepPurple, vibrantPurple],
                              ).createShader(Rect.fromLTWH(0, 0, 200, 70)),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.15),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeOutCubic,
      )),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Column(
          children: [
            // Map Card
            _buildMapCard(),
            
            const SizedBox(height: 16),
            
            // Get Location Button
            _buildGetLocationButton(),
            
            const SizedBox(height: 16),
            
            // Location Status Card
            _buildLocationStatusCard(),
            
            const SizedBox(height: 16),
            
            // City Field
            _buildTextField(
              controller: _cityController,
              label: 'City',
              icon: Icons.location_city,
            ),
            
            const SizedBox(height: 12),
            
            // Street Field
            _buildTextField(
              controller: _streetController,
              label: 'Street',
              icon: Icons.signpost,
            ),
            
            const SizedBox(height: 20),
            
            // Contacts Info Card
            _buildContactsInfoCard(),
            
            const SizedBox(height: 16),
            
            // Send Emergency Button
            _buildSendEmergencyButton(),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMapCard() {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: palePurple.withOpacity(0.35),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: _initialCameraPosition,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              markers: _markers,
              onMapCreated: (GoogleMapController controller) {
                if (!_controller.isCompleted) {
                  _controller.complete(controller);
                  _mapController = controller;
                }
              },
              buildingsEnabled: true,
              zoomControlsEnabled: false,
              mapType: MapType.normal,
              liteModeEnabled: false,
            ),
            if (_isLoadingLocation)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      deepPurple.withOpacity(0.8),
                      vibrantPurple.withOpacity(0.8),
                    ],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: 1.0 + (_pulseController.value * 0.3),
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.location_searching,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Getting your location...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGetLocationButton() {
    return Semantics(
      label: 'Get current location',
      button: true,
      child: GestureDetector(
        onTap: _isLoadingLocation ? null : _getCurrentLocation,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isLoadingLocation
                  ? [Colors.grey.shade400, Colors.grey.shade500]
                  : [vibrantPurple, primaryPurple],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: _isLoadingLocation
                ? []
                : [
                    BoxShadow(
                      color: vibrantPurple.withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoadingLocation)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              else
                const Icon(
                  Icons.my_location,
                  color: Colors.white,
                  size: 22,
                ),
              const SizedBox(width: 12),
              Text(
                _isLoadingLocation ? 'Getting Location...' : 'Get Current Location',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isLocationLoaded ? vibrantPurple : palePurple,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (_isLocationLoaded ? vibrantPurple : palePurple).withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isLocationLoaded
                    ? [vibrantPurple.withOpacity(0.2), primaryPurple.withOpacity(0.2)]
                    : [palePurple.withOpacity(0.2), lightPurple.withOpacity(0.2)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isLocationLoaded ? Icons.location_on : Icons.location_off,
              color: _isLocationLoaded ? vibrantPurple : Colors.grey,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isLocationLoaded ? 'Location Found' : _locationStatus,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: deepPurple,
                  ),
                ),
                if (_isLocationLoaded && _currentAccuracy > 0)
                  Text(
                    'Accuracy: ${_currentAccuracy.toStringAsFixed(0)}m',
                    style: TextStyle(
                      fontSize: 12,
                      color: deepPurple.withOpacity(0.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palePurple, width: 2),
        boxShadow: [
          BoxShadow(
            color: palePurple.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        style: TextStyle(
          fontSize: 14,
          color: deepPurple,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: deepPurple.withOpacity(0.6),
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: Icon(icon, color: vibrantPurple),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildContactsInfoCard() {
    final bool hasContacts = _contacts.isNotEmpty;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasContacts
              ? [vibrantPurple.withOpacity(0.1), primaryPurple.withOpacity(0.1)]
              : [Colors.orange.shade50, Colors.orange.shade100.withOpacity(0.3)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasContacts ? vibrantPurple : Colors.orange,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: hasContacts ? vibrantPurple : Colors.orange,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              hasContacts ? Icons.contacts : Icons.contact_phone,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hasContacts
                  ? 'Ready to send to ${_contacts.length} contact(s)'
                  : 'Add contacts to send emergency SMS',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: hasContacts ? vibrantPurple : Colors.orange.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendEmergencyButton() {
    final bool canSend = _isLocationLoaded && !_isLoadingLocation && !_isSendingLocation;
    final bool hasContacts = _contacts.isNotEmpty;
    
    return Semantics(
      label: hasContacts
          ? (canSend ? 'Send emergency SMS' : 'Get location first')
          : 'Add emergency contacts',
      button: true,
      child: GestureDetector(
        onTap: canSend
            ? () async {
                if (!hasContacts) {
                  _hapticFeedback();
                  _speak('Add contacts first');
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ContactInfoPage()),
                  );
                  await _loadUserContacts();
                  return;
                }

                if (_currentLatLng != null) {
                  await _saveLocationToFirebase(_currentLatLng!);
                }
                await _confirmAndSendLocation();
              }
            : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: canSend
                  ? (hasContacts
                      ? [Colors.red.shade600, Colors.red.shade800]
                      : [vibrantPurple, primaryPurple])
                  : [Colors.grey.shade300, Colors.grey.shade400],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: canSend
                ? [
                    BoxShadow(
                      color: (hasContacts ? Colors.red : vibrantPurple).withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : [],
          ),
          child: _isSendingLocation
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Sending Emergency SMS...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isLoadingLocation
                          ? Icons.hourglass_empty
                          : canSend
                              ? (hasContacts ? Icons.emergency_share : Icons.person_add)
                              : Icons.location_searching,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isLoadingLocation
                          ? 'Loading...'
                          : canSend
                              ? (hasContacts ? 'Send Emergency SMS' : 'Add Emergency Contacts')
                              : 'Get Location First',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}