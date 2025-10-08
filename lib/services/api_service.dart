import 'dart:convert';
import 'package:http/http.dart' as http;

class CurrencyApiService {
  static const String baseUrl = 'http://192.168.86.45:5000';
  
  Future<bool> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      print('Currency API Health Check Error: $e');
      return false;
    }
  }
  
  Future<Map<String, dynamic>> predictCurrency(List<double> features) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/predict'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'values': [features]
        }),
      ).timeout(Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Prediction failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Currency prediction error: $e');
    }
  }
}