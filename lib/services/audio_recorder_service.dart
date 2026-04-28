import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentRecordingPath;
  Directory? _cachedTempDir;
  bool _permissionPrewarmed = false;

  // --- Speech detection state -------------------------------------------------
  // We sample the recorder amplitude (in dBFS) at a steady interval while a
  // recording is active and count how many of those samples were loud enough
  // to be considered speech. After [stopRecording] callers can use
  // [speechDetected] to decide whether the clip is worth uploading.
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  static const Duration _amplitudeInterval = Duration(milliseconds: 100);
  // dBFS values are <= 0; -160 is silence, 0 is max. -38 dBFS is typically
  // around the level of someone speaking close to the phone in a quiet room.
  static const double _speechThresholdDb = -38.0;
  // Require roughly 300 ms of cumulative "loud" audio before we consider the
  // clip to actually contain speech. Below that we treat it as noise / silence.
  static const int _minLoudSamples = 3;
  int _loudSamples = 0;
  double _maxAmplitudeDb = -160.0;

  /// True when the last recording captured enough loud audio to plausibly be
  /// speech. Always true if amplitude monitoring isn't available on the
  /// platform (we'd rather upload than discard a real recording).
  bool get speechDetected =>
      _loudSamples >= _minLoudSamples || _maxAmplitudeDb > _speechThresholdDb + 6;

  /// Pre-initialize expensive resources (permission state, temp dir) so the
  /// first call to [startRecording] doesn't pay that cost.
  Future<void> prewarm() async {
    try {
      _cachedTempDir ??= await getTemporaryDirectory();
    } catch (_) {}
    if (!_permissionPrewarmed) {
      try {
        await Permission.microphone.status;
        _permissionPrewarmed = true;
      } catch (_) {}
    }
  }

  /// Request microphone permission
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Check if microphone permission is granted
  Future<bool> hasPermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  /// Start recording audio
  Future<void> startRecording() async {
    try {
      if (!await hasPermission()) {
        final granted = await requestPermission();
        if (!granted) {
          throw Exception('Microphone permission denied');
        }
      }

      // Defensive: make sure no previous session is still active.
      try {
        if (await _recorder.isRecording()) {
          await _recorder.stop();
        }
      } catch (_) {}

      final directory = _cachedTempDir ?? await getTemporaryDirectory();
      _cachedTempDir = directory;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${directory.path}/recording_$timestamp.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );

      _resetSpeechDetection();
      _amplitudeSubscription =
          _recorder.onAmplitudeChanged(_amplitudeInterval).listen((amp) {
        final db = amp.current;
        if (db.isFinite) {
          if (db > _maxAmplitudeDb) {
            _maxAmplitudeDb = db;
          }
          if (db > _speechThresholdDb) {
            _loudSamples++;
          }
        }
      }, onError: (_) {});
    } catch (e) {
      throw Exception('Failed to start recording: $e');
    }
  }

  void _resetSpeechDetection() {
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _loudSamples = 0;
    _maxAmplitudeDb = -160.0;
  }

  /// Stop recording and return the file path
  Future<String?> stopRecording() async {
    try {
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      final path = await _recorder.stop();
      _currentRecordingPath = null;
      return path;
    } catch (e) {
      throw Exception('Failed to stop recording: $e');
    }
  }

  /// Cancel recording and delete the file
  Future<void> cancelRecording() async {
    try {
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      await _recorder.stop();
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
        _currentRecordingPath = null;
      }
    } catch (e) {
      throw Exception('Failed to cancel recording: $e');
    }
  }

  /// Convert audio file to base64
  Future<String> audioFileToBase64(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      throw Exception('Failed to convert audio to base64: $e');
    }
  }

  /// Check if currently recording
  Future<bool> isRecording() async {
    return await _recorder.isRecording();
  }

  /// Dispose resources
  void dispose() {
    _recorder.dispose();
  }
}
