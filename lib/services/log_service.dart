import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LogEntry {
  final DateTime timestamp;
  final String level; // info, warning, error
  final String action;
  final String? detail;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.action,
    this.detail,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level,
    'action': action,
    if (detail != null) 'detail': detail,
  };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
    timestamp: DateTime.parse(json['timestamp']),
    level: json['level'],
    action: json['action'],
    detail: json['detail'],
  );
}

class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  static const String _storageKey = 'pending_logs';
  static const int _sendIntervalMinutes = 5;
  static const int _maxStoredLogs = 500;

  final List<LogEntry> _pendingLogs = [];
  Timer? _sendTimer;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Load any unsent logs from previous session
    await _loadPendingLogs();

    // Start periodic sending
    _sendTimer = Timer.periodic(
      const Duration(minutes: _sendIntervalMinutes),
      (_) => sendLogs(),
    );

    info('app_started', detail: 'LogService initialized');
  }

  /// Log an info-level event
  void info(String action, {String? detail}) {
    _addEntry('info', action, detail: detail);
  }

  /// Log a warning-level event
  void warning(String action, {String? detail}) {
    _addEntry('warning', action, detail: detail);
  }

  /// Log an error-level event
  void error(String action, {String? detail}) {
    _addEntry('error', action, detail: detail);
  }

  void _addEntry(String level, String action, {String? detail}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      action: action,
      detail: detail,
    );
    _pendingLogs.add(entry);

    // Trim if too many
    if (_pendingLogs.length > _maxStoredLogs) {
      _pendingLogs.removeRange(0, _pendingLogs.length - _maxStoredLogs);
    }

    // Persist to disk
    _savePendingLogs();
  }

  /// Send accumulated logs to the server
  Future<void> sendLogs() async {
    if (_pendingLogs.isEmpty) return;

    final url = dotenv.env['LOG_URL'];
    if (url == null || url.isEmpty) return;

    final logsToSend = List<LogEntry>.from(_pendingLogs);

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'logs': logsToSend.map((e) => e.toJson()).toList(),
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Remove sent logs
        _pendingLogs.removeWhere((log) => logsToSend.contains(log));
        await _savePendingLogs();
      }
    } catch (e) {
      debugPrint('LogService: Failed to send logs: $e');
    }
  }

  Future<void> _savePendingLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _pendingLogs.map((e) => e.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('LogService: Failed to save logs: $e');
    }
  }

  Future<void> _loadPendingLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored != null) {
        final List<dynamic> jsonList = jsonDecode(stored);
        _pendingLogs.addAll(
          jsonList.map((e) => LogEntry.fromJson(e as Map<String, dynamic>)),
        );
      }
    } catch (e) {
      debugPrint('LogService: Failed to load logs: $e');
    }
  }

  /// Force send and cleanup
  Future<void> dispose() async {
    _sendTimer?.cancel();
    await sendLogs();
  }
}
