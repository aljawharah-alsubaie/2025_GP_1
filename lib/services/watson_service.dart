import 'dart:convert';
import 'package:http/http.dart' as http;

class WatsonMLService {
  static const String _apiKey = 'zsGa6T0WiBzU5pPET06i9OtwgRImPtf9qvESwd6qKS7j';
  static const String _mlUrl = 'https://us-south.ml.cloud.ibm.com';
  static const String _deploymentId = '905b9f7e-a9c3-4406-8d9e-8ac812e3b234';

  String? _cachedToken;
  DateTime? _tokenExpiry;

  // 🔑 الحصول على Token (مع Cache)
  Future<String> _getAccessToken() async {
    // استخدم Token محفوظ إذا لم ينتهي
    if (_cachedToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _cachedToken!;
    }
    try {
      final response = await http
          .post(
            Uri.parse('https://iam.cloud.ibm.com/identity/token'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'grant_type': 'urn:ibm:params:oauth:grant-type:apikey',
              'apikey': _apiKey,
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _cachedToken = data['access_token'];

        // Token صالح لمدة ساعة، احفظه لـ 50 دقيقة
        _tokenExpiry = DateTime.now().add(const Duration(minutes: 50));

        return _cachedToken!;
      } else {
        throw Exception('Failed to get token: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Token error: $e');
    }
  }

  // 🎯 التنبؤ بالعملة
  Future<Map<String, dynamic>> predictCurrency(List<double> features) async {
    try {
      // تأكد من 19 ميزة بالضبط
      if (features.length != 19) {
        throw Exception('Expected 19 features, got ${features.length}');
      }

      // احصل على Token
      final token = await _getAccessToken();

      // جهّز البيانات
      final payload = {
        "input_data": [
          {
            "fields": [
              "red_mean",
              "green_mean",
              "blue_mean",
              "red_std",
              "green_std",
              "blue_std",
              "brightness",
              "contrast",
              "red_max",
              "green_max",
              "blue_max",
              "red_min",
              "green_min",
              "blue_min",
              "aspect_ratio",
              "red_range",
              "green_range",
              "blue_range",
              "color_variance",
            ],
            "values": [features],
          },
        ],
      };

      print('📤 Sending to Watson: ${features.length} features');

      // أرسل الطلب
      final response = await http
          .post(
            Uri.parse(
              '$_mlUrl/ml/v4/deployments/$_deploymentId/predictions?version=2021-05-01',
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 15));

      print('📥 Watson Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        return {'success': true, 'prediction': result};
      } else {
        print('❌ Error body: ${response.body}');
        throw Exception('Prediction failed: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Watson prediction error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 🔍 فحص الاتصال
  Future<bool> checkHealth() async {
    try {
      await _getAccessToken();
      return true;
    } catch (e) {
      print('Health check failed: $e');
      return false;
    }
  }
}
