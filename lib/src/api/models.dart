/// Domain models mirroring `tower-core` (`crates/tower-core/src/objects.rs`).
///
/// Field names match the server's JSON verbatim. Timestamps are ms-epoch
/// ints; ids are ULID strings. See the knowledge base entry
/// `concepts/tower-api-surface.md` for the wire contract.
library;

import 'dart:convert';

/// `result` is free-form JSON: tower agents store an object (usually with
/// a `summary` string), older rows a plain string. Show the summary when
/// there is one, otherwise the JSON text.
String? _resultText(Object? v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is Map<String, dynamic> && v['summary'] is String) {
    return v['summary'] as String;
  }
  return jsonEncode(v);
}

/// `AgentState`: `unknown | launching | idle | working | blocked | done | dead`.
enum AgentState {
  unknown,
  launching,
  idle,
  working,
  blocked,
  done,
  dead;

  static AgentState fromJson(String? v) => AgentState.values.firstWhere(
    (s) => s.name == v,
    orElse: () => AgentState.unknown,
  );
}

/// `TaskState`:
/// `queued | assigned | working | input-required | completed | failed |
/// canceled | rejected`.
enum TaskState {
  queued,
  assigned,
  working,
  inputRequired,
  completed,
  failed,
  canceled,
  rejected;

  static TaskState fromJson(String? v) {
    final name = v?.replaceAll('-', '_');
    return TaskState.values.firstWhere(
      (s) => s.name == name,
      orElse: () => TaskState.queued,
    );
  }

  /// Open jobs, the rows the Jobs screen shows in its queue section.
  /// Mirrors the herdr jobs panel's open set (`jobs.js:20`).
  static const openStates = {
    TaskState.queued,
    TaskState.assigned,
    TaskState.working,
    TaskState.inputRequired,
  };

  bool get isOpen => openStates.contains(this);
}

/// `RunState`: `waiting | running | completed | failed | canceled`.
enum RunState {
  waiting,
  running,
  completed,
  failed,
  canceled;

  static RunState fromJson(String? v) => RunState.values.firstWhere(
    (s) => s.name == v,
    orElse: () => RunState.waiting,
  );

  bool get isOpen => this == RunState.waiting || this == RunState.running;
}

/// `StepState`: `pending | ready | running | completed | failed | canceled`.
enum StepState {
  pending,
  ready,
  running,
  completed,
  failed,
  canceled;

  static StepState fromJson(String? v) => StepState.values.firstWhere(
    (s) => s.name == v,
    orElse: () => StepState.pending,
  );
}

/// `MessageKind`:
/// `prompt | question | answer | approval | approval-response | notice |
/// delegation | broadcast`.
enum MessageKind {
  prompt,
  question,
  answer,
  approval,
  approvalResponse,
  notice,
  delegation,
  broadcast;

  static MessageKind fromJson(String? v) {
    final name = v?.replaceAll('-', '_');
    return MessageKind.values.firstWhere(
      (k) => k.name == name,
      orElse: () => MessageKind.notice,
    );
  }
}

/// `MessageStatus`:
/// `pending | delivered | answered | dismissed | expired | failed`.
enum MessageStatus {
  pending,
  delivered,
  answered,
  dismissed,
  expired,
  failed;

  static MessageStatus fromJson(String? v) => MessageStatus.values.firstWhere(
    (s) => s.name == v,
    orElse: () => MessageStatus.pending,
  );
}

/// `Agent` row, `GET /v1/agents`.
class Agent {
  const Agent({
    required this.id,
    required this.name,
    required this.kind,
    required this.machineId,
    required this.state,
    required this.desiredState,
    required this.permissions,
    required this.adopted,
    required this.createdAt,
    required this.updatedAt,
    this.paneId,
    this.workdir,
    this.worktree,
    this.model,
    this.args = const [],
  });

  final String id;
  final String name;
  final String kind;
  final String machineId;
  final String? paneId;
  final String? workdir;
  final String? worktree;
  final AgentState state;
  final String desiredState;
  final String permissions;
  final bool adopted;
  final String? model;
  final List<String> args;
  final int createdAt;
  final int updatedAt;

  factory Agent.fromJson(Map<String, dynamic> json) => Agent(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: json['kind'] as String? ?? '',
    machineId: json['machine_id'] as String? ?? 'local',
    paneId: json['pane_id'] as String?,
    workdir: json['workdir'] as String?,
    worktree: json['worktree'] as String?,
    state: AgentState.fromJson(json['state'] as String?),
    desiredState: json['desired_state'] as String? ?? 'running',
    permissions: json['permissions'] as String? ?? 'default',
    adopted: json['adopted'] as bool? ?? false,
    model: json['model'] as String?,
    args: (json['args'] as List<dynamic>? ?? const [])
        .map((a) => a as String)
        .toList(),
    createdAt: json['created_at'] as int? ?? 0,
    updatedAt: json['updated_at'] as int? ?? 0,
  );
}

