import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/ssh_host.dart';
import '../src/rust/api/simple.dart' as rust_api;
import '../src/rust/opencode.dart';
import '../src/rust/ssh.dart';
import 'keepalive_service.dart';
import 'storage_service.dart';

enum OpencodeState {
  idle,
  connecting,
  checkingService,
  startingService,
  pairing,
  forwarding,
  ready,
  error,
  disconnected,
}

class OpencodeLogEntry {
  final DateTime timestamp;
  final String step;
  final String message;
  final bool isError;

  OpencodeLogEntry({
    required this.step,
    required this.message,
    this.isError = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get timeFormatted {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class OpencodeService extends ChangeNotifier {
  static final OpencodeService _instance = OpencodeService._internal();
  factory OpencodeService() => _instance;
  OpencodeService._internal();

  OpencodeState _state = OpencodeState.idle;
  SshHost? _currentHost;
  String? _currentSessionId;
  String? _localUrl;
  String? _remoteUrl;
  int? _localPort;
  int? _remotePort;
  String? _errorMessage;
  final List<OpencodeLogEntry> _logs = [];

  StreamSubscription<OpencodeSessionEvent>? _subscription;

  OpencodeState get state => _state;
  SshHost? get currentHost => _currentHost;
  String? get currentSessionId => _currentSessionId;
  String? get localUrl => _localUrl;
  String? get remoteUrl => _remoteUrl;
  int? get localPort => _localPort;
  int? get remotePort => _remotePort;
  String? get errorMessage => _errorMessage;
  List<OpencodeLogEntry> get logs => List.unmodifiable(_logs);

  bool get isConnecting =>
      _state == OpencodeState.connecting ||
      _state == OpencodeState.checkingService ||
      _state == OpencodeState.startingService ||
      _state == OpencodeState.pairing ||
      _state == OpencodeState.forwarding;

  bool get isConnected => _state == OpencodeState.ready;

  void _addLog(String step, String message, {bool isError = false}) {
    _logs.add(OpencodeLogEntry(step: step, message: message, isError: isError));
    notifyListeners();
  }

  Future<void> connect(SshHost host) async {
    // If an existing session is running, cleanly disconnect first
    if (_currentSessionId != null) {
      await disconnect();
    }

    _currentHost = host;
    _logs.clear();
    _errorMessage = null;
    _localUrl = null;
    _remoteUrl = null;
    _localPort = null;
    _remotePort = null;
    _state = OpencodeState.connecting;
    notifyListeners();

    final sessionId = 'oc_${DateTime.now().millisecondsSinceEpoch}_${host.id}';
    _currentSessionId = sessionId;

    _addLog('init', 'Initiating connection to ${host.name} (${host.host}:${host.port})...');

    // Resolve private key if key-based authentication
    String? privKeyStr;
    if (host.authType == 'key' && host.keyId != null) {
      final keyEntry = StorageService().getKeyById(host.keyId!);
      if (keyEntry != null) {
        privKeyStr = keyEntry.privateKeyOpenSsh;
      } else {
        _state = OpencodeState.error;
        _errorMessage = 'Referenced SSH Key not found in local storage.';
        _addLog('error', _errorMessage!, isError: true);
        notifyListeners();
        return;
      }
    }

    final sshConfig = SshConnectConfig(
      host: host.host,
      port: host.port,
      username: host.username,
      authType: host.authType,
      password: host.password,
      privateKey: privKeyStr,
      passphrase: host.passphrase,
    );

    final opencodeConfig = OpencodeConnectConfig(
      sessionId: sessionId,
      sshConfig: sshConfig,
      remoteWorkdir: host.remoteWorkdir,
      customOpencodePath: host.customOpencodePath,
      preferredLocalPort: host.preferredLocalPort,
    );

    try {
      final stream = rust_api.startOpencodeSession(config: opencodeConfig);

      _subscription = stream.listen(
        (event) {
          _handleSessionEvent(event);
        },
        onError: (err) {
          _state = OpencodeState.error;
          _errorMessage = err.toString();
          _addLog('error', 'Error in session stream: $err', isError: true);
          notifyListeners();
        },
        onDone: () {
          if (_state != OpencodeState.error && _state != OpencodeState.ready) {
            _state = OpencodeState.disconnected;
            _addLog('closed', 'Session closed');
            notifyListeners();
          }
        },
      );

      // Record last connected time
      host.lastConnected = DateTime.now();
      await StorageService().saveHost(host);
      await StorageService().setLastHostId(host.id);
    } catch (e) {
      _state = OpencodeState.error;
      _errorMessage = e.toString();
      _addLog('error', 'Failed to start session: $e', isError: true);
      notifyListeners();
    }
  }

  void _handleSessionEvent(OpencodeSessionEvent event) {
    switch (event.step) {
      case 'connecting':
        _state = OpencodeState.connecting;
        _addLog(event.step, event.message);
        break;
      case 'checking':
        _state = OpencodeState.checkingService;
        _addLog(event.step, event.message);
        break;
      case 'starting_service':
        _state = OpencodeState.startingService;
        _addLog(event.step, event.message);
        break;
      case 'pairing':
        _state = OpencodeState.pairing;
        _addLog(event.step, event.message);
        break;
      case 'forwarding':
        _state = OpencodeState.forwarding;
        _addLog(event.step, event.message);
        break;
      case 'ready':
        _state = OpencodeState.ready;
        _localUrl = event.localUrl;
        _remoteUrl = event.remoteUrl;
        _localPort = event.localPort;
        _remotePort = event.remotePort;
        _addLog(event.step, event.message);
        // Start foreground service keepalive
        KeepAliveService().syncState(
          isConnected: true,
          hostName: _currentHost?.name,
          localPort: _localPort,
          remotePort: _remotePort,
        );
        break;
      case 'error':
        _state = OpencodeState.error;
        _errorMessage = event.message;
        _addLog(event.step, event.message, isError: true);
        KeepAliveService().syncState(isConnected: false);
        break;
      case 'closed':
        _state = OpencodeState.disconnected;
        _addLog(event.step, event.message);
        KeepAliveService().syncState(isConnected: false);
        break;
      default:
        _addLog(event.step, event.message);
        break;
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    final sId = _currentSessionId;
    _currentSessionId = null;
    _state = OpencodeState.disconnected;
    _addLog('disconnect', 'Disconnected by user');
    KeepAliveService().syncState(isConnected: false);
    notifyListeners();

    if (sId != null) {
      try {
        await rust_api.stopOpencodeSession(sessionId: sId);
      } catch (e) {
        debugPrint('stopOpencodeSession error: $e');
      }

      final sub = _subscription;
      _subscription = null;
      try {
        await sub?.cancel().timeout(const Duration(milliseconds: 300));
      } catch (e) {
        debugPrint('subscription cancel error: $e');
      }
    }
  }

  Future<String> refreshPairUrl() async {
    final sId = _currentSessionId;
    if (sId == null || _state != OpencodeState.ready) {
      throw Exception('No active connected session to refresh URL for');
    }
    try {
      _addLog('refresh', 'Requesting new pair token...');
      final newUrl = await rust_api.refreshOpencodeUrl(sessionId: sId);
      _localUrl = newUrl;
      _addLog('refresh', 'Pair token updated: $newUrl');
      notifyListeners();
      return newUrl;
    } catch (e) {
      _addLog('refresh_error', 'Failed to refresh pair URL: $e', isError: true);
      rethrow;
    }
  }

  Future<String> controlService(String action) async {
    final sId = _currentSessionId;
    if (sId == null) {
      throw Exception('No active session');
    }
    try {
      _addLog('service_control', 'Executing opencode service $action...');
      final result = await rust_api.controlOpencodeService(
        sessionId: sId,
        action: action,
      );
      _addLog('service_control', 'Result ($action): $result');
      notifyListeners();
      return result;
    } catch (e) {
      _addLog('service_control_error', 'Service $action failed: $e', isError: true);
      rethrow;
    }
  }

  Future<String> testHost(SshHost host) async {
    String? privKeyStr;
    if (host.authType == 'key' && host.keyId != null) {
      final keyEntry = StorageService().getKeyById(host.keyId!);
      if (keyEntry != null) {
        privKeyStr = keyEntry.privateKeyOpenSsh;
      }
    }

    final sshConfig = SshConnectConfig(
      host: host.host,
      port: host.port,
      username: host.username,
      authType: host.authType,
      password: host.password,
      privateKey: privKeyStr,
      passphrase: host.passphrase,
    );

    return await rust_api.testSshConnection(config: sshConfig);
  }
}
