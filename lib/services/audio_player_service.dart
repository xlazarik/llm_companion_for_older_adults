import 'dart:io';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  String? _currentAudioPath;

  /// Play audio from base64 string
  Future<void> playAudioFromBase64(String base64Audio) async {
    try {
      // Decode base64 to bytes
      final bytes = base64Decode(base64Audio);

      // Save to temporary file
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentAudioPath = '${directory.path}/response_$timestamp.mp3';
      final file = File(_currentAudioPath!);
      await file.writeAsBytes(bytes);

      // Play the audio file
      await _player.play(DeviceFileSource(_currentAudioPath!));
    } catch (e) {
      throw Exception('Failed to play audio: $e');
    }
  }

  /// Replay the current audio
  Future<void> replay() async {
    try {
      if (_currentAudioPath != null) {
        await _player.stop();
        await _player.play(DeviceFileSource(_currentAudioPath!));
      }
    } catch (e) {
      throw Exception('Failed to replay audio: $e');
    }
  }

  /// Stop playing audio
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (e) {
      throw Exception('Failed to stop audio: $e');
    }
  }

  /// Check if audio is currently playing
  Future<bool> isPlaying() async {
    return _player.state == PlayerState.playing;
  }

  /// Listen to player state changes
  Stream<PlayerState> get onPlayerStateChanged => _player.onPlayerStateChanged;

  /// Clean up temporary audio file
  Future<void> cleanupAudio() async {
    try {
      await _player.stop();
      if (_currentAudioPath != null) {
        final file = File(_currentAudioPath!);
        if (await file.exists()) {
          await file.delete();
        }
        _currentAudioPath = null;
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }

  /// Dispose resources
  void dispose() {
    _player.dispose();
  }
}
