/// Session controller: owns the active machine's connection, token, and
/// client. Switching machines closes the old connection and opens the
/// new one. One connection open at a time (battery, per the plan).
library;

import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import '../api/live_feed.dart';
import '../api/tower_client.dart';
import 'connection.dart';
import 'registry.dart';

/// Print SSH debug lines to the console; visible under `flutter run`.
void debugLog(String line) {
  // ignore: avoid_print
  print('ssh: $line');
}

/// Phases of bringing a machine online.
enum SessionPhase { disconnected, connecting, connected, ready, failed }

/// State of the active machine session.
class SessionState {
  const SessionState({
    this.phase = SessionPhase.disconnected,
    this.machine,
    this.client,
    this.error,
    this.needsPassword = false,
    this.feed,
  });

  final SessionPhase phase;
  final StoredMachine? machine;
  final TowerClient? client;
  final String? error;

  /// Key auth failed and no password was supplied: the UI should ask
  /// for one and reconnect.
  final bool needsPassword;

  /// Live event feed; set only while [phase] is ready.
  final LiveFeed? feed;

  SessionState copyWith({
    SessionPhase? phase,
    StoredMachine? machine,
    TowerClient? client,
    String? error,
    bool? needsPassword,
  }) => SessionState(
    phase: phase ?? this.phase,
    machine: machine ?? this.machine,
    client: client ?? this.client,
    error: error,
    needsPassword: needsPassword ?? this.needsPassword,
    feed: feed,
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
  Future<void> connect(StoredMachine machine, {String? password}) async {
    _recovery = null;
    await _connect(machine, password: password);
  }

  /// Delays before each automatic reconnect attempt after a drop.
  static const _recoverDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ];

  /// Identifies the running recovery loop; cleared by an explicit
  /// connect or disconnect, which makes the loop stop.
  Object? _recovery;

  Future<void> _recover(StoredMachine machine) async {
    final token = _recovery = Object();
    for (var i = 0; i < _recoverDelays.length; i++) {
      _set(
        SessionState(
          phase: SessionPhase.connecting,
          machine: machine,
          error:
              'connection to ${machine.name} lost; reconnecting '
              '(${i + 1}/${_recoverDelays.length})',
        ),
      );
      await Future<void>.delayed(_recoverDelays[i]);
      if (!identical(_recovery, token)) return;
      await _connect(machine);
      if (!identical(_recovery, token)) return;
      final s = _state;
      if (s.phase == SessionPhase.ready || s.needsPassword) break;
      machine = s.machine ?? machine;
    }
    if (identical(_recovery, token)) _recovery = null;
    if (_state.phase != SessionPhase.ready && !_state.needsPassword) {
      _set(
        SessionState(
          phase: SessionPhase.failed,
          machine: machine,
          error: 'connection to ${machine.name} lost; tap it to reconnect',
        ),
      );
    }
  }

  /// The app went to the background: close the event stream. The SSH
  /// session stays; Android may drop it, and [resume] finds out.
  void pause() => _state.feed?.pause();

  /// The app is back: probe the tunnel. A dead one is closed, which
  /// starts recovery; a live one reopens the feed from its cursor.
  Future<void> resume() async {
    final conn = _conn;
    final client = _state.client;
    if (conn == null || client == null || _state.phase != SessionPhase.ready) {
      return;
    }
    bool ok;
    try {
      ok = await conn.health(client.token).timeout(const Duration(seconds: 8));
    } catch (_) {
      ok = false;
    }
    if (!identical(_conn, conn)) return;
    if (ok) {
      _state.feed?.resume();
    } else {
      conn.close();
    }
  }

  Future<void> _connect(StoredMachine machine, {String? password}) async {
    await _teardown();
    _set(SessionState(phase: SessionPhase.connecting, machine: machine));

    var useKey = false;
    try {
      final (publicKey, privateKey) = await _registry.deviceKeyPair();

      // A regenerated (pre-fix) key invalidates every machine's
      // bootstrap flag: the public key on the hosts is the broken one's
      // sibling that never authenticated, so re-bootstrap everywhere.
      if (await _registry.deviceKeyWasRegenerated()) {
        final machines = _registry.machines();
        final i = machines.indexWhere((m) => m.id == machine.id);
        if (i >= 0) {
          machine = machine.copyWith(keyBootstrapped: false);
          machines[i] = machine;
          await _registry.saveMachines(machines);
        }
      }

      useKey = machine.keyBootstrapped;
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
        onDebug: debugLog,
      );
      _conn = conn;
      _set(_state.copyWith(phase: SessionPhase.connected));

      // TOFU: record the fingerprint at first sight; refuse a change.
      if (machine.hostKeyFingerprint.isNotEmpty &&
          _fingerprint != null &&
          machine.hostKeyFingerprint != _fingerprint) {
        throw ConnectionError(
          'host key changed: was ${machine.hostKeyFingerprint}, '
          'now $_fingerprint',
        );
      }
      // A password login installed the device key on the host. Record
      // that even when the fingerprint was saved earlier (an attempt
      // that connected but failed later), or key auth never turns on.
      final firstSight =
          machine.hostKeyFingerprint.isEmpty && _fingerprint != null;
      if (firstSight || (password != null && !machine.keyBootstrapped)) {
        final machines = _registry.machines();
        final i = machines.indexWhere((m) => m.id == machine.id);
        if (i >= 0) {
          machine = machine.copyWith(
            hostKeyFingerprint: firstSight
                ? _fingerprint
                : machine.hostKeyFingerprint,
            keyBootstrapped: machine.keyBootstrapped || password != null,
          );
          machines[i] = machine;
          await _registry.saveMachines(machines);
        }
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

      if (!await conn.health(client.token)) {
        throw ConnectionError('tower server did not answer /healthz');
      }
      await _registry.setActiveMachine(machine.id);
      _set(
        SessionState(
          phase: SessionPhase.ready,
          machine: machine,
          client: client,
          feed: LiveFeed(client),
        ),
      );
      // The tunnel can die under us (network change, sshd restart,
      // Android killing the socket in the background). Reconnect on our
      // own with key auth; screens refetch when the new feed goes live.
      unawaited(
        conn.closed.then((_) {
          if (!identical(_conn, conn) || _state.phase != SessionPhase.ready) {
            return;
          }
          _state.feed?.dispose();
          unawaited(_recover(machine));
        }),
      );
    } on ConnectionError catch (e) {
      // Key auth refused with no password available: ask for one
      // instead of dead-ending. The UI reconnects with the answer.
      final keyRejected =
          useKey &&
          (e.message.contains('auth failed') || e.message.contains('closed'));
      _set(
        SessionState(
          phase: SessionPhase.failed,
          machine: machine,
          error: e.message,
          needsPassword: keyRejected && password == null,
        ),
      );
    } catch (e) {
      _set(
        SessionState(phase: SessionPhase.failed, machine: machine, error: '$e'),
      );
    }
  }

  Future<void> disconnect() async {
    _recovery = null;
    await _teardown();
  }

  Future<void> _teardown() async {
    _state.feed?.dispose();
    _conn?.close();
    _conn = null;
    _set(const SessionState());
  }

  void dispose() {
    _recovery = null;
    _state.feed?.dispose();
    _conn?.close();
    _ctl.close();
  }
}
