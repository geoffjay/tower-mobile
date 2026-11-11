/// Typed wrappers over the tower REST API.
///
/// Every request goes through the active connection's forwarded port with
/// `Authorization: Bearer`. Error envelope:
/// `{"error": {code, message, detail?}}` — mapped to [TowerApiError].
library;

import 'dart:convert';

import '../connection/connection.dart';
import 'models.dart';

/// Server error codes, `crates/tower-core/src/error.rs`.
enum TowerErrorCode {
  notFound,
  conflict,
  timeout,
  driver,
  invalid,
  unauthorized,
  machineOffline,
  unknown;

  static TowerErrorCode fromJson(String? v) => TowerErrorCode.values
      .firstWhere(
        (c) => c.name == v?.replaceAll('_', '-'),
        orElse: () => TowerErrorCode.unknown,
      );
}

/// One server error, decoded from the envelope.
class TowerApiError implements Exception {
  TowerApiError(this.code, this.message, {this.status, this.detail});

  final TowerErrorCode code;
  final String message;
  final int? status;
  final dynamic detail;

  @override
  String toString() => 'tower $code: $message';
}

/// Thrown when the transport below the API fails (tunnel down, SSH
/// dropped). Distinct from [TowerApiError] so the UI can offer a
/// reconnect.
class TowerTransportError implements Exception {
  TowerTransportError(this.message);
  final String message;

  @override
  String toString() => 'transport error: $message';
}

/// REST client bound to one [TowerConnection] and bearer token.
class TowerClient {
  TowerClient(this._conn, this.token);

  final TowerConnection _conn;

  /// The bearer token; mutable so a refetch after 401 can replace it.
  String token;

