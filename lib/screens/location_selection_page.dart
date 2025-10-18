import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final Telephony _telephony = Telephony.instance;
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();

  LatLng? _currentLatLng;
  final Set<Marker> _markers = <Marker>{};

  bool _isLocationLoaded = false;
  bool _isLoadingLocation = false;
  double _currentAccuracy = 0.0;
  bool _isSendingLocation = false;

  List<Map<String, dynamic>> _contacts = [];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;

  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);

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
      await _loadUserContacts();
      await _checkInitialPermissions();
    } catch (e) {
      debugPrint('App initialization error: $e');
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
      _speak(_contacts.isEmpty ? 'No contacts found' : 'No location available');
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
      _showSnackBar(
        'SMS permissions required to send emergency messages',
        isError: true,
      );
      return false;
    }

    setState(() {
      _isSendingLocation = true;
    });

    try {
      final User? user = _auth.currentUser;
      final String userName =
          user?.displayName ?? user?.email?.split('@')[0] ?? 'User';

      final String locationText =
          'EMERGENCY: My current location: ${_cityController.text}, ${_streetController.text}';
      final String mapsUrl =
          'https://maps.google.com/?q=${_currentLatLng!.latitude},${_currentLatLng!.longitude}';
      final String messageBody =
          '$locationText\n\n View on map: $mapsUrl\n\nSent from Emergency Location Tracker - $userName';

      int successCount = 0;
      int failCount = 0;

      for (var contact in _contacts) {
        try {
          final String phoneNumber = contact['phone'] ?? '';
          if (phoneNumber.isNotEmpty) {
            String cleanPhoneNumber = phoneNumber.replaceAll(
              RegExp(r'[^\d+]'),
              '',
            );

            if (cleanPhoneNumber.startsWith('05')) {
              cleanPhoneNumber = '+966${cleanPhoneNumber.substring(1)}';
            } else if (cleanPhoneNumber.startsWith('5') &&
                cleanPhoneNumber.length == 9) {
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

      if (mounted) {
        setState(() {
          _isSendingLocation = false;
        });
      }

      if (successCount > 0) {
        _speak('Emergency location sent successfully');
        _showSnackBar(
          'Emergency location sent to $successCount contact(s)${failCount > 0 ? ' ($failCount failed)' : ''}',
          isError: false,
        );
        return true;
      } else {
        _speak('Failed to send location');
        _showSnackBar('Failed to send location to contacts', isError: true);
        return false;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSendingLocation = false;
        });
      }
      _speak('Error sending location');
      _showSnackBar('Error sending location: ${e.toString()}', isError: true);
      return false;
    }
  }

  Future<void> _checkInitialPermissions() async {
    if (!mounted) return;
    try {
      await Geolocator.isLocationServiceEnabled();
      await Geolocator.checkPermission();
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
      });

      final bool hasPermissions = await _checkAndRequestPermissions();
      if (!hasPermissions) return;

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      ).timeout(const Duration(seconds: 35));

      if (mounted && _isValidLocation(position)) {
        await _updateLocationData(position);
      } else if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
        _speak('Location accuracy too low');
        _showSnackBar(
          'Location accuracy too low, please try again',
          isError: true,
        );
      }
    } catch (e) {
      debugPrint('Error getting current location: $e');
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
        _speak('Failed to get location');
        _showSnackBar('Failed to get location', isError: true);
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
        });
        _showSnackBar('Location services are disabled', isError: true);
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
          });
          _showSnackBar('Location permission denied', isError: true);
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
        _showSnackBar('Location permission permanently denied', isError: true);
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
        _markers.clear();
        _markers.add(
          Marker(
            markerId: const MarkerId('currentLocation'),
            position: latLng,
            infoWindow: InfoWindow(
              title: 'Current Location',
              snippet: 'Accuracy: ${position.accuracy.toStringAsFixed(0)}m',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueViolet,
            ),
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
        });
        _showSnackBar('Error processing location', isError: true);
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
        final String city =
            place.locality ??
            place.subAdministrativeArea ??
            place.administrativeArea ??
            'Riyadh';
        final String street =
            place.street ??
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
        'latitude': latLng.latitude,
        'longitude': latLng.longitude,
        'accuracy': _currentAccuracy,
        'city': _cityController.text.isNotEmpty
            ? _cityController.text
            : 'Riyadh',
        'street': _streetController.text.isNotEmpty
            ? _streetController.text
            : 'Current Location',
        'timestamp': FieldValue.serverTimestamp(),
        'devicePlatform': Platform.isAndroid
            ? 'Android'
            : Platform.isIOS
            ? 'iOS'
            : 'Unknown',
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
                Expanded(child: _buildContent()),
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
        padding: const EdgeInsets.fromLTRB(20, 45, 30, 45),
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
                  _hapticFeedback();
                  _speak('Going back');
                  Navigator.pop(context, false);
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    'Automatic or Manual',
                    style: TextStyle(
                      
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      foreground: Paint()
                        ..shader = LinearGradient(
                          colors: [deepPurple, vibrantPurple],
                        ).createShader(Rect.fromLTWH(0, 0, 200, 70)),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Detect automatically or enter manually',
                    style: TextStyle(
                      fontSize: 12,
                      color: deepPurple.withOpacity(0.6),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
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

  Widget _buildContent() {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _slideController,
              curve: Curves.easeOutCubic,
            ),
          ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Column(
          children: [
            _buildMapCard(),
            const SizedBox(height: 16),
            _buildGetLocationButton(),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _cityController,
              label: 'City',
              icon: Icons.location_city,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _streetController,
              label: 'Street',
              icon: Icons.signpost,
            ),
            const SizedBox(height: 20),
            _buildContactsInfoCard(),
            const SizedBox(height: 16),
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
          padding: const EdgeInsets.symmetric(vertical: 20),
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
                const Icon(Icons.my_location, color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Text(
                _isLoadingLocation
                    ? 'Getting Location...'
                    : 'Get Current Location',
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
              ? [vibrantPurple.withOpacity(0.1), primaryPurple.withOpacity(0.3)]
              : [Colors.red.shade50, Colors.red.shade100.withOpacity(0.5)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasContacts
              ? vibrantPurple
              : const Color.fromARGB(255, 255, 17, 0),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: hasContacts
                  ? vibrantPurple
                  : const Color.fromARGB(255, 255, 18, 1),
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
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: hasContacts ? vibrantPurple : Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendEmergencyButton() {
    final bool canSend =
        _isLocationLoaded && !_isLoadingLocation && !_isSendingLocation;
    final bool hasContacts = _contacts.isNotEmpty;

    return Semantics(
      label: hasContacts
          ? (canSend ? 'Send emergency SMS' : 'Get location first')
          : 'Add emergency contacts',
      button: true,
      child: GestureDetector(
        onTap: canSend
            ? () async {
                // لا يوجد تأكيد قبل الإرسال
                if (!hasContacts) {
                  _hapticFeedback();
                  _speak('Add contacts first');
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ContactInfoPage()),
                  );
                  await _loadUserContacts();
                  return;
                }

                if (_currentLatLng != null) {
                  await _saveLocationToFirebase(_currentLatLng!);
                }

                _hapticFeedback();
                final bool smsSuccess = await _sendLocationSMS();

                // تأكيد الإرسال + الرجوع للصفحة السابقة إذا نجح
                if (smsSuccess && mounted) {
                  await Future.delayed(const Duration(milliseconds: 300));
                  Navigator.pop(context, true);
                }
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
                      color: (hasContacts ? Colors.red : vibrantPurple)
                          .withOpacity(0.4),
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
                          ? (hasContacts
                                ? Icons.emergency_share
                                : Icons.person_add)
                          : Icons.location_searching,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isLoadingLocation
                          ? 'Loading...'
                          : canSend
                          ? (hasContacts
                                ? 'Send Emergency SMS'
                                : 'Add Emergency Contacts')
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
