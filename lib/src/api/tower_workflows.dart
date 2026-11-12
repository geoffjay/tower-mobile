/// Workflow routes: `GET /v1/workflows`, `GET /v1/workflows/{name}`,
/// `POST /v1/workflows/{name}/runs`, `GET /v1/runs`, `GET /v1/runs/{id}`,
/// `POST /v1/runs/{id}/cancel`.
library;

import 'tower_client.dart';
import 'models.dart';

/// Extensions of [TowerClient] for the workflow surface. Kept separate
/// from the core client to mirror the server's split between
/// `tasks.rs` and `workflows/mod.rs`.
extension TowerClientWorkflows on TowerClient {
  /// `GET /v1/workflows` — list with `open_runs` per row.
  Future<List<Workflow>> workflows() async {
    final v = await request('GET', '/v1/workflows');
    return [
      for (final w in (v['workflows'] as List<dynamic>? ?? const []))
        Workflow.fromJson(w as Map<String, dynamic>),
    ];
  }

  /// `GET /v1/workflows/{name}` — definition, inputs, schedules, runs.
  Future<WorkflowDetail> workflow(String nameOrId) async {
    final v = await request('GET', '/v1/workflows/$nameOrId');
    return WorkflowDetail(
      Workflow.fromJson(v['workflow'] as Map<String, dynamic>),
      _inputSpecs(v['definition']),
      [
        for (final r in (v['runs'] as List<dynamic>? ?? const []))
          WorkflowRun.fromJson(r as Map<String, dynamic>),
      ],
    );
  }

  /// `POST /v1/workflows/{name}/runs` — start a run. The body is optional
  /// on the server; we always send `{input: {...}}`.
  Future<WorkflowRun> runWorkflow(
    String name,
    Map<String, String> input,
  ) async {
    final v = await request(
      'POST',
      '/v1/workflows/$name/runs',
      body: {'input': input},
    );
    return WorkflowRun.fromJson(v['run'] as Map<String, dynamic>);
  }

  /// `GET /v1/runs?workflow=&state=&limit=` — newest first.
  Future<List<WorkflowRun>> runs({
    String? workflow,
    List<String>? states,
  }) async {
    final v = await request(
      'GET',
      '/v1/runs',
      query: {
        'workflow': ?workflow,
        if (states != null && states.isNotEmpty) 'state': states.join(','),
      },
    );
    return [
      for (final r in (v['runs'] as List<dynamic>? ?? const []))
        WorkflowRun.fromJson(r as Map<String, dynamic>),
    ];
  }

  /// `GET /v1/runs/{id}` — run with steps and `waiting_for`.
  Future<RunDetail> run(String id) async {
    final v = await request('GET', '/v1/runs/$id');
    return RunDetail(
      WorkflowRun.fromJson(v['run'] as Map<String, dynamic>),
      [
        for (final s in (v['steps'] as List<dynamic>? ?? const []))
          WorkflowStep.fromJson(s as Map<String, dynamic>),
      ],
      [
        for (final w in (v['waiting_for'] as List<dynamic>? ?? const []))
          (w as Map<String, dynamic>)['agent'] as String? ?? '',
      ],
    );
  }

  /// `POST /v1/runs/{id}/cancel` — cancel a waiting or running run.
  Future<void> cancelRun(String id) => request('POST', '/v1/runs/$id/cancel');
}

/// Parse the input declarations from a workflow `definition` JSON.
/// The server stores the parsed TOML; inputs live under
/// `definition.inputs` as `{name: {required, description?}}`
/// [INFERENCE: exact shape read at M3 against a live server; the herdr
/// app reads the same field for its `missingInputs` check].
List<WorkflowInputSpec> _inputSpecs(dynamic definition) {
  if (definition is! Map<String, dynamic>) return const [];
  final inputs = definition['inputs'];
  if (inputs is! Map<String, dynamic>) return const [];
  return [
    for (final e in inputs.entries)
      if (e.value is Map<String, dynamic>)
        WorkflowInputSpec.fromJson(<String, dynamic>{
          'name': e.key,
          ...(e.value as Map<String, dynamic>),
        }),
  ];
}

/// `{workflow, definition, schedules, runs}` from workflow detail.
class WorkflowDetail {
  const WorkflowDetail(this.workflow, this.inputs, this.runs);
  final Workflow workflow;
  final List<WorkflowInputSpec> inputs;
  final List<WorkflowRun> runs;
}

/// `{run, steps, waiting_for}` from `GET /v1/runs/{id}`.
class RunDetail {
  const RunDetail(this.run, this.steps, this.waitingFor);
  final WorkflowRun run;
  final List<WorkflowStep> steps;
  final List<String> waitingFor;
}
