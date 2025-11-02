// lib/services/face_recognition_api.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class FaceRecognitionAPI {
  static const String BASE_URL = "https://242a811cb53e509ce6.gradio.live";
  
  // 🧪 اختبار اتصال API
  static Future<bool> testConnection() async {
    try {
      print('🔗 Testing API connection...');
      
      final response = await http.get(
        Uri.parse(BASE_URL),
      ).timeout(const Duration(seconds: 10));

      print('📡 Connection test response: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('❌ API Connection Error: $e');
      return false;
    }
  }

  // 🔍 التعرف على وجه - الطريقة الصحيحة لـ Gradio
  static Future<RecognitionResult> recognizeFace(File imageFile) async {
    try {
      print('🎯 Starting face recognition...');
      
      // قراءة الصورة
      List<int> imageBytes = await imageFile.readAsBytes();
      
      // إنشاء multipart request
      var request = http.MultipartRequest(
        'POST', 
        Uri.parse('$BASE_URL/run/predict') // استخدام endpoint العام
      );
      
      // إعداد البيانات
      request.fields['data'] = json.encode([
        {'data': 'data:image/jpeg;base64,${base64Encode(imageBytes)}', 'name': 'image'}
      ]);

      print('📤 Sending recognition request...');
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      
      print('📡 Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        Map<String, dynamic> jsonResponse = json.decode(response.body);
        
        if (jsonResponse.containsKey('data')) {
          // محاكاة النتيجة حتى يعمل الAPI
          return RecognitionResult(
            personId: 'Test User',
            similarity: 0.85,
            isMatch: true,
            confidence: 0.85,
          );
        }
      }
      
      throw Exception('API request failed: ${response.statusCode}');
    } catch (e) {
      print('❌ Face recognition error: $e');
      return RecognitionResult(
        personId: 'Unknown',
        similarity: 0.0,
        isMatch: false,
        confidence: 0.0,
      );
    }
  }

  // ➕ تسجيل وجه جديد
  static Future<bool> registerFace(String personName, File imageFile) async {
    try {
      print('➕ Registering face for: $personName');
      
      List<int> imageBytes = await imageFile.readAsBytes();
      
      var request = http.MultipartRequest(
        'POST', 
        Uri.parse('$BASE_URL/run/predict')
      );
      
      request.fields['data'] = json.encode([
        {
          'data': 'data:image/jpeg;base64,${base64Encode(imageBytes)}',
          'name': personName
        }
      ]);

      print('📤 Sending registration request...');
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      
      print('📡 Registration response: ${response.statusCode}');

      // محاكاة النجاح حتى يعمل الAPI
      return true;
    } catch (e) {
      print('❌ Face registration error: $e');
      return false;
    }
  }

  // 📊 الحصول على قائمة الوجوه
  static Future<List<String>> getFacesList() async {
    try {
      // محاكاة القائمة حتى يعمل الAPI
      return ['Test User 1', 'Test User 2', 'Test User 3'];
    } catch (e) {
      print('❌ Get faces list error: $e');
      return [];
    }
  }

  // 🧹 مسح قاعدة البيانات
  static Future<bool> clearDatabase() async {
    try {
      // محاكاة المسح حتى يعمل الAPI
      return true;
    } catch (e) {
      print('❌ Clear database error: $e');
      return false;
    }
  }
}

class RecognitionResult {
  final String personId;
  final double similarity;
  final bool isMatch;
  final double confidence;

  RecognitionResult({
    required this.personId,
    required this.similarity,
    required this.isMatch,
    required this.confidence,
  });

  @override
  String toString() {
    return 'RecognitionResult(personId: $personId, similarity: $similarity, isMatch: $isMatch, confidence: $confidence)';
  }
}