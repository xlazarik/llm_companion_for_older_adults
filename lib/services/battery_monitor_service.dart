import 'dart:async';

import 'package:battery_plus/battery_plus.dart';

import 'log_service.dart';

class BatteryMonitorService {
  static const Duration _pollInterval = Duration(seconds: 30);

  final Battery _battery = Battery();
  final LogService _log = LogService();
  final StreamController<int> _lowBatteryController =
      StreamController<int>.broadcast();

  Timer? _pollTimer;
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  BatteryState _batteryState = BatteryState.unknown;
  int? _lastBatteryLevel;
  bool _started = false;

  Stream<int> get lowBatteryAlerts => _lowBatteryController.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      _batteryState = await _battery.batteryState;
    } catch (e) {
      _log.warning('battery_state_read_failed', detail: '$e');
    }

    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((state) {
      _batteryState = state;
      unawaited(_pollBatteryLevel());
    });

    await _pollBatteryLevel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_pollBatteryLevel());
    });
  }

  bool get _shouldTrackDischarge =>
      _batteryState == BatteryState.discharging ||
      _batteryState == BatteryState.unknown;

  Future<void> _pollBatteryLevel() async {
    try {
      final currentLevel = await _battery.batteryLevel;
      final previousLevel = _lastBatteryLevel;
      _lastBatteryLevel = currentLevel;

      if (previousLevel == null || !_shouldTrackDischarge) {
        return;
      }

      for (final level in _levelsToAnnounce(previousLevel, currentLevel)) {
        _log.warning('battery_low', detail: 'Battery dropped to $level%');
        _lowBatteryController.add(level);
      }
    } catch (e) {
      _log.error('battery_level_read_failed', detail: '$e');
    }
  }

  Iterable<int> _levelsToAnnounce(int previousLevel, int currentLevel) sync* {
    if (currentLevel >= previousLevel) {
      return;
    }

    if (previousLevel > 20 && currentLevel <= 20) {
      yield 20;
    }
    if (previousLevel > 15 && currentLevel <= 15) {
      yield 15;
    }
    if (previousLevel > 10 && currentLevel <= 10) {
      yield 10;
    }

    if (currentLevel < 10) {
      final startLevel = previousLevel <= 9 ? previousLevel - 1 : 9;
      for (int level = startLevel; level >= currentLevel; level--) {
        if (level >= 1) {
          yield level;
        }
      }
    }
  }

  Future<void> dispose() async {
    _pollTimer?.cancel();
    await _batteryStateSubscription?.cancel();
    await _lowBatteryController.close();
  }
}