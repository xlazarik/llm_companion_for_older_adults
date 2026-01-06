import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/assistant_provider.dart';

class AssistantScreen extends StatelessWidget {
  const AssistantScreen({super.key});
  final double AVATAR_SIZE = 320.0;
  final bool AVATARS_ON = true; // whether to use image avatars instead of icons

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<AssistantProvider>(
          builder: (context, provider, child) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildContent(context, provider),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, AssistantProvider provider) {
    // Show error if present
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

    switch (provider.currentState) {
      case AppState.idle:
      case AppState.idleWithHistory:
        return _buildIdleScreen(context, provider);
      case AppState.recording:
        return _buildRecordingScreen(context, provider);
      case AppState.processing:
        return _buildProcessingScreen(context, provider);
      case AppState.playingResponse:
        return _buildPlayingResponseScreen(context, provider);
    }
  }

  /// Idle screen - main avatar with "Hovoriť" button
  Widget _buildIdleScreen(BuildContext context, AssistantProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
              // Avatar
              _buildAvatar(
                imagePath: AVATARS_ON ? 'assets/images/avatar_normal.png': '',
                icon: Icons.face,
                size: AVATAR_SIZE,
                color: Colors.blue,
              ),
          SizedBox(height: 60),
          // Main "Hovoriť" button
          _buildLargeButton(
            text: 'Hovoriť',
            onPressed: () => provider.startRecording(),
            color: Colors.green,
          ),

          // "Nový rozhovor" button (only if has history)
          if (provider.hasConversationHistory) ...[
            const SizedBox(height: 20),
            _buildLargeButton(
              text: 'Nový rozhovor',
              onPressed: () => provider.startNewConversation(),
              color: Colors.orange,
              ),
            ],
        ],
      ),
    );
  }

  /// Recording screen - microphone icon with "Poslať" and "Zrušiť" buttons
  Widget _buildRecordingScreen(
    BuildContext context,
    AssistantProvider provider,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Recording indicator (microphone icon)
          _buildAvatar(
            imagePath: "", // no avatar for now
            icon: Icons.mic,
            size: AVATAR_SIZE,
            color: Colors.red,
            isPulsing: true,
          ),
          const SizedBox(height: 60),

          // Buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLargeButton(
                text: 'Poslať',
                onPressed: () => provider.submitAudio(),
                color: Colors.blue,
                width: 180,
              ),
              const SizedBox(width: 20),
              _buildLargeButton(
                text: 'Zrušiť',
                onPressed: () => provider.cancelRecording(),
                color: Colors.grey,
                width: 180,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Processing screen - thinking avatar, no buttons
  Widget _buildProcessingScreen(
    BuildContext context,
    AssistantProvider provider,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Thinking avatar
          _buildAvatar(
            imagePath: AVATARS_ON ? 'assets/images/avatar_thinking.png': '',
            icon: Icons.psychology,
            size: AVATAR_SIZE,
            color: Colors.purple,
            isPulsing: true,
          ),
          const SizedBox(height: 40),
          const Text(
            'Premýšľam...',
            style: TextStyle(fontSize: 24, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  /// Playing response screen - speaking avatar with "Znova" and "Ok" buttons
  Widget _buildPlayingResponseScreen(
    BuildContext context,
    AssistantProvider provider,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Speaking avatar
          _buildAvatar(
            imagePath: AVATARS_ON ? 'assets/images/avatar_speaking.png': '',
            icon: Icons.record_voice_over,
            size: AVATAR_SIZE,
            color: Colors.green,
            isPulsing: true,
          ),
          const SizedBox(height: 60),

          // Buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLargeButton(
                text: 'Znova',
                onPressed: () => provider.replayResponse(),
                color: Colors.orange,
                width: 180,
              ),
              const SizedBox(width: 20),
              _buildLargeButton(
                text: 'Ok',
                onPressed: () => provider.acknowledgeResponse(),
                color: Colors.green,
                width: 180,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build avatar widget
  Widget _buildAvatar({
    required String imagePath,
    required IconData icon,
    required Color color,
    required double size,
    bool isPulsing = false,
  }) {
    Widget avatar = 
              // Stack(
            // children: [
              Container(
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
            // Fallback to icon if image not found
            return Icon(icon, size: size * 0.6, color: color);
          },
        ),
      ),
    );
    //  const SizedBox(height: 60),

              // Positioned(
              //   left: 0,
              //   right: 0,
              //   bottom: 0,
              //   height: 200, // Height of the gradient area (adjust as needed)
              //   child: Container(
              //     decoration: BoxDecoration(
              //       gradient: LinearGradient(
              //         begin: Alignment.topCenter,
              //         end: Alignment.bottomCenter,
              //     colors: [
              //       Colors.white.withOpacity(0.0),
              //       Colors.white.withOpacity(0.6),
              //       Colors.white.withOpacity(1.0),
              //       Colors.white.withOpacity(1.0),
              //     ],
              //     stops: [0.0, 0.3, 0.6, 1.0],
              //       ),
              //     ),
              //   ),
              // ),],);

    if (isPulsing) {
      return _PulsingWidget(child: avatar);
    }
    return avatar;
  }

  /// Build large button
  Widget _buildLargeButton({
    required String text,
    required VoidCallback onPressed,
    required Color color,
    double height = 120,
    double width = 300,
  }) {
    return SizedBox(
      height: height,
      width: width,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 8,
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// Pulsing animation widget
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
