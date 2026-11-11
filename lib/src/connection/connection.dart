/// Per-machine connection: SSH session, local port forward to the tower
/// server, bearer token fetch, health probe.
///
/// Design: `decisions/ssh-tunnel-transport.md` in the knowledge base.
/// First connection authenticates with a password and bootstraps the
/// device public key into `authorized_keys`. Later connections use the
/// key. The password lives only in memory for the bootstrap session.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'sse.dart';

/// Result of one HTTP exchange through the tunnel.
class HttpResponse {
  const HttpResponse(this.status, this.body);
  final int status;
  final String body;
}

/// Thrown when the SSH layer fails before any HTTP happens.
class ConnectionError implements Exception {
  ConnectionError(this.message);
  final String message;

  @override
  String toString() => 'connection error: $message';
}

/// One connected machine.
class TowerConnection {
  TowerConnection._(this.ssh, this._forward);

  /// The local listener that tunnels to the host; closed with the
  /// connection so it does not outlive the session.
  final ServerSocket _forward;
  int get _serverPort => _forward.port;
  /// Null for the local test constructor; the real one holds the SSH
  /// session the tunnel runs over.
  final SSHClient? ssh;

  /// Test-only: bind the forward server directly to a local address,
  /// no SSH underneath. Used by the e2e harness against a local tower.
  static Future<TowerConnection> connectLocal({
    required String forwardTo,
    required int forwardPort,
  }) async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    server.listen((client) async {
      try {
        final remote = await Socket.connect(forwardTo, forwardPort);
        client.listen(remote.add, onDone: () => remote.destroy());
        remote.listen(client.add, onDone: () => client.destroy());
      } catch (_) {
        client.destroy();
      }
    });
    return TowerConnection._(null, server);
  }


  /// Open a connection. Password auth on first connect (bootstrap appends
  /// the [publicKey] to `authorized_keys`), key auth afterwards.
  static Future<TowerConnection> connect({
    required String host,
    required int port,
    required String username,
    String? password,
    SSHKeyPair? keyPair,
    String? publicKey,
    Duration timeout = const Duration(seconds: 15),
    void Function(String type, String fingerprint)? onHostKeyFingerprint,
    void Function(String line)? onDebug,
  }) async {
    final SSHSocket socket;
    try {
      socket = await SSHSocket.connect(host, port, timeout: timeout);
    } catch (e) {
      throw ConnectionError('cannot reach $host:$port: $e');
    }

    // One credential, two auth methods: many sshd setups (macOS,
    // PAM-based Linux) accept keyboard-interactive only, others accept
    // plain password. Hand the password out exactly once across both,
    // so a rejection fails fast instead of replaying.
    final handOut = password == null ? null : _once(password);
    final ssh = SSHClient(
      socket,
      username: username,
      identities: keyPair == null ? null : [keyPair],
      onPasswordRequest: handOut,
      onUserInfoRequest: handOut == null
          ? null
          : (request) => List<String>.from(
              [
                for (var i = 0; i < request.prompts.length; i++) handOut(),
              ],
            ),
      onVerifyHostKey: (type, fingerprint) {
        onHostKeyFingerprint?.call(type, _hex(fingerprint));
        // TOFU: the caller records and compares the fingerprint.
        return true;
      },
      printDebug: onDebug == null ? null : (line) => onDebug(line ?? ''),
      handshakeTimeout: timeout,
      authTimeout: timeout,
    );

    try {
      await ssh.authenticated.timeout(timeout);
    } catch (e) {
      ssh.close();
      // Surface the SSH-level reason (wrong password, key refused,
      // host key mismatch) instead of a bare timeout.
      final detail = ssh.isClosed
          ? 'connection closed by $host'
          : 'ssh auth failed: ${sshErrorText(e)}';
      throw ConnectionError(
        'auth failed: $detail (user $username, $host:$port)',
      );
    }

    // First connect: install the device key for future connects.
    if (password != null && publicKey != null) {
      await _bootstrapKey(ssh, publicKey);
    }

    // Local forward: 127.0.0.1:<ephemeral> -> 127.0.0.1:8266 on the host.
    final server = await ServerSocket.bind('127.0.0.1', 0);
    server.listen((client) async {
      // Writing to a socket the peer already closed completes `done` with
      // an error; without a handler that is an unhandled async exception.
      client.done.catchError((Object _) {});
      try {
        final remote = await ssh.forwardLocal('127.0.0.1', 8266);
        client.listen(
          remote.sink.add,
          onError: (Object _) => remote.destroy(),
          onDone: () => remote.sink.close(),
          cancelOnError: true,
        );
        remote.stream.listen(
          (data) {
            try {
              client.add(data);
            } catch (_) {
              remote.destroy();
            }
          },
          onError: (Object _) => client.destroy(),
          onDone: client.destroy,
        );
      } catch (_) {
        client.destroy();
      }
    });

    return TowerConnection._(ssh, server);
  }

  /// Idempotent authorized_keys append: grep for the key body first.
  static Future<void> _bootstrapKey(SSHClient ssh, String publicKey) async {
    final body = publicKey.trim().split(' ')[1];
    final script = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && "
        "touch ~/.ssh/authorized_keys && "
        "if ! grep -qF '$body' ~/.ssh/authorized_keys 2>/dev/null; then "
        "echo '${publicKey.trim()}' >> ~/.ssh/authorized_keys && "
        "chmod 600 ~/.ssh/authorized_keys; fi";
    final res = await _exec(ssh, script);
    if (res.exitCode != 0) {
      throw ConnectionError('key bootstrap failed: ${res.stderr}');
    }
  }

  /// Run one command over the SSH session and collect its output.
  ///
  /// `exitCode` is a plain `int?` that stays null until the remote side
  /// reports an exit status, and stdout/stderr can still hold buffered
  /// data after the channel closes — so wait for the exit status and
  /// drain both streams before returning.
  static Future<ShellResult> _exec(SSHClient ssh, String command) async {
    final session = await ssh.execute(command);
    final out = <int>[];
    final err = <int>[];
    final drains = Future.wait([
      session.stdout.forEach(out.addAll).catchError((Object _) {}),
      session.stderr.forEach(err.addAll).catchError((Object _) {}),
    ]);
    final exitCode = await session.waitForExit(
      timeout: const Duration(seconds: 30),
    );
    await drains.timeout(const Duration(seconds: 10));
    return ShellResult(
      exitCode ?? 0,
      utf8.decode(out),
      utf8.decode(err, allowMalformed: true),
    );
  }

  /// One HTTP/1.1 request through the tunnel. The tower API is a plain
  /// JSON service on the host's loopback; this avoids an HTTP client
  /// dependency stacked on dartssh2's forward.
  Future<HttpResponse> http(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    final qs = query == null || query.isEmpty
        ? ''
        : '?${query.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    final socket = await Socket.connect('127.0.0.1', _serverPort);
    try {
      final payload = body == null
          ? Uint8List(0)
          : Uint8List.fromList(utf8.encode(jsonEncode(body)));
      final head = StringBuffer()
        ..write('$method $path$qs HTTP/1.1\r\n')
        ..write('Host: 127.0.0.1:8266\r\n')
        ..write('Connection: close\r\n')
        ..write('Accept: application/json\r\n');
      headers?.forEach((k, v) => head.write('$k: $v\r\n'));
      if (payload.isNotEmpty) {
        head
          ..write('Content-Type: application/json\r\n')
          ..write('Content-Length: ${payload.length}\r\n');
      }
      head.write('\r\n');
      // `Socket.write` takes a String; passing bytes would send its
      // toString() — a bracketed number list — and the server answers
      // 400 with no JSON envelope.
      socket.write(head.toString());
      if (payload.isNotEmpty) socket.add(payload);

      final data = BytesBuilder();
      await socket.cast<List<int>>().forEach(data.add).timeout(
        const Duration(seconds: 70),
      );
      return _parseHttpResponse(data.takeBytes());
    } finally {
      socket.destroy();
    }
  }

  /// Open a `text/event-stream` through the tunnel. The server sends a
  /// keep-alive comment every 15 s, so 45 s of silence means the tunnel
  /// is dead and the stream fails with [ConnectionError]. Cancelling the
  /// subscription closes the socket.
  Stream<SseFrame> sse(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) {
    // A StreamController, not `async*`: cancelling an async* generator
    // waits until it next yields, which on a quiet feed is a long time.
    // Here cancel closes the socket at once.
    Socket? socket;
    StreamSubscription<SseFrame>? sub;
    var cancelled = false;
    late final StreamController<SseFrame> ctl;
    ctl = StreamController<SseFrame>(
      onListen: () async {
        try {
          final qs = query == null || query.isEmpty
              ? ''
              : '?${query.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
          final s = await Socket.connect('127.0.0.1', _serverPort);
          if (cancelled) {
            s.destroy();
            return;
          }
          socket = s;
          final head = StringBuffer()
            ..write('GET $path$qs HTTP/1.1\r\n')
            ..write('Host: 127.0.0.1:8266\r\n')
            ..write('Accept: text/event-stream\r\n')
            ..write('Cache-Control: no-cache\r\n');
          headers?.forEach((k, v) => head.write('$k: $v\r\n'));
          head.write('\r\n');
          s.write(head.toString());
          sub = parseSse(
            s.cast<List<int>>().timeout(
              const Duration(seconds: 45),
              onTimeout: (sink) {
                sink.addError(ConnectionError('event feed went silent'));
                sink.close();
              },
            ),
          ).listen(
            ctl.add,
            onError: ctl.addError,
            onDone: () {
              s.destroy();
              ctl.close();
            },
          );
        } catch (e) {
          if (!ctl.isClosed) {
            ctl.addError(ConnectionError('event feed: $e'));
            await ctl.close();
          }
        }
      },
      onCancel: () {
        cancelled = true;
        socket?.destroy();
        sub?.cancel();
      },
    );
    return ctl.stream;
  }

  /// Read the tower token file over SSH (no tunnel needed).
  Future<String> fetchToken() async {
    final conn = ssh;
    if (conn == null) {
      throw ConnectionError('no SSH session; local-test connection');
    }
    final res = await _exec(conn, 'cat "\${TOWER_HOME:-}/token" 2>/dev/null'
        ' || cat ~/Library/"Application Support"/tower/token 2>/dev/null'
        ' || cat ~/.local/share/tower/token 2>/dev/null');
    final token = res.stdout.trim();
    if (token.isEmpty) {
      throw ConnectionError(
        'cannot read the tower token file; is the server started?',
      );
    }
    return token;
  }

  /// `GET /healthz` through the tunnel. This tower version requires the
  /// bearer token on `/healthz` too (an unauthenticated probe gets 401).
  Future<bool> health(String token) async {
    final res = await http(
      'GET',
      '/healthz',
      headers: {'Authorization': 'Bearer $token'},
    );
    return res.status == 200;
  }

  /// Completes when the SSH session ends for any reason (dropped
  /// network, server close, [close]). Never throws.
  Future<void> get closed async {
    try {
      await ssh?.done;
    } catch (_) {}
  }

  void close() {
    _forward.close();
    ssh?.close();
  }
}

