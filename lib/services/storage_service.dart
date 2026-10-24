import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ssh_host.dart';
import '../models/ssh_key_entry.dart';

class StorageService extends ChangeNotifier {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static const String _keyHosts = 'opencode_hosts';
  static const String _keyKeys = 'opencode_keys';
  static const String _keyLastHostId = 'opencode_last_host_id';

  late SharedPreferences _prefs;
  bool _initialized = false;

  final List<SshHost> _hosts = [];
  final List<SshKeyEntry> _keys = [];
  String? _lastHostId;

  List<SshHost> get hosts => List.unmodifiable(_hosts);
  List<SshKeyEntry> get keys => List.unmodifiable(_keys);
  String? get lastHostId => _lastHostId;

  SshHost? get lastHost {
    if (_lastHostId == null) return _hosts.isNotEmpty ? _hosts.first : null;
    return getHostById(_lastHostId!) ?? (_hosts.isNotEmpty ? _hosts.first : null);
  }

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();

    // Load Hosts
    final hostsJson = _prefs.getString(_keyHosts);
    if (hostsJson != null) {
      try {
        final List<dynamic> list = jsonDecode(hostsJson) as List<dynamic>;
        _hosts.clear();
        for (final item in list) {
          _hosts.add(SshHost.fromJson(item as Map<String, dynamic>));
        }
      } catch (e) {
        debugPrint('Error loading hosts: $e');
      }
    }

    // Load Keys
    final keysJson = _prefs.getString(_keyKeys);
    if (keysJson != null) {
      try {
        final List<dynamic> list = jsonDecode(keysJson) as List<dynamic>;
        _keys.clear();
        for (final item in list) {
          _keys.add(SshKeyEntry.fromJson(item as Map<String, dynamic>));
        }
      } catch (e) {
        debugPrint('Error loading keys: $e');
      }
    }

    _lastHostId = _prefs.getString(_keyLastHostId);
    _initialized = true;
    notifyListeners();
  }

  // ---- Hosts ----
  Future<void> saveHost(SshHost host) async {
    final idx = _hosts.indexWhere((h) => h.id == host.id);
    if (idx >= 0) {
      _hosts[idx] = host;
    } else {
      _hosts.add(host);
    }
    await _persistHosts();
    notifyListeners();
  }

  Future<void> deleteHost(String id) async {
    _hosts.removeWhere((h) => h.id == id);
    if (_lastHostId == id) {
      _lastHostId = null;
      await _prefs.remove(_keyLastHostId);
    }
    await _persistHosts();
    notifyListeners();
  }

  SshHost? getHostById(String id) {
    try {
      return _hosts.firstWhere((h) => h.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> setLastHostId(String id) async {
    _lastHostId = id;
    await _prefs.setString(_keyLastHostId, id);
    notifyListeners();
  }

  Future<void> _persistHosts() async {
    final jsonList = _hosts.map((h) => h.toJson()).toList();
    await _prefs.setString(_keyHosts, jsonEncode(jsonList));
  }

  // ---- Keys ----
  Future<void> saveKey(SshKeyEntry key) async {
    final idx = _keys.indexWhere((k) => k.id == key.id);
    if (idx >= 0) {
      _keys[idx] = key;
    } else {
      _keys.add(key);
    }
    await _persistKeys();
    notifyListeners();
  }

  Future<void> deleteKey(String id) async {
    _keys.removeWhere((k) => k.id == id);
    await _persistKeys();
    notifyListeners();
  }

  SshKeyEntry? getKeyById(String id) {
    try {
      return _keys.firstWhere((k) => k.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistKeys() async {
    final jsonList = _keys.map((k) => k.toJson()).toList();
    await _prefs.setString(_keyKeys, jsonEncode(jsonList));
  }
}
