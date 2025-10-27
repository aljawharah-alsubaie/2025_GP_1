import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class OpenAIService {
  final String _apiKey = dotenv.env['Osk-proj-4RsCiEs2FedU1hg0Iv63rk6Q2Fz2QXZuW9-TVJAcsAh8b06QXTxATPZSeOnnQ0GrQ6L1SkmHysT3BlbkFJ5Svf9_tHOKMUZ00KCF6LhxWkKGT7q8uTiC44Sb1cCL1VzCQCOffmgj9HfXmfrFF3tkORqaJfwA'] ?? '';
  final String _apiUrl = 'https://api.openai.com/v1/chat/completions';

  Future<String> describeImage(File imageFile) async {
    if (_apiKey.isEmpty) {
      return 'API key not configured. Please check your .env file.';
    }

    try {
      // Convert image to base64
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Prepare the request
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o',
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': 'Describe this image in 1-2 short sentences for a blind user. Identify the main object and describe its colors precisely. Be specific about color patterns (stripes, solid, etc.) but keep it brief and useful. Example: "A striped shirt with black and white horizontal stripes".',
                },
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,$base64Image',
                  },
                },
              ],
            },
          ],
          'max_tokens': 100,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        print('Error: ${response.statusCode}');
        print('Response: ${response.body}');
        return 'Sorry, I could not analyze the image. Please try again.';
      }
    } catch (e) {
      print('Exception: $e');
      return 'An error occurred while analyzing the image.';
    }
  }
}