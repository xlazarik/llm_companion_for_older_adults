import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/api_models.dart';

class ApiService {
  static const String _baseUrl = 'https://ui.smartiepal.com';
  static String get _assistantId => dotenv.env['ASSISTANT_ID'] ?? '';

  /// Send audio question to the API
  Future<AskResponse> askAudio({
    required String session,
    required int messageId,
    required String audioBase64,
    String? identifier,
  }) async {
    try {
      final request = AskAudioRequest(
        session: session,
        id: messageId,
        audio: audioBase64,
        identifier: identifier,
      );

      final response = await http.post(
        Uri.parse('$_baseUrl/ask/audio'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-assistant-id': _assistantId,
        },
        body: jsonEncode(request.toJson()),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
        return AskResponse.fromJson(jsonResponse);
      } else if (response.statusCode == 403) {
        throw Exception('Forbidden: Check your assistant ID');
      } else {
        throw Exception(
          'API request failed with status ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Failed to send audio: $e');
    }
  }
}
