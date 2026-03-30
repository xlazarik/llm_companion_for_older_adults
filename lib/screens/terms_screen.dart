import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/tts_service.dart';
import '../services/log_service.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  final TtsService _ttsService = TtsService();
  final LogService _log = LogService();
  bool _isSpeaking = false;

  String get _termsUrl => dotenv.env['TERMS_URL'] ?? '';

  String get _termsText =>
      'Podmienky používania tejto aplikácie nájdete na adrese $_termsUrl. '
      'Používaním tejto aplikácie súhlasíte so spracovaním vašich hlasových nahrávok. '
      'Pre pokračovanie musíte súhlasiť s podmienkami používania. '
      'Stlačte tlačidlo Súhlasím pre pokračovanie, alebo Nesúhlasím pre ukončenie aplikácie.';

  Future<void> _speakTerms() async {
    if (_isSpeaking) {
      await _ttsService.stop();
      setState(() => _isSpeaking = false);
      return;
    }
    setState(() => _isSpeaking = true);
    await _ttsService.speak(_termsText);
    if (mounted) setState(() => _isSpeaking = false);
  }

  Future<void> _accept() async {
    await _ttsService.stop();
    _log.info('terms_accepted');
    if (!mounted) return;
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    await settings.setTermsAccepted(true);
  }

  Future<void> _decline() async {
    await _ttsService.stop();
    _log.info('terms_declined');
    // Close the app
    SystemNavigator.pop();
  }

  @override
  void dispose() {
    _ttsService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              const Icon(
                Icons.description_outlined,
                size: 80,
                color: Colors.blueGrey,
              ),
              const SizedBox(height: 24),
              const Text(
                'Podmienky používania',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const Text(
                        'Pre používanie tejto aplikácie je potrebné súhlasiť '
                        's podmienkami používania.',
                        style: TextStyle(fontSize: 20),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      if (_termsUrl.isNotEmpty) ...[
                        const Text(
                          'Podmienky používania nájdete na adrese:',
                          style: TextStyle(fontSize: 18),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _termsUrl,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Play terms button
              OutlinedButton.icon(
                onPressed: _speakTerms,
                icon: Icon(
                  _isSpeaking ? Icons.stop : Icons.volume_up,
                  size: 28,
                ),
                label: Text(
                  _isSpeaking ? 'Zastaviť' : 'Prehrať podmienky',
                  style: const TextStyle(fontSize: 20),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Accept button
              ElevatedButton(
                onPressed: _accept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Súhlasím',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              // Decline button
              ElevatedButton(
                onPressed: _decline,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Nesúhlasím',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