/// A message `Part`; exactly one content field is set. Wire form is
/// camelCase (`mediaType`).
class MessagePart {
  const MessagePart({this.text, this.url, this.data, this.mediaType});

  final String? text;
  final String? url;
  final String? data;
  final String? mediaType;

  factory MessagePart.fromJson(Map<String, dynamic> json) => MessagePart(
    text: json['text'] as String?,
    url: json['url'] as String?,
    data: json['data'] as String?,
    mediaType: json['mediaType'] as String?,
  );

  String get displayText => text ?? url ?? data ?? '';
}

/// `Message` row, `GET /v1/messages`.
class Message {
  const Message({
    required this.id,
    required this.fromKind,
    required this.fromId,
    required this.toKind,
    required this.toId,
    required this.kind,
    required this.status,
    required this.createdAt,
    required this.parts,
    this.taskId,
    this.deadlineAt,
    this.respondedAt,
  });

  final String id;
  final String? taskId;
  final String fromKind;
  final String fromId;
  final String toKind;
  final String toId;
  final MessageKind kind;
  final List<MessagePart> parts;
  final MessageStatus status;
  final int? deadlineAt;
  final int? respondedAt;
  final int createdAt;

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    taskId: json['task_id'] as String?,
    fromKind: json['from_kind'] as String? ?? '',
    fromId: json['from_id'] as String? ?? '',
    toKind: json['to_kind'] as String? ?? '',
    toId: json['to_id'] as String? ?? '',
    kind: MessageKind.fromJson(json['kind'] as String?),
    status: MessageStatus.fromJson(json['status'] as String?),
    parts: (json['parts'] as List<dynamic>? ?? const [])
        .map((p) => MessagePart.fromJson(p as Map<String, dynamic>))
        .toList(),
    deadlineAt: json['deadline_at'] as int?,
    respondedAt: json['responded_at'] as int?,
    createdAt: json['created_at'] as int? ?? 0,
  );

  /// True when the item waits on the operator: question or approval.
  bool get needsAnswer =>
      kind == MessageKind.question || kind == MessageKind.approval;

  String get body =>
      parts.map((p) => p.displayText).where((t) => t.isNotEmpty).join('\n');
}

/// `Task` row, `GET /v1/tasks`.
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.state,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
    required this.leaseS,
    required this.maxAttempts,
    required this.attemptCount,
    required this.tags,
    this.description,
    this.agentId,
    this.ownerId,
    this.targetAgentId,
    this.notBefore,
    this.result,
    this.preRun,
    this.postRun,
    this.hook,
  });

  final String id;
  final String? agentId;
  final String? ownerId;
  final String title;
  final String? description;
  final TaskState state;
  final int priority;
  final List<String> tags;
  final int attemptCount;
  final int maxAttempts;
  final int leaseS;
  final int? notBefore;
  final String? targetAgentId;
  final String? preRun;
  final String? postRun;
  final String? hook;
  final String? result;
  final int createdAt;
  final int updatedAt;

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    agentId: json['agent_id'] as String?,
    ownerId: json['owner_id'] as String?,
    title: json['title'] as String? ?? '',
    description: json['description'] as String?,
    state: TaskState.fromJson(json['state'] as String?),
    priority: json['priority'] as int? ?? 0,
    tags: (json['tags'] as List<dynamic>? ?? const [])
        .map((t) => t as String)
        .toList(),
    attemptCount: json['attempt_count'] as int? ?? 0,
    maxAttempts: json['max_attempts'] as int? ?? 0,
    leaseS: json['lease_s'] as int? ?? 60,
    notBefore: json['not_before'] as int?,
    targetAgentId: json['target_agent_id'] as String?,
    preRun: json['pre_run'] as String?,
    postRun: json['post_run'] as String?,
    hook: json['hook'] as String?,
    result: _resultText(json['result']),
    createdAt: json['created_at'] as int? ?? 0,
    updatedAt: json['updated_at'] as int? ?? 0,
  );
}

/// `Workflow` row, `GET /v1/workflows` (adds `nodes`, `triggers`,
/// `open_runs`).
class Workflow {
  const Workflow({
    required this.id,
    required this.name,
    required this.enabled,
    required this.currentVersion,
    required this.openRuns,
    required this.createdAt,
    required this.updatedAt,
    this.description,
  });

  final String id;
  final String name;
  final String? description;
  final bool enabled;
  final int currentVersion;
  final int openRuns;
  final int createdAt;
  final int updatedAt;

