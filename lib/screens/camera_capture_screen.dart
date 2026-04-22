import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/image_capture_service.dart';
import '../services/tts_service.dart';

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({
    super.key,
    required this.soundFeedbackEnabled,
  });

  final bool soundFeedbackEnabled;

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  final ImageCaptureService _imageCaptureService = ImageCaptureService();
  final TtsService _ttsService = TtsService();

  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  bool _isCapturing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeControllerFuture = _initializeCamera();
    unawaited(HapticFeedback.mediumImpact());
    if (widget.soundFeedbackEnabled) {
      unawaited(
        _ttsService.speak(
          'Fotoaparát otvorený. Ťuknite kdekoľvek pre odfotenie. Podržte prst pre zrušenie.',
        ),
      );
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('Fotoaparát nie je dostupný');
      }

      final preferredCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        preferredCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Chyba fotoaparátu: $e';
      });
    }
  }

  Future<void> _capturePhoto() async {
    if (_isCapturing) {
      return;
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      await HapticFeedback.heavyImpact();
      final photo = await controller.takePicture();
      final optimizedPath = await _imageCaptureService.optimizePhoto(photo.path);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(optimizedPath);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Nepodarilo sa odfotiť obrázok: $e';
        _isCapturing = false;
      });
    }
  }

  Future<void> _cancelCapture() async {
    await HapticFeedback.mediumImpact();
    await _ttsService.stop();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    unawaited(_ttsService.stop());
    _ttsService.dispose();
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _initializeControllerFuture,
          builder: (context, snapshot) {
            if (_errorMessage != null) {
              return _buildStatus(
                message: _errorMessage!,
                actionLabel: 'Zatvoriť',
                onAction: _cancelCapture,
              );
            }

            if (snapshot.connectionState != ConnectionState.done || _controller == null) {
              return _buildStatus(
                message: 'Pripravujem fotoaparát...',
                actionLabel: 'Zrušiť',
                onAction: _cancelCapture,
              );
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _capturePhoto,
              onLongPress: _cancelCapture,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(_controller!),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.55),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            'Ťuknite kdekoľvek pre odfotenie',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Podržte prst pre zrušenie',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                          ),
                        ),
                        const Spacer(),
                        Center(
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              color: _isCapturing
                                  ? Colors.orange.withValues(alpha: 0.9)
                                  : Colors.white.withValues(alpha: 0.95),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black54, width: 6),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _isCapturing ? 'Čakajte' : 'FOTO',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatus({
    required String message,
    required String actionLabel,
    required Future<void> Function() onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 24),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  unawaited(onAction());
                },
                child: Text(actionLabel, style: const TextStyle(fontSize: 22)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}