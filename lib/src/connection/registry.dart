/// Stored machines and secrets.
///
/// Machines live in `shared_preferences` (non-secret metadata). The tower
/// bearer token per machine lives in `flutter_secure_storage` (Android
/// Keystore). The SSH device key pair is generated once, stored in secure
/// storage, and its public half is what the bootstrap installs.
library;

import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pinenacl/ed25519.dart';
import 'package:shared_preferences/shared_preferences.dart';



/// A machine the app can connect to.
class StoredMachine {
  const StoredMachine({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.hostKeyFingerprint,
    this.keyBootstrapped = false,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  /// Trust-on-first-use host key fingerprint, recorded at first connect.
  final String hostKeyFingerprint;
  /// True once the device key is in the host's `authorized_keys`.
  final bool keyBootstrapped;

  StoredMachine copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    String? hostKeyFingerprint,
    bool? keyBootstrapped,
  }) =>
      StoredMachine(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        hostKeyFingerprint: hostKeyFingerprint ?? this.hostKeyFingerprint,
        keyBootstrapped: keyBootstrapped ?? this.keyBootstrapped,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'username': username,
    'host_key_fingerprint': hostKeyFingerprint,
    'key_bootstrapped': keyBootstrapped,
  };

  factory StoredMachine.fromJson(Map<String, dynamic> json) => StoredMachine(
    id: json['id'] as String,
    name: json['name'] as String,
    host: json['host'] as String,
    port: json['port'] as int? ?? 22,
    username: json['username'] as String,
    hostKeyFingerprint: json['host_key_fingerprint'] as String? ?? '',
    keyBootstrapped: json['key_bootstrapped'] as bool? ?? false,
  );
}

/// Registry of machines plus the device key material.
class MachineRegistry {
  MachineRegistry(this._prefs, this._secure);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  static const _machinesKey = 'machines';
  static const _activeKey = 'active_machine';
  static const _pubkeyKey = 'device_public_key';
  static const _privkeyKey = 'device_private_key';
  static const _tokenPrefix = 'tower_token:';

  static Future<MachineRegistry> create() async {
    final prefs = await SharedPreferences.getInstance();
    const secure = FlutterSecureStorage();
    return MachineRegistry(prefs, secure);
  }

  List<StoredMachine> machines() {
    final raw = _prefs.getString(_machinesKey);
    if (raw == null) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return [
      for (final m in list)
        StoredMachine.fromJson(m as Map<String, dynamic>),
    ];
  }

  Future<void> saveMachines(List<StoredMachine> machines) =>
      _prefs.setString(
        _machinesKey,
        jsonEncode([for (final m in machines) m.toJson()]),
      );

  String? activeMachineId() => _prefs.getString(_activeKey);

  Future<void> setActiveMachine(String? id) async {
    if (id == null) {
      await _prefs.remove(_activeKey);
    } else {
      await _prefs.setString(_activeKey, id);
    }
  }

  // --------------------------------------------------------- secrets

  Future<String?> towerToken(String machineId) =>
      _secure.read(key: '$_tokenPrefix$machineId');

  Future<void> setTowerToken(String machineId, String token) =>
      _secure.write(key: '$_tokenPrefix$machineId', value: token);

  Future<void> clearTowerToken(String machineId) =>
      _secure.delete(key: '$_tokenPrefix$machineId');

  /// The device SSH key pair, generated on first use. The private key
  /// stays in secure storage in OpenSSH format.
  Future<(String public, String private)> deviceKeyPair() async {
    final existingPub = await _secure.read(key: _pubkeyKey);
    final existingPriv = await _secure.read(key: _privkeyKey);
    if (existingPub != null && existingPriv != null) {
      return (existingPub, existingPriv);
    }
    final pair = await _generateKeyPair();
    await _secure.write(key: _pubkeyKey, value: pair.$1);
    await _secure.write(key: _privkeyKey, value: pair.$2);
    return pair;
  }

  Future<void> clearDeviceKey() async {
    await _secure.delete(key: _pubkeyKey);
    await _secure.delete(key: _privkeyKey);
  }

  /// Generate an Ed25519 OpenSSH key pair. dartssh2 has no generate()
  /// helper; the seed comes from pinenacl's `SigningKey.generate()` (the
  /// same crypto stack dartssh2 uses for Ed25519 signing).
  Future<(String public, String private)> _generateKeyPair() async {
    final signing = SigningKey.generate();
    final pair = OpenSSHEd25519KeyPair(
      Uint8List.fromList(signing.verifyKey.asTypedList),
      Uint8List.fromList(signing.seed),
      'tower-mobile',
    );
    final publicKey =
        'ssh-ed25519 '
        '${base64.encode(pair.toPublicKey().encode())} tower-mobile';
    return (publicKey, pair.toPem());
  }
}
