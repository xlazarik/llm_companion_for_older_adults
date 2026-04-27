import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/api_models.dart';
import '../services/api_service.dart';
import '../services/audio_player_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/battery_monitor_service.dart';
import '../services/log_service.dart';
import '../services/tts_service.dart';
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
  final AudioRecorderService _recorderService = AudioRecorderService();
  final ApiService _apiService = ApiService();
  final AudioPlayerService _playerService = AudioPlayerService();
  final BatteryMonitorService _batteryMonitorService = BatteryMonitorService();
  final TtsService _ttsService = TtsService();
  final LogService _log = LogService();

  SettingsProvider? _settingsProvider;
  StreamSubscription<int>? _batteryAlertSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  Timer? _thinkingTimer;
  bool _cancelled = false;
  bool _isBatteryAnnouncementInProgress = false;
  int? _pendingBatteryAnnouncementLevel;

  AppState _currentState = AppState.idle;
  String? _sessionId;
  int _messageCounter = 0;
  int? _lastResponseCounter;
  DateTime? _lastResponseInserted;
  String? _errorMessage;
  bool _isRecordingReady = false;

  AppState get currentState => _currentState;
  bool get hasConversationHistory => _sessionId != null && _messageCounter > 0;
  String? get errorMessage => _errorMessage;
  bool get isPreparingRecording => _currentState == AppState.recording && !_isRecordingReady;
  bool get canSubmitRecording => _currentState == AppState.recording && _isRecordingReady;

  bool get _soundFeedback => _settingsProvider?.soundFeedbackEnabled ?? false;
  bool get _canAnnounceBattery =>
      _currentState == AppState.idle || _currentState == AppState.idleWithHistory;

  AssistantProvider() {
    _batteryAlertSubscription = _batteryMonitorService.lowBatteryAlerts.listen((level) {
      unawaited(_handleBatteryAnnouncement(level));
    });
    _playerStateSubscription = _playerService.onPlayerStateChanged.listen((state) {
      if ((state == PlayerState.completed || state == PlayerState.stopped) &&
          _currentState == AppState.playingResponse) {
        _setCurrentState(AppState.idleWithHistory);
      }
    });
    unawaited(_batteryMonitorService.start());
    unawaited(_recorderService.prewarm());
  }

  void setSettingsProvider(SettingsProvider provider) {
    _settingsProvider = provider;
    if (_soundFeedback) {
      unawaited(_flushPendingBatteryAnnouncement());
    }
  }

  void _setCurrentState(AppState state) {
    _currentState = state;
    notifyListeners();

    if (_canAnnounceBattery) {
      unawaited(
        Future<void>.delayed(const Duration(seconds: 1), () async {
          await _flushPendingBatteryAnnouncement();
        }),
      );
    }
  }

  Future<void> _handleBatteryAnnouncement(int level) async {
    if (!_soundFeedback) {
      return;
    }

    if (!_canAnnounceBattery || _isBatteryAnnouncementInProgress) {
      _pendingBatteryAnnouncementLevel = level;
      return;
    }

    _isBatteryAnnouncementInProgress = true;
    try {
      await _ttsService.speakAndWait('Batéria má $level percent');
    } catch (e) {
      _log.error('battery_announcement_failed', detail: '$e');
    } finally {
      _isBatteryAnnouncementInProgress = false;
    }

    await _flushPendingBatteryAnnouncement();
  }

  Future<void> _flushPendingBatteryAnnouncement() async {
    final level = _pendingBatteryAnnouncementLevel;
    if (level == null ||
        !_soundFeedback ||
        !_canAnnounceBattery ||
        _isBatteryAnnouncementInProgress) {
      return;
    }

    _pendingBatteryAnnouncementLevel = null;
    await _handleBatteryAnnouncement(level);
  }

  Future<void> _speakIfEnabled(String text) async {
    if (_soundFeedback) {
      await _ttsService.speak(text);
    }
  }

  Future<void> _speakAndWaitIfEnabled(String text) async {
    if (_soundFeedback) {
      await _ttsService.speakAndWait(text);
    }
  }

  void _startThinkingTimer() {
    _thinkingTimer?.cancel();
    _thinkingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _speakIfEnabled('Premýšľam');
    });
  }

  void _stopThinkingTimer() {
    _thinkingTimer?.cancel();
    _thinkingTimer = null;
  }

  Future<void> announceReady() async {
    await _speakIfEnabled('Aplikácia je zapnutá, čakám na konverzáciu');
  }

  ChatItem? _findLatestAudioResponse(
    AskResponse response, {
    int? counterAfter,
    DateTime? insertedAfter,
  }) {
    final chat = response.chat;
    if (chat == null || chat.isEmpty) {
      return null;
    }

    for (final item in chat.reversed) {
      final audioResponse = item.audioResponse;
      if (audioResponse == null || audioResponse.isEmpty) {
        continue;
      }

      final matchesCounter =
          counterAfter == null || (item.counter != null && item.counter! > counterAfter);
      final matchesInserted = insertedAfter == null ||
          (item.inserted != null && item.inserted!.isAfter(insertedAfter));

      if (matchesCounter && matchesInserted) {
        return item;
      }
    }

    return null;
  }

  Future<void> _playResponse(ChatItem responseItem) async {
    final responseAudio = responseItem.audioResponse;
    if (responseAudio == null || responseAudio.isEmpty) {
      throw Exception('Žiadna audio odpoveď');
    }

    if (_cancelled) {
      return;
    }

    _stopThinkingTimer();
    await _ttsService.stop();

    if (_cancelled) {
      return;
    }

    _lastResponseCounter = responseItem.counter ?? _lastResponseCounter;
    _lastResponseInserted = responseItem.inserted ?? _lastResponseInserted;

    _log.info('response_playback_started');
    await _playerService.playAudioFromBase64(responseAudio);
    _setCurrentState(AppState.playingResponse);
  }

  Future<void> startRecording() async {
    try {
      if (_currentState == AppState.recording ||
          _currentState == AppState.processing ||
          _currentState == AppState.playingResponse) {
        return;
      }

      _errorMessage = null;
      _isRecordingReady = false;
      _setCurrentState(AppState.recording);
      _log.info('recording_started');
      await _speakAndWaitIfEnabled('Nahrávam');
      if (_soundFeedback) {
        await _ttsService.playBeep();
      }
      await _recorderService.startRecording();
      _isRecordingReady = true;
      notifyListeners();
    } catch (e) {
      _isRecordingReady = false;
      _log.error('recording_failed', detail: '$e');
      _errorMessage = 'Chyba pri nahrávaní: $e';
      _setCurrentState(hasConversationHistory ? AppState.idleWithHistory : AppState.idle);
    }
  }

  Future<void> cancelRecording() async {
    try {
      _log.info('recording_cancelled');
      await _speakIfEnabled('Zrušené');
      await _recorderService.cancelRecording();
      _setCurrentState(hasConversationHistory ? AppState.idleWithHistory : AppState.idle);
    } catch (e) {
      _log.error('recording_cancel_failed', detail: '$e');
      _errorMessage = 'Chyba pri zrušení: $e';
      notifyListeners();
    }
  }

  Future<void> submitAudio() async {
    try {
      if (!canSubmitRecording) {
        return;
      }

      _errorMessage = null;
      _cancelled = false;
      _isRecordingReady = false;
      _setCurrentState(AppState.processing);
      _log.info('audio_submitting');

      final recordingPath = await _recorderService.stopRecording();
      if (recordingPath == null) {
        throw Exception('Žiadne nahrávanie nenájdené');
      }

      await _speakIfEnabled('Odosielam');
      _startThinkingTimer();

      final audioBase64 = await _recorderService.audioFileToBase64(recordingPath);

      _sessionId ??= const Uuid().v4();

      final response = await _apiService.askAudio(
        session: _sessionId!,
        messageId: _messageCounter,
        audioBase64: audioBase64,
      );

      _messageCounter++;
      _log.info('api_response_received');

      final responseItem = _findLatestAudioResponse(
            response,
            counterAfter: _lastResponseCounter,
            insertedAfter: _lastResponseInserted,
          ) ??
          _findLatestAudioResponse(response);
      if (responseItem == null) {
        throw Exception('Žiadna audio odpoveď');
      }

      await _playResponse(responseItem);
    } catch (e) {
      _stopThinkingTimer();
      await _ttsService.stop();
      _log.error('audio_submit_failed', detail: '$e');
      _errorMessage = 'Chyba pri odosielaní: $e';
      _setCurrentState(hasConversationHistory ? AppState.idleWithHistory : AppState.idle);
    }
  }

  Future<void> submitPhoto(String imagePath) async {
    try {
      _errorMessage = null;
      _cancelled = false;
      _log.info('photo_submit_started');

      _sessionId ??= const Uuid().v4();
      _setCurrentState(AppState.processing);
      await _speakAndWaitIfEnabled('Fotku nahrávam');
      _startThinkingTimer();

      await _apiService.uploadSessionFile(
        session: _sessionId!,
        filePath: imagePath,
      );
      _log.info('photo_uploaded');

      _stopThinkingTimer();

      if (_cancelled) {
        return;
      }

      _setCurrentState(hasConversationHistory ? AppState.idleWithHistory : AppState.idle);
      await _speakAndWaitIfEnabled('Obrázok nahratý');
    } catch (e) {
      _stopThinkingTimer();
      await _ttsService.stop();
      _log.error('photo_submit_failed', detail: '$e');
      _errorMessage = 'Chyba pri spracovaní fotografie: $e';
      _setCurrentState(hasConversationHistory ? AppState.idleWithHistory : AppState.idle);
    }
  }

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

  Future<void> acknowledgeResponse() async {
    await _playerService.stop();
    await _speakIfEnabled('V poriadku');
    _setCurrentState(AppState.idleWithHistory);
  }

  Future<void> startNewConversation() async {
    _log.info('new_conversation');
    await _speakIfEnabled('Nový rozhovor');
    await _playerService.cleanupAudio();
    _sessionId = null;
    _messageCounter = 0;
    _lastResponseCounter = null;
    _lastResponseInserted = null;
    _errorMessage = null;
    _setCurrentState(AppState.idle);
  }

  Future<void> cancelEverything() async {
    _log.info('cancel_everything');
    _cancelled = true;
    _stopThinkingTimer();
    await _ttsService.stop();
    await _playerService.stop();
    await _playerService.cleanupAudio();
    _sessionId = null;
    _messageCounter = 0;
    _lastResponseCounter = null;
    _lastResponseInserted = null;
    _errorMessage = null;
    _setCurrentState(AppState.idle);
    await _speakIfEnabled('Zrušené');
  }

  Future<void> startNewConversationAndRecord() async {
    try {
      if (_currentState == AppState.recording ||
          _currentState == AppState.processing ||
          _currentState == AppState.playingResponse) {
        return;
      }

      _log.info('new_conversation_and_record');
      await _playerService.stop();
      await _playerService.cleanupAudio();
      _sessionId = null;
      _messageCounter = 0;
      _lastResponseCounter = null;
      _lastResponseInserted = null;
      _errorMessage = null;
      _isRecordingReady = false;
      _setCurrentState(AppState.recording);
      await _speakAndWaitIfEnabled('Nový rozhovor');
      await _speakAndWaitIfEnabled('Nahrávam');
      if (_soundFeedback) {
        await _ttsService.playBeep();
      }
      await _recorderService.startRecording();
      _isRecordingReady = true;
      notifyListeners();
    } catch (e) {
      _isRecordingReady = false;
      _log.error('new_conversation_and_record_failed', detail: '$e');
      _errorMessage = 'Chyba pri nahrávaní: $e';
      _setCurrentState(AppState.idle);
    }
  }

  Future<void> speakTutorial() async {
    await _ttsService.speak(
      'Návod na ovládanie aplikácie. '
      'Ťuknite na obrázok a začne sa nahrávanie vašej otázky. '
      'Ak na obrázok trikrát rýchlo ťuknete, otvorí sa fotoaparát priamo v aplikácii a odfotená fotografia sa pošle do konverzácie. '
      'Ťuknite znova a otázka sa odošle. '
      'Počkajte na odpoveď, ktorá sa automaticky prehrá. '
      'Po prehratí odpovede ťuknite na obrázok pre návrat. '
      'Ak chcete začať úplne nový rozhovor, podržte prst na obrázku dve sekundy. '
      'V nastaveniach môžete zapnúť zvukové informovanie a avatary.',
    );
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopThinkingTimer();
    unawaited(_batteryAlertSubscription?.cancel());
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_batteryMonitorService.dispose());
    _ttsService.dispose();
    _recorderService.dispose();
    _playerService.dispose();
    super.dispose();
  }
}
