// lib/services/face_recognition_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class FaceRecognitionAPI {
  static const String BASE_URL = "https://242a811cb53e509ce6.gradio.live";
  
  // 🧪 اختبار اتصال API
  static Future<bool> testConnection() async {
    try {
      print('🔗 Testing connection to: $BASE_URL');
      
      final response = await http.get(
        Uri.parse(BASE_URL),
      ).timeout(const Duration(seconds: 10));

      print('📡 Response status: ${response.statusCode}');
      
      // إذا كان الرد 200 فهذا يعني الاتصال ناجح
      return response.statusCode == 200;
    } catch (e) {
      print('❌ API Test Connection Error: $e');
      return false;
    }
  }

  // 🔍 التعرف على وجه من الصورة - متوافق مع Gradio
  static Future<RecognitionResult> recognizeFace(List<int> imageBytes) async {
    try {
      print('🎯 Sending face recognition request...');
      
      // تحويل الصورة إلى base64
      String base64Image = base64Encode(imageBytes);
      
      // إعداد البيانات حسب توقعات Gradio
      final requestData = {
        'data': [
          'data:image/jpeg;base64,$base64Image'
        ]
      };

      print('📤 Sending request to /api/predict...');
      
      final response = await http.post(
        Uri.parse('$BASE_URL/api/predict'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestData),
      ).timeout(const Duration(seconds: 15));

      print('📡 Response status: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        
        // معالجة رد Gradio
        if (result['data'] != null && result['data'].isNotEmpty) {
          String recognitionResult = result['data'][0];
          print('✅ Recognition result: $recognitionResult');
          
          // تحليل النتيجة النصية
          return _parseRecognitionResult(recognitionResult);
        } else {
          throw Exception('No data in response');
        }
      } else {
        throw Exception('API Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ API Recognition Error: $e');
      // إرجاع نتيجة افتراضية
      return RecognitionResult(
        personId: 'Unknown',
        similarity: 0.0,
        isMatch: false,
        confidence: 0.0,
      );
    }
  }

  // ➕ إضافة وجه جديد - متوافق مع Gradio
  static Future<bool> addFace(String personName, List<int> imageBytes) async {
    try {
      print('➕ Adding face for: $personName');
      
      // تحويل الصورة إلى base64
      String base64Image = base64Encode(imageBytes);
      
      // إعداد البيانات حسب توقعات Gradio
      final requestData = {
        'data': [
          'data:image/jpeg;base64,$base64Image',
          personName
        ]
      };

      print('📤 Sending request to /api/register_face...');
      
      final response = await http.post(
        Uri.parse('$BASE_URL/api/register_face'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestData),
      ).timeout(const Duration(seconds: 15));

      print('📡 Response status: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        
        // التحقق من النتيجة
        if (result['data'] != null && result['data'].isNotEmpty) {
          String responseText = result['data'][0];
          bool success = responseText.contains('✅') || responseText.contains('تم تسجيل');
          print('✅ Add face result: $responseText - Success: $success');
          return success;
        }
      }
      
      return false;
    } catch (e) {
      print('❌ API Add Face Error: $e');
      return false;
    }
  }

  // 🗑️ حذف وجه - قد لا يكون مدعوماً في الـ API الحالي
  static Future<bool> deleteFace(String personName) async {
    try {
      print('🗑️ Delete face not supported in current API');
      // الـ API الحالي لا يدعم الحذف الفردي، فقط مسح الكل
      return false;
    } catch (e) {
      print('❌ API Delete Face Error: $e');
      return false;
    }
  }

  // 📋 الحصول على قائمة الوجوه - متوافق مع Gradio
  static Future<List<String>> getFacesList() async {
    try {
      print('📋 Getting faces list...');
      
      // محاولة الحصول على الإحصائيات التي تحتوي على قائمة الوجوه
      final requestData = {
        'data': []
      };

      final response = await http.post(
        Uri.parse('$BASE_URL/api/get_statistics'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestData),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        
        if (result['data'] != null && result['data'].isNotEmpty) {
          String statsText = result['data'][0];
          print('📊 Statistics: $statsText');
          
          // استخراج الأسماء من النص (هذا تقديري - قد تحتاج تعديل)
          return _extractNamesFromStats(statsText);
        }
      }

      return [];
    } catch (e) {
      print('❌ API Get Faces Error: $e');
      return [];
    }
  }

  // 🧹 مسح كل قاعدة البيانات
  static Future<bool> clearDatabase() async {
    try {
      final requestData = {
        'data': []
      };

      final response = await http.post(
        Uri.parse('$BASE_URL/api/clear_database'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestData),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        return result['data'] != null && result['data'].isNotEmpty && 
               result['data'][0].contains('✅');
      }
      
      return false;
    } catch (e) {
      print('❌ API Clear Database Error: $e');
      return false;
    }
  }

  // 🔧 دالة مساعدة لتحليل نتيجة التعرف
  static RecognitionResult _parseRecognitionResult(String result) {
    try {
      print('🔧 Parsing recognition result: $result');
      
      bool isMatch = result.contains('✅') || !result.contains('غير معروف');
      double confidence = 0.0;
      String personId = 'Unknown';

      // استخراج الثقة من النص
      final confidenceMatch = RegExp(r'([\d.]+)%').firstMatch(result);
      if (confidenceMatch != null) {
        confidence = double.tryParse(confidenceMatch.group(1) ?? '0') ?? 0.0;
        confidence = confidence / 100.0; // تحويل إلى كسر
      }

      // استخراج الاسم إذا كان معروفاً
      if (isMatch) {
        final nameMatch = RegExp(r'✅\s*([^\n]+)').firstMatch(result);
        if (nameMatch != null) {
          personId = nameMatch.group(1)?.trim() ?? 'Unknown';
        } else {
          // محاولة أخرى لاستخراج الاسم
          final lines = result.split('\n');
          for (String line in lines) {
            if (line.contains('✅')) {
              personId = line.replaceAll('✅', '').trim();
              break;
            }
          }
        }
      }

      // حساب similarity بناءً على confidence
      double similarity = confidence;

      return RecognitionResult(
        personId: personId,
        similarity: similarity,
        isMatch: isMatch,
        confidence: confidence,
      );
    } catch (e) {
      print('❌ Error parsing recognition result: $e');
      return RecognitionResult(
        personId: 'Unknown',
        similarity: 0.0,
        isMatch: false,
        confidence: 0.0,
      );
    }
  }

  // 🔧 دالة مساعدة لاستخراج الأسماء من الإحصائيات
  static List<String> _extractNamesFromStats(String statsText) {
    try {
      List<String> names = [];
      final lines = statsText.split('\n');
      bool inNamesSection = false;

      for (String line in lines) {
        if (line.contains('المسجلين:')) {
          inNamesSection = true;
          continue;
        }
        
        if (inNamesSection) {
          if (line.trim().isEmpty) break; // نهاية القسم
          
          // استخراج الاسم من السطر (مثال: "1. John" أو "✅ John")
          final nameMatch = RegExp(r'[\d.]+\.\s*(.+)').firstMatch(line) ?? 
                          RegExp(r'✅\s*(.+)').firstMatch(line);
          if (nameMatch != null) {
            names.add(nameMatch.group(1)!.trim());
          } else if (line.trim().isNotEmpty && !line.contains('لا يوجد')) {
            names.add(line.trim());
          }
        }
      }

      print('📋 Extracted names: $names');
      return names;
    } catch (e) {
      print('❌ Error extracting names: $e');
      return [];
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