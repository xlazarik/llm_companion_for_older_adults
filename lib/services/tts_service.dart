import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _beepPlayer = AudioPlayer();
  bool _isInitialized = false;
  String? _beepPath;

  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    await _tts.setLanguage('sk-SK');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _generateBeepFile();
    _isInitialized = true;
  }

  /// Generate a short beep WAV file
  Future<void> _generateBeepFile() async {
    final dir = await getTemporaryDirectory();
    _beepPath = '${dir.path}/beep.wav';
    final file = File(_beepPath!);
    if (await file.exists()) await file.delete();

    const sampleRate = 44100;
    const durationMs = 400;
    final numSamples = (sampleRate * durationMs / 1000).round();
    final samples = Int16List(numSamples);

    // Pleasant chime: two rising notes with harmonics and smooth decay
    const freq1 = 523.25; // C5
    const freq2 = 659.25; // E5
    const freq3 = 783.99; // G5
    const pi2 = 2 * 3.14159265;

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Exponential decay envelope for bell-like quality
      final decay = exp(-t * 6.0);
      // Quick fade-in to avoid click
      final fadeIn = (t < 0.005) ? t / 0.005 : 1.0;

      // Mix three notes of a major chord with decreasing amplitudes
      final tone1 = sin(pi2 * freq1 * t) * 0.5;
      final tone2 = sin(pi2 * freq2 * t) * 0.35;
      final tone3 = sin(pi2 * freq3 * t) * 0.25;
      // Add soft octave overtone for shimmer
      final overtone = sin(pi2 * freq1 * 2 * t) * 0.1 * exp(-t * 10.0);

      final sample = (tone1 + tone2 + tone3 + overtone) * decay * fadeIn;
      samples[i] = (sample * 28000).round().clamp(-32768, 32767);
    }

    final dataSize = numSamples * 2;
    final header = ByteData(44);
    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, 36 + dataSize, Endian.little);
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final wavBytes = Uint8List(44 + dataSize);
    wavBytes.setRange(0, 44, header.buffer.asUint8List());
    wavBytes.setRange(44, 44 + dataSize, samples.buffer.asUint8List());
    await file.writeAsBytes(wavBytes);
  }

  /// Play a short beep sound and wait for it to finish
  Future<void> playBeep() async {
    await _ensureInitialized();
    if (_beepPath != null) {
      final completer = Completer<void>();
      late StreamSubscription sub;
      sub = _beepPlayer.onPlayerComplete.listen((_) {
        if (!completer.isCompleted) completer.complete();
        sub.cancel();
      });
      await _beepPlayer.play(DeviceFileSource(_beepPath!));
      await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () { sub.cancel(); },
      );
    }
  }

  Future<void> speak(String text) async {
    await _ensureInitialized();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  void dispose() {
    _tts.stop();
    _beepPlayer.dispose();
  }
}
