import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  static const String _soundFeedbackKey = 'sound_feedback_enabled';
  static const String _avatarsEnabledKey = 'avatars_enabled';
  static const String _termsAcceptedKey = 'terms_accepted';

  bool _soundFeedbackEnabled = false;
  bool _avatarsEnabled = true;
  bool _termsAccepted = false;
  bool _loaded = false;

  bool get soundFeedbackEnabled => _soundFeedbackEnabled;
  bool get avatarsEnabled => _avatarsEnabled;
  bool get termsAccepted => _termsAccepted;
  bool get loaded => _loaded;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _soundFeedbackEnabled = prefs.getBool(_soundFeedbackKey) ?? false;
    _avatarsEnabled = prefs.getBool(_avatarsEnabledKey) ?? true;
    _termsAccepted = prefs.getBool(_termsAcceptedKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setSoundFeedback(bool value) async {
    _soundFeedbackEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundFeedbackKey, value);
    notifyListeners();
  }

  Future<void> setAvatarsEnabled(bool value) async {
    _avatarsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_avatarsEnabledKey, value);
    notifyListeners();
  }

  Future<void> setTermsAccepted(bool value) async {
    _termsAccepted = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_termsAcceptedKey, value);
    notifyListeners();
  }
}
