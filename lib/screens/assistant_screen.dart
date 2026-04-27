import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import '../providers/assistant_provider.dart';
import '../providers/settings_provider.dart';
import 'camera_capture_screen.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  static const double _avatarSize = 320.0;
  static const Duration _tripleTapWindow = Duration(milliseconds: 450);

  Timer? _idleTapTimer;
  int _idleTapCount = 0;

  void _resetIdleTapTracking() {
    _idleTapTimer?.cancel();
    _idleTapTimer = null;
    _idleTapCount = 0;
  }

  Future<void> _openInAppCamera(
    BuildContext context,
    AssistantProvider provider,
    SettingsProvider settings,
  ) async {
    final imagePath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CameraCaptureScreen(
          soundFeedbackEnabled: settings.soundFeedbackEnabled,
        ),
      ),
    );

    if (!mounted || imagePath == null) {
      return;
    }

    await provider.submitPhoto(imagePath);
  }

  void _handleIdleTap(
    BuildContext context,
    AssistantProvider provider,
    SettingsProvider settings,
  ) {
    _idleTapCount++;

    if (_idleTapCount >= 3) {
      _resetIdleTapTracking();
      unawaited(_openInAppCamera(context, provider, settings));
      return;
    }

    _idleTapTimer?.cancel();
    _idleTapTimer = Timer(_tripleTapWindow, () {
      final tapCount = _idleTapCount;
      _resetIdleTapTracking();

      if (tapCount > 0) {
        provider.startRecording();
      }
    });
  }

  @override
  void dispose() {
    _resetIdleTapTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: _buildSettingsDrawer(context),
      body: SafeArea(
        child: Stack(
          children: [
            Consumer2<AssistantProvider, SettingsProvider>(
              builder: (context, provider, settings, child) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildContent(context, provider, settings),
                );
              },
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.settings, size: 32, color: Colors.grey),
                  onPressed: () {
                    Scaffold.of(ctx).openEndDrawer();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsDrawer(BuildContext context) {
    final privacyUrl = (dotenv.env['PRIVACY_POLICY_URL'] ?? '').isNotEmpty
        ? dotenv.env['PRIVACY_POLICY_URL']!
        : (dotenv.env['TERMS_URL'] ?? '');

    return Drawer(
      child: SafeArea(
        child: Consumer2<SettingsProvider, AssistantProvider>(
          builder: (context, settings, assistant, child) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Nastavenia',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 30),
                SwitchListTile(
                  title: const Text(
                    'Zvukové informovanie',
                    style: TextStyle(fontSize: 20),
                  ),
                  subtitle: const Text(
                    'Hlasové oznámenia o stave aplikácie',
                    style: TextStyle(fontSize: 14),
                  ),
                  value: settings.soundFeedbackEnabled,
                  onChanged: (value) {
                    settings.setSoundFeedback(value);
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text(
                    'Avatary',
                    style: TextStyle(fontSize: 20),
                  ),
                  subtitle: const Text(
                    'Zobrazovať obrázky namiesto ikon',
                    style: TextStyle(fontSize: 14),
                  ),
                  value: settings.avatarsEnabled,
                  onChanged: (value) {
                    settings.setAvatarsEnabled(value);
                  },
                ),
                const Divider(),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    assistant.speakTutorial();
                  },
                  icon: const Icon(Icons.help_outline, size: 28),
                  label: const Text(
                    'Návod',
                    style: TextStyle(fontSize: 20),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const Divider(),
                const SizedBox(height: 10),
                if (privacyUrl.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.description_outlined, size: 28),
                    title: const Text(
                      'Ochrana súkromia',
                      style: TextStyle(fontSize: 18),
                    ),
                    subtitle: Text(
                      privacyUrl,
                      style: const TextStyle(fontSize: 14, color: Colors.blue),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AssistantProvider provider,
    SettingsProvider settings,
  ) {
    if (provider.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage!),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        provider.clearError();
      });
    }

    final avatarsOn = settings.avatarsEnabled;

    switch (provider.currentState) {
      case AppState.idle:
      case AppState.idleWithHistory:
        return _buildIdleScreen(context, provider, settings, avatarsOn);
      case AppState.recording:
        return _buildRecordingScreen(context, provider, avatarsOn);
      case AppState.processing:
      case AppState.playingResponse:
        return _buildProcessingScreen(context, provider, avatarsOn);
    }
  }

  Widget _buildIdleScreen(
    BuildContext context,
    AssistantProvider provider,
    SettingsProvider settings,
    bool avatarsOn,
  ) {
    return GestureDetector(
      onTap: () => _handleIdleTap(context, provider, settings),
      onLongPress: () {
        _resetIdleTapTracking();
        provider.startNewConversationAndRecord();
      },
      behavior: HitTestBehavior.opaque,
      child: Center(
        key: const ValueKey('idle'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAvatar(
              imagePath: avatarsOn ? 'assets/images/avatar_normal.png' : '',
              icon: Icons.face,
              size: _avatarSize,
              color: Colors.blue,
            ),
            const SizedBox(height: 20),
            Text(
              'Trojklik pre fotoaparát',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 8),
            if (provider.hasConversationHistory)
              Text(
                'Podržte pre nový rozhovor',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingScreen(BuildContext context, AssistantProvider provider, bool avatarsOn) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: provider.canSubmitRecording ? () => provider.submitAudio() : null,
      child: Center(
        key: const ValueKey('recording'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAvatar(
              imagePath: avatarsOn ? '' : '',
              icon: Icons.mic,
              size: _avatarSize,
              color: Colors.red,
              isPulsing: true,
            ),
            const SizedBox(height: 20),
            Text(
              provider.isPreparingRecording
                  ? 'Moment, pripravujem mikrofón...'
                  : 'Hovorte. Po dokončení ťuknite pre odoslanie',
              style: const TextStyle(fontSize: 18, color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingScreen(BuildContext context, AssistantProvider provider, bool avatarsOn) {
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 1500)),
          (instance) {
            instance.onLongPress = () => provider.cancelEverything();
          },
        ),
      },
      behavior: HitTestBehavior.opaque,
      child: Center(
        key: const ValueKey('processing'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAvatar(
              imagePath: avatarsOn ? 'assets/images/avatar_thinking.png' : '',
              icon: Icons.psychology,
              size: _avatarSize,
              color: Colors.purple,
              isPulsing: true,
            ),
            const SizedBox(height: 20),
            const Text(
              'Premýšľam...',
              style: TextStyle(fontSize: 20, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar({
    required String imagePath,
    required IconData icon,
    required Color color,
    required double size,
    bool isPulsing = false,
  }) {
    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade200,
      ),
      child: ClipOval(
        child: Image.asset(
          imagePath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (context, error, stackTrace) {
            return Icon(icon, size: size * 0.6, color: color);
          },
        ),
      ),
    );

    if (isPulsing) {
      return _PulsingWidget(child: avatar);
    }
    return avatar;
  }
}

class _PulsingWidget extends StatefulWidget {
  final Widget child;

  const _PulsingWidget({required this.child});

  @override
  State<_PulsingWidget> createState() => _PulsingWidgetState();
}

class _PulsingWidgetState extends State<_PulsingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _animation, child: widget.child);
  }
}