  factory Workflow.fromJson(Map<String, dynamic> json) => Workflow(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    enabled: json['enabled'] as bool? ?? true,
    currentVersion: json['current_version'] as int? ?? 1,
    openRuns: json['open_runs'] as int? ?? 0,
    createdAt: json['created_at'] as int? ?? 0,
    updatedAt: json['updated_at'] as int? ?? 0,
  );
}

/// `WorkflowRun` row, `GET /v1/runs`.
class WorkflowRun {
  const WorkflowRun({
    required this.id,
    required this.workflowName,
    required this.state,
    required this.input,
    required this.createdAt,
    this.workflowId,
    this.result,
    this.error,
    this.endedAt,
  });

  final String id;
  final String? workflowId;
  final String workflowName;
  final RunState state;
  final Map<String, dynamic> input;
  final String? result;
  final String? error;
  final int? endedAt;
  final int createdAt;

  factory WorkflowRun.fromJson(Map<String, dynamic> json) => WorkflowRun(
    id: json['id'] as String,
    workflowId: json['workflow_id'] as String?,
    workflowName: json['workflow_name'] as String? ?? '',
    state: RunState.fromJson(json['state'] as String?),
    input: json['input'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    result: _resultText(json['result']),
    error: json['error'] as String?,
    endedAt: json['ended_at'] as int?,
    createdAt: json['created_at'] as int? ?? 0,
  );
}

/// `WorkflowStep` row, `GET /v1/runs/{id}`.
class WorkflowStep {
  const WorkflowStep({
    required this.id,
    required this.runId,
    required this.nodeId,
    required this.visit,
    required this.state,
    required this.createdAt,
    this.taskId,
    this.agentId,
    this.outcome,
    this.result,
    this.error,
    this.startedAt,
    this.endedAt,
  });

  final String id;
  final String runId;
  final String nodeId;
  final int visit;
  final StepState state;
  final String? taskId;
  final String? agentId;
  final String? outcome;
  final String? result;
  final String? error;
  final int createdAt;
  final int? startedAt;
  final int? endedAt;

  factory WorkflowStep.fromJson(Map<String, dynamic> json) => WorkflowStep(
    id: json['id'] as String,
    runId: json['run_id'] as String,
    nodeId: json['node_id'] as String,
    visit: json['visit'] as int? ?? 1,
    state: StepState.fromJson(json['state'] as String?),
    taskId: json['task_id'] as String?,
    agentId: json['agent_id'] as String?,
    outcome: json['outcome'] as String?,
    result: _resultText(json['result']),
    error: json['error'] as String?,
    createdAt: json['created_at'] as int? ?? 0,
    startedAt: json['started_at'] as int?,
    endedAt: json['ended_at'] as int?,
  );
}

/// `Event` off the SSE feed: `seq, ts, kind, subject_type?, subject_id?,
/// payload`.
class TowerEvent {
  const TowerEvent({
    required this.seq,
    required this.ts,
    required this.kind,
    this.subjectType,
    this.subjectId,
    this.payload = const {},
  });

  final int seq;
  final int ts;
  final String kind;
  final String? subjectType;
  final String? subjectId;
  final Map<String, dynamic> payload;

  factory TowerEvent.fromJson(Map<String, dynamic> json) => TowerEvent(
    seq: json['seq'] as int,
    ts: json['ts'] as int? ?? 0,
    kind: json['kind'] as String,
    subjectType: json['subject_type'] as String?,
    subjectId: json['subject_id'] as String?,
    payload:
        json['payload'] as Map<String, dynamic>? ?? const <String, dynamic>{},
  );
}

/// Assignment reservation info from `POST /v1/tasks` and
/// `POST /v1/tasks/{id}/assign` responses: `{task, waiting}`.
class WaitingInfo {
  const WaitingInfo({required this.reason});

  final String reason;

  factory WaitingInfo.fromJson(Map<String, dynamic>? json) =>
      WaitingInfo(reason: json == null ? '' : json['reason'] as String? ?? '');
}

/// A workflow `definition`'s input declaration, from
/// `GET /v1/workflows/{name}`. Shape (herdr `missingInputs` contract):
/// `[{name, required, description?}, …]`.
class WorkflowInputSpec {
  const WorkflowInputSpec({
    required this.name,
    required this.required,
    this.description,
  });

  final String name;
  final bool required;
  final String? description;

  factory WorkflowInputSpec.fromJson(Map<String, dynamic> json) =>
      WorkflowInputSpec(
        name: json['name'] as String,
        required: json['required'] as bool? ?? false,
        description: json['description'] as String?,
      );
}