  /// Raw request hook shared with extension libraries (workflows).
  /// Decode errors; return parsed JSON.
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    try {
      final res = await _conn.http(
        method,
        path,
        body: body,
        query: query,
        headers: {'Authorization': 'Bearer $token'},
      );
      final text = res.body;
      if (res.status >= 400) {
        throw _decodeError(res.status, text);
      }
      return text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    } on TowerApiError {
      rethrow;
    } on TowerTransportError {
      rethrow;
    } catch (e) {
      throw TowerTransportError('$e');
    }
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) =>
      request(method, path, body: body, query: query);

  TowerApiError _decodeError(int status, String text) {
    try {
      final v = jsonDecode(text);
      if (v is Map<String, dynamic> && v['error'] is Map<String, dynamic>) {
        final err = v['error'] as Map<String, dynamic>;
        return TowerApiError(
          TowerErrorCode.fromJson(err['code'] as String?),
          err['message'] as String? ?? 'request failed',
          status: status,
          detail: err['detail'],
        );
      }
    } catch (_) {
      // fall through to the plain envelope below
    }
    return TowerApiError(
      TowerErrorCode.unknown,
      'HTTP $status',
      status: status,
    );
  }

  // ------------------------------------------------------------- fleet

  /// `GET /v1/agents` — every agent seat.
  Future<List<Agent>> agents() async {
    final v = await _request('GET', '/v1/agents');
    return [
      for (final a in (v['agents'] as List<dynamic>? ?? const []))
        Agent.fromJson(a as Map<String, dynamic>),
    ];
  }

  /// `GET /v1/agents/{id}` — name or id.
  Future<Agent> agent(String nameOrId) async {
    final v = await _request('GET', '/v1/agents/$nameOrId');
    return Agent.fromJson(v['agent'] as Map<String, dynamic>);
  }

  /// `GET /v1/agents/{id}/read` — terminal snapshot, ANSI-capable.
  Future<String> readAgent(String nameOrId, {bool ansi = true}) async {
    final v = await _request(
      'GET',
      '/v1/agents/$nameOrId/read',
      query: ansi ? {'format': 'ansi'} : null,
    );
    return v['output'] as String? ?? '';
  }

  /// `POST /v1/agents/{id}/prompt` — send a prompt.
  Future<void> prompt(String nameOrId, String text) =>
      _request('POST', '/v1/agents/$nameOrId/prompt', body: {'text': text});

  /// `POST /v1/agents/{id}/interrupt` — ctrl+c.
  Future<void> interrupt(String nameOrId) =>
      _request('POST', '/v1/agents/$nameOrId/interrupt');

  // ------------------------------------------------------------- inbox

  /// `GET /v1/messages?to=me&status=pending` — the operator inbox,
  /// exactly what `tower inbox` calls.
  Future<List<Message>> inbox() async {
    final v = await _request(
      'GET',
      '/v1/messages',
      query: {'to': 'me', 'status': 'pending'},
    );
    return [
      for (final m in (v['messages'] as List<dynamic>? ?? const []))
        Message.fromJson(m as Map<String, dynamic>),
    ];
  }

  /// `POST /v1/messages/{id}/respond` — answer a question (text part)
  /// or an approval (`approve`).
  Future<void> respond(String id, {String? answer, bool? approve}) {
    final body = <String, dynamic>{};
    if (answer != null) {
      body['parts'] = [
        <String, dynamic>{'text': answer},
      ];
    }
    if (approve != null) body['approve'] = approve;
    return _request('POST', '/v1/messages/$id/respond', body: body);
  }

  /// `POST /v1/messages/{id}/dismiss` — close without answering.
  Future<void> dismiss(String id) =>
      _request('POST', '/v1/messages/$id/dismiss');

  // ------------------------------------------------------------- jobs

  /// `GET /v1/tasks`, optionally filtered by state.
  Future<List<Task>> tasks({List<String>? states}) async {
    final v = await _request(
      'GET',
      '/v1/tasks',
      query: states == null || states.isEmpty
          ? null
          : {'state': states.join(',')},
    );
    return [
      for (final t in (v['tasks'] as List<dynamic>? ?? const []))
        Task.fromJson(t as Map<String, dynamic>),
    ];
  }

  /// `GET /v1/tasks/{id}` — job detail plus trail.
  Future<TaskDetail> task(String id) async {
    final v = await _request('GET', '/v1/tasks/$id');
    return TaskDetail(
      Task.fromJson(v['task'] as Map<String, dynamic>),
      [
        for (final e in (v['trail'] as List<dynamic>? ?? const []))
          TowerEvent.fromJson(e as Map<String, dynamic>),
      ],
    );
  }

  /// `POST /v1/tasks` — queue a job, optionally pre-assigned.
  /// Returns the task plus reservation info when it waits.
  Future<TaskCreateResult> createTask(CreateTaskBody body) async {
    final v = await _request('POST', '/v1/tasks', body: body.toJson());
    return TaskCreateResult(
      Task.fromJson(v['task'] as Map<String, dynamic>),
      WaitingInfo.fromJson(v['waiting'] as Map<String, dynamic>?),
    );
  }

  /// `POST /v1/tasks/{id}/assign` — dispatch to an agent; a busy agent
  /// reserves the job.
  Future<TaskCreateResult> assignTask(String id, String agent) async {
    final v = await _request(
      'POST',
      '/v1/tasks/$id/assign',
      body: {'to': agent},
    );
    return TaskCreateResult(
      Task.fromJson(v['task'] as Map<String, dynamic>),
      WaitingInfo.fromJson(v['waiting'] as Map<String, dynamic>?),
    );
  }

  /// `POST /v1/tasks/{id}/release` — back to the queue.
  Future<void> releaseTask(String id, {String? reason}) =>
      _request('POST', '/v1/tasks/$id/release', body: {'reason': reason});

  /// `POST /v1/tasks/{id}/cancel` — interrupts the owner.
  Future<void> cancelTask(String id) =>
      _request('POST', '/v1/tasks/$id/cancel');

  /// `GET /v1/events` — the live feed. The server batches events into
  /// `tower-batch` SSE frames whose data is newline-joined `Event` JSON.
  /// [exclude] is the server filter syntax, e.g. `type:agent.output`.
  Stream<TowerEvent> events({String? exclude}) => _conn
      .sse(
        '/v1/events',
        query: {'exclude': ?exclude},
        headers: {'Authorization': 'Bearer $token'},
      )
      .where((f) => f.event == 'tower-batch')
      // Plain transforms, not async*: cancel reaches the socket at once.
      .expand(
        (f) => f.data
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .map(
              (l) => TowerEvent.fromJson(jsonDecode(l) as Map<String, dynamic>),
            ),
      );
}

/// Body of `POST /v1/tasks`.
class CreateTaskBody {
  CreateTaskBody({
    required this.title,
    this.description,
    this.priority,
    this.tags,
    this.assign,
    this.notBefore,
    this.leaseS,
    this.preRun,
    this.postRun,
  });

  final String title;
  final String? description;
  final int? priority;
  final List<String>? tags;
  final String? assign;
  final DateTime? notBefore;
  final int? leaseS;
  final String? preRun;
  final String? postRun;

  Map<String, dynamic> toJson() => {
    'title': title,
    if (description != null) 'description': description,
    if (priority != null) 'priority': priority,
    if (tags != null) 'tags': tags,
    if (assign != null) 'assign': assign,
    if (notBefore != null)
      'not_before': notBefore!.millisecondsSinceEpoch,
    if (leaseS != null) 'lease_s': leaseS,
    if (preRun != null) 'pre_run': preRun,
    if (postRun != null) 'post_run': postRun,
  };
}

/// `{task, trail}` from `GET /v1/tasks/{id}`.
class TaskDetail {
  const TaskDetail(this.task, this.trail);
  final Task task;
  final List<TowerEvent> trail;
}

/// `{task, waiting}` from create and assign.
class TaskCreateResult {
  const TaskCreateResult(this.task, this.waiting);
  final Task task;
  final WaitingInfo waiting;
}
