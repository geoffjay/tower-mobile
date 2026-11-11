/// Session controller: owns the active machine's connection, token, and
/// client. Switching machines closes the old connection and opens the
/// new one. One connection open at a time (battery, per the plan).
library;

import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import '../api/tower_client.dart';
import 'connection.dart';
import 'registry.dart';

/// Phases of bringing a machine online.
enum SessionPhase { disconnected, connecting, connected, ready, failed }

/// State of the active machine session.
class SessionState {
  const SessionState({
    this.phase = SessionPhase.disconnected,
    this.machine,
    this.client,
    this.error,
  });

  final SessionPhase phase;
  final StoredMachine? machine;
  final TowerClient? client;
  final String? error;

  SessionState copyWith({
    SessionPhase? phase,
    StoredMachine? machine,
    TowerClient? client,
    String? error,
  }) => SessionState(
    phase: phase ?? this.phase,
    machine: machine ?? this.machine,
    client: client ?? this.client,
    error: error,
  );
}

/// Brings a machine online: SSH, key bootstrap (first connect), tunnel,
/// token fetch, health probe. Exposes the resulting [TowerClient].
class SessionController extends Stream<SessionState> {
  SessionController(this._registry) {
    _ctl = StreamController<SessionState>.broadcast();
  }

  final MachineRegistry _registry;
  late final StreamController<SessionState> _ctl;
  SessionState _state = const SessionState();
  TowerConnection? _conn;
  String? _fingerprint;

  SessionState get state => _state;

  @override
  StreamSubscription<SessionState> listen(
    void Function(SessionState)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _ctl.stream.listen(onData);

  void _set(SessionState s) {
    _state = s;
    _ctl.add(s);
  }

  /// Connect [machine]. First connect (no key bootstrap yet) needs
  /// [password] and installs the device public key on the host.
  Future<void> connect(
    StoredMachine machine, {
    String? password,
  }) async {
    await disconnect();
    _set(SessionState(phase: SessionPhase.connecting, machine: machine));

    try {
      final (publicKey, privateKey) = await _registry.deviceKeyPair();

      final useKey = machine.keyBootstrapped;
      final keyPair = useKey ? SSHKeyPair.fromPem(privateKey).single : null;

      final conn = await TowerConnection.connect(
        host: machine.host,
        port: machine.port,
        username: machine.username,
        password: useKey ? null : password,
        keyPair: keyPair,
        publicKey: publicKey,
        onHostKeyFingerprint: (type, fingerprint) =>
            _fingerprint = '$type $fingerprint',
      );
      _conn = conn;
      _set(_state.copyWith(phase: SessionPhase.connected));

      // TOFU: record the fingerprint at first sight; refuse a change.
      if (machine.hostKeyFingerprint.isEmpty) {
        final machines = _registry.machines();
        final i = machines.indexWhere((m) => m.id == machine.id);
        if (i >= 0 && _fingerprint != null) {
          machine = machine.copyWith(
            hostKeyFingerprint: _fingerprint,
            keyBootstrapped: password != null,
          );
          machines[i] = machine;
          await _registry.saveMachines(machines);
        }
      } else if (_fingerprint != null &&
          machine.hostKeyFingerprint != _fingerprint) {
        throw ConnectionError(
          'host key changed: was ${machine.hostKeyFingerprint}, '
          'now $_fingerprint',
        );
      }

      // Token: cache in secure storage; refetch when it goes stale.
      var token = await _registry.towerToken(machine.id);
      token ??= await conn.fetchToken();
      var client = TowerClient(conn, token);
      try {
        await client.agents();
      } on TowerApiError catch (e) {
        if (e.code != TowerErrorCode.unauthorized) rethrow;
        token = await conn.fetchToken();
        await _registry.setTowerToken(machine.id, token);
        client = TowerClient(conn, token);
        await client.agents();
      }

      if (!await conn.health()) {
        throw ConnectionError('tower server did not answer /healthz');
      }
      await _registry.setActiveMachine(machine.id);
      _set(SessionState(
        phase: SessionPhase.ready,
        machine: machine,
        client: client,
      ));
    } on ConnectionError catch (e) {
      _set(SessionState(
        phase: SessionPhase.failed,
        machine: machine,
        error: e.message,
      ));
    } catch (e) {
      _set(SessionState(
        phase: SessionPhase.failed,
        machine: machine,
        error: '$e',
      ));
    }
  }

  Future<void> disconnect() async {
    _conn?.close();
    _conn = null;
    _set(const SessionState());
  }

  void dispose() {
    _conn?.close();
    _ctl.close();
  }
}
