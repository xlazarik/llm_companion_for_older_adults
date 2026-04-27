import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

import '../models/api_models.dart';

class ApiService {
  static const String _baseUrl = 'https://ui.smartiepal.com';
  static const Duration _requestTimeout = Duration(seconds: 300);
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

      final client = http.Client();
      http.Response response;
      try {
        final httpRequest = http.Request('POST', Uri.parse('$_baseUrl/ask/audio'));
        httpRequest.headers.addAll({
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-assistant-id': _assistantId,
        });
        httpRequest.body = jsonEncode(request.toJson());

        final streamedResponse = await client.send(httpRequest).timeout(_requestTimeout);
        response = await http.Response.fromStream(streamedResponse);
      } finally {
        client.close();
      }

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

  /// Upload a file so it becomes input for an existing session.
  Future<SessionFileResponse> uploadSessionFile({
    required String session,
    required String filePath,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/ask/file'));
      request.headers.addAll({
        'Accept': 'application/json',
        'X-assistant-id': _assistantId,
      });
      request.fields['session'] = session;
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: p.basename(filePath),
          contentType: _contentTypeFor(filePath),
        ),
      );

      final client = http.Client();
      http.Response response;
      try {
        final streamedResponse = await client.send(request).timeout(_requestTimeout);
        response = await http.Response.fromStream(streamedResponse);
      } finally {
        client.close();
      }

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
        return SessionFileResponse.fromJson(jsonResponse);
      } else if (response.statusCode == 403) {
        throw Exception('Forbidden: Check your assistant ID');
      } else {
        throw Exception(
          'Session file upload failed with status ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Failed to upload session file: $e');
    }
  }

  static MediaType _contentTypeFor(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return MediaType('image', 'jpeg');
      case '.png':
        return MediaType('image', 'png');
      case '.webp':
        return MediaType('image', 'webp');
      case '.heic':
        return MediaType('image', 'heic');
      case '.gif':
        return MediaType('image', 'gif');
      default:
        return MediaType('application', 'octet-stream');
    }
  }

}
