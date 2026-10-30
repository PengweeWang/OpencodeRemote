import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class KeepAliveService {
  static final KeepAliveService _instance = KeepAliveService._internal();
  factory KeepAliveService() => _instance;
  KeepAliveService._internal();

  static const _channel = MethodChannel('com.pengwee.opencode_remote/keepalive');
  bool _isServiceRunning = false;

  bool get isRunning => _isServiceRunning;

  /// Synchronize Android foreground service state with Opencode session state
  Future<void> syncState({
    required bool isConnected,
    String? hostName,
    int? localPort,
    int? remotePort,
  }) async {
    if (!Platform.isAndroid) return;

    if (isConnected) {
      final name = hostName ?? 'Opencode';
      final title = 'Opencode Remote - 已连接 $name';
      final portInfo = (localPort != null && remotePort != null)
          ? ' (本地 $localPort ➔ 远程 $remotePort)'
          : '';
      final content = '后台保活运行中$portInfo，切屏与息屏保持连接';

      try {
        if (!_isServiceRunning) {
          await _channel.invokeMethod('start', {
            'title': title,
            'content': content,
          });
          _isServiceRunning = true;
        } else {
          await _channel.invokeMethod('update', {
            'title': title,
            'content': content,
          });
        }
      } catch (e) {
        debugPrint('KeepAliveService start/update error: $e');
      }
    } else {
      if (_isServiceRunning) {
        try {
          await _channel.invokeMethod('stop');
        } catch (e) {
          debugPrint('KeepAliveService stop error: $e');
        }
        _isServiceRunning = false;
      }
    }
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (_isServiceRunning) {
      try {
        await _channel.invokeMethod('stop');
      } catch (e) {
        debugPrint('KeepAliveService stop error: $e');
      }
      _isServiceRunning = false;
    }
  }

  /// Check whether the app is on the battery optimization whitelist
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Request system ignore battery optimizations dialog or settings
  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
