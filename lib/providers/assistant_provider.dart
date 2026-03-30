import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:uuid/uuid.dart';
import '../services/audio_recorder_service.dart';
import '../services/api_service.dart';
import '../services/audio_player_service.dart';
import '../services/tts_service.dart';
import '../services/log_service.dart';
import '../models/api_models.dart';
import 'settings_provider.dart';

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
  final TtsService _ttsService = TtsService();
  final LogService _log = LogService();

  // Settings reference
  SettingsProvider? _settingsProvider;
  Timer? _thinkingTimer;
  bool _cancelled = false;

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

  bool get _soundFeedback => _settingsProvider?.soundFeedbackEnabled ?? false;

  /// Set the settings provider reference
  void setSettingsProvider(SettingsProvider provider) {
    _settingsProvider = provider;
  }

  /// Speak text if sound feedback is enabled
  Future<void> _speakIfEnabled(String text) async {
    if (_soundFeedback) {
      await _ttsService.speak(text);
    }
  }

  /// Play beep if sound feedback is enabled
  Future<void> _playBeepIfEnabled() async {
    if (_soundFeedback) {
      await _ttsService.playBeep();
    }
  }

  /// Start the "thinking" timer that says "Premýšľam" every 5 seconds
  void _startThinkingTimer() {
    _thinkingTimer?.cancel();
    _thinkingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _speakIfEnabled('Premýšľam');
    });
  }

  /// Stop the thinking timer
  void _stopThinkingTimer() {
    _thinkingTimer?.cancel();
    _thinkingTimer = null;
  }

  /// Announce that app is ready (called when entering idle state)
  Future<void> announceReady() async {
    await _speakIfEnabled('Aplikácia je zapnutá, čakám na konverzáciu');
  }

  /// Start recording audio
  Future<void> startRecording() async {
    try {
      _errorMessage = null;
      _log.info('recording_started');
      await _playBeepIfEnabled();
      await _recorderService.startRecording();
      _currentState = AppState.recording;
      notifyListeners();
    } catch (e) {
      _log.error('recording_failed', detail: '$e');
      _errorMessage = 'Chyba pri nahrávaní: $e';
      notifyListeners();
    }
  }

  /// Cancel recording and return to previous state
  Future<void> cancelRecording() async {
    try {
      _log.info('recording_cancelled');
      await _speakIfEnabled('Zrušené');
      await _recorderService.cancelRecording();
      _lastRecordingPath = null;
      _currentState = hasConversationHistory
          ? AppState.idleWithHistory
          : AppState.idle;
      notifyListeners();
    } catch (e) {
      _log.error('recording_cancel_failed', detail: '$e');
      _errorMessage = 'Chyba pri zrušení: $e';
      notifyListeners();
    }
  }

  /// Submit recorded audio to the API
  Future<void> submitAudio() async {
    try {
      _errorMessage = null;
      _cancelled = false;
      _log.info('audio_submitting');
      await _speakIfEnabled('Odosielam');
      _currentState = AppState.processing;
      notifyListeners();

      // Start thinking announcements every 5 seconds
      _startThinkingTimer();

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
      _log.info('api_response_received');

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

      // Check if cancelled during API call
      if (_cancelled) return;

      // Stop thinking timer and TTS before playing response
      _stopThinkingTimer();
      await _ttsService.stop();

      // Check again after stopping TTS
      if (_cancelled) return;

      // Play the response audio
      _log.info('response_playback_started');
      await _playerService.playAudioFromBase64(responseAudio);

      _currentState = AppState.playingResponse;
      notifyListeners();

      // Auto-transition to idle when playback finishes
      _playerService.onPlayerStateChanged.listen((state) {
        if (state == PlayerState.completed || state == PlayerState.stopped) {
          if (_currentState == AppState.playingResponse) {
            _currentState = AppState.idleWithHistory;
            notifyListeners();
          }
        }
      });
    } catch (e) {
      _stopThinkingTimer();
      await _ttsService.stop();
      _log.error('audio_submit_failed', detail: '$e');
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
      await _speakIfEnabled('Prehrávam znova');
      await _playerService.replay();
    } catch (e) {
      _errorMessage = 'Chyba pri prehrávaní: $e';
      notifyListeners();
    }
  }

  /// Acknowledge response and return to idle with history
  Future<void> acknowledgeResponse() async {
    await _playerService.stop();
    await _speakIfEnabled('V poriadku');
    _currentState = AppState.idleWithHistory;
    notifyListeners();
  }

  /// Start a new conversation (clear context)
  Future<void> startNewConversation() async {
    _log.info('new_conversation');
    await _speakIfEnabled('Nový rozhovor');
    await _playerService.cleanupAudio();
    _sessionId = null;
    _messageCounter = 0;
    _lastRecordingPath = null;
    _lastResponseAudio = null;
    _errorMessage = null;
    _currentState = AppState.idle;
    notifyListeners();
  }

  /// Cancel everything (processing/playback) and return to fresh idle
  Future<void> cancelEverything() async {
    _log.info('cancel_everything');
    _cancelled = true;
    _stopThinkingTimer();
    await _ttsService.stop();
    await _playerService.stop();
    await _playerService.cleanupAudio();
    _sessionId = null;
    _messageCounter = 0;
    _lastRecordingPath = null;
    _lastResponseAudio = null;
    _errorMessage = null;
    _currentState = AppState.idle;
    notifyListeners();
    await _speakIfEnabled('Zrušené');
  }

  /// Start a new conversation and immediately begin recording
  Future<void> startNewConversationAndRecord() async {
    _log.info('new_conversation_and_record');
    await _playerService.stop();
    await _playerService.cleanupAudio();
    _sessionId = null;
    _messageCounter = 0;
    _lastRecordingPath = null;
    _lastResponseAudio = null;
    _errorMessage = null;
    await _speakIfEnabled('Nový rozhovor');
    // Small delay so TTS finishes before recording starts
    await Future.delayed(const Duration(milliseconds: 800));
    await _recorderService.startRecording();
    _currentState = AppState.recording;
    notifyListeners();
  }

  /// Speak the tutorial/instructions
  Future<void> speakTutorial() async {
    await _ttsService.speak(
      'Návod na ovládanie aplikácie. '
      'Ťuknite na obrázok a začne sa nahrávanie vašej otázky. '
      'Ťuknite znova a otázka sa odošle. '
      'Počkajte na odpoveď, ktorá sa automaticky prehrá. '
      'Po prehratí odpovede ťuknite na obrázok pre návrat. '
      'Ak chcete začať úplne nový rozhovor, podržte prst na obrázku dve sekundy. '
      'V nastaveniach môžete zapnúť zvukové informovanie a avatary.',
    );
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopThinkingTimer();
    _ttsService.dispose();
    _recorderService.dispose();
    _playerService.dispose();
    super.dispose();
  }
}