/// Result of one `ssh.execute`.
class ShellResult {
  const ShellResult(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Hex-encode a host key fingerprint for storage and comparison.
String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Parse a raw HTTP/1.1 response: status, headers, chunked or
/// Content-Length delimited body.
HttpResponse _parseHttpResponse(Uint8List bytes) {
  final headerEnd = _indexOf(bytes, utf8.encode('\r\n\r\n'));
  if (headerEnd < 0) return const HttpResponse(0, '');
  final headerText = utf8.decode(bytes.sublist(0, headerEnd));
  final lines = headerText.split('\r\n');
  final status = int.tryParse(
    lines.first.split(' ').length > 1 ? lines.first.split(' ')[1] : '',
  );
  final headers = <String, String>{};
  for (final line in lines.skip(1)) {
    final i = line.indexOf(':');
    if (i > 0) {
      headers[line.substring(0, i).toLowerCase()] = line.substring(i + 1).trim();
    }
  }
  var body = bytes.sublist(headerEnd + 4);
  if ((headers['transfer-encoding'] ?? '').contains('chunked')) {
    body = _decodeChunked(body);
  } else {
    final len = int.tryParse(headers['content-length'] ?? '');
    if (len != null && len < body.length) body = body.sublist(0, len);
  }
  return HttpResponse(status ?? 0, utf8.decode(body, allowMalformed: true));
}

int _indexOf(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

Uint8List _decodeChunked(Uint8List bytes) {
  final out = BytesBuilder();
  var pos = 0;
  while (pos < bytes.length) {
    final lineEnd = _indexOf(bytes.sublist(pos), utf8.encode('\r\n'));
    if (lineEnd < 0) break;
    final size = int.tryParse(
      utf8.decode(bytes.sublist(pos, pos + lineEnd)).trim(),
      radix: 16,
    );
    if (size == null || size == 0) break;
    pos += lineEnd + 2;
    out.add(bytes.sublist(pos, pos + size));
    pos += size + 2;
  }
  return out.takeBytes();
}

/// Wrap [password] in a handler that hands it out exactly once, then
/// reports no credential left — dartssh2 re-calls the handler for every
/// auth attempt, and replaying a rejected password just burns attempts.
SSHPasswordRequestHandler _once(String password) {
  var handedOut = false;
  return () {
    if (handedOut) return null;
    handedOut = true;
    return password;
  };
}

/// Pull the human-readable reason out of an SSH error.
String sshErrorText(Object e) {
  if (e is SSHError) return e.toString();
  if (e is TimeoutException) return 'timed out';
  return e.toString();
}
