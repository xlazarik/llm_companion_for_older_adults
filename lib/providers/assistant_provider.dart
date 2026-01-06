import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../services/audio_recorder_service.dart';
import '../services/api_service.dart';
import '../services/audio_player_service.dart';
import '../models/api_models.dart';

/// App states
enum AppState {
  idle,
  idleWithHistory,
  recording,
  processing,
  playingResponse,
}

class AssistantProvider extends ChangeNotifier {
  // Services
  final AudioRecorderService _recorderService = AudioRecorderService();
  final ApiService _apiService = ApiService();
  final AudioPlayerService _playerService = AudioPlayerService();

  // State
  AppState _currentState = AppState.idle;
  String? _sessionId;
  int _messageCounter = 0;
  String? _lastRecordingPath;
  String? _lastResponseAudio;
  String? _errorMessage;

  // Getters
  AppState get currentState => _currentState;
  bool get hasConversationHistory => _sessionId != null && _messageCounter > 0;
  String? get errorMessage => _errorMessage;

  /// Start recording audio
  Future<void> startRecording() async {
    try {
      _errorMessage = null;
      await _recorderService.startRecording();
      _currentState = AppState.recording;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Chyba pri nahrávaní: $e';
      notifyListeners();
    }
  }

  /// Cancel recording and return to previous state
  Future<void> cancelRecording() async {
    try {
      await _recorderService.cancelRecording();
      _lastRecordingPath = null;
      _currentState = hasConversationHistory
          ? AppState.idleWithHistory
          : AppState.idle;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Chyba pri zrušení: $e';
      notifyListeners();
    }
  }

  /// Submit recorded audio to the API
  Future<void> submitAudio() async {
    try {
      _errorMessage = null;
      _currentState = AppState.processing;
      notifyListeners();

      // Stop recording and get file path
      final recordingPath = await _recorderService.stopRecording();
      if (recordingPath == null) {
        throw Exception('Žiadne nahrávanie nenájdené');
      }
      _lastRecordingPath = recordingPath;

      // Convert to base64
      final audioBase64 = await _recorderService.audioFileToBase64(recordingPath);

      // Initialize session if needed
      if (_sessionId == null) {
        _sessionId = const Uuid().v4();
      }

      // Send to API
      final response = await _apiService.askAudio(
        session: _sessionId!,
        messageId: _messageCounter,
        audioBase64: audioBase64,
      );

      // Increment message counter
      _messageCounter++;

      // Get the latest response with audio
      String? responseAudio;
      if (response.chat != null && response.chat!.isNotEmpty) {
        // Find the last item with audioResponse
        for (var item in response.chat!.reversed) {
          if (item.audioResponse != null && item.audioResponse!.isNotEmpty) {
            responseAudio = item.audioResponse;
            break;
          }
        }
      }

      if (responseAudio == null || responseAudio.isEmpty) {
        throw Exception('Žiadna audio odpoveď');
      }

      _lastResponseAudio = responseAudio;

      // Play the response audio
      await _playerService.playAudioFromBase64(responseAudio);

      _currentState = AppState.playingResponse;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Chyba pri odosielaní: $e';
      _currentState = hasConversationHistory
          ? AppState.idleWithHistory
          : AppState.idle;
      notifyListeners();
    }
  }

  /// Replay the last audio response
  Future<void> replayResponse() async {
    try {
      _errorMessage = null;
      await _playerService.replay();
    } catch (e) {
      _errorMessage = 'Chyba pri prehrávaní: $e';
      notifyListeners();
    }
  }

  /// Acknowledge response and return to idle with history
  Future<void> acknowledgeResponse() async {
    await _playerService.stop();
    _currentState = AppState.idleWithHistory;
    notifyListeners();
  }

  /// Start a new conversation (clear context)
  Future<void> startNewConversation() async {
    await _playerService.cleanupAudio();
    _sessionId = null;
    _messageCounter = 0;
    _lastRecordingPath = null;
    _lastResponseAudio = null;
    _errorMessage = null;
    _currentState = AppState.idle;
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _recorderService.dispose();
    _playerService.dispose();
    super.dispose();
  }
}
