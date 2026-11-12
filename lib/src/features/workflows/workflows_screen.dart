/// Workflows screen: definitions and recent runs, live from
/// `GET /v1/workflows` and `GET /v1/runs`.
library;

import 'package:flutter/material.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../../api/tower_workflows.dart';
import '../common/actions.dart';
import '../common/live_resource.dart';
import 'run_detail_screen.dart';

/// How many runs to show (the server returns them newest first).
const _runsShown = 20;

class WorkflowsData {
  const WorkflowsData(this.workflows, this.runs);

  final List<Workflow> workflows;
  final List<WorkflowRun> runs;
}

class WorkflowsScreen extends StatelessWidget {
  const WorkflowsScreen({super.key, required this.client, required this.feed});

  final TowerClient client;
  final LiveFeed feed;

  @override
  Widget build(BuildContext context) => LiveResource<WorkflowsData>(
    feed: feed,
    kinds: const ['workflow.'],
    load: () async {
      final (workflows, runs) = await (client.workflows(), client.runs()).wait;
      workflows.sort((a, b) => a.name.compareTo(b.name));
      return WorkflowsData(workflows, runs.take(_runsShown).toList());
    },
    builder: (context, data) => ListView(
      children: [
        const _Header('Workflows'),
        if (data.workflows.isEmpty)
          const ListTile(title: Text('No workflows.'))
        else
          for (final w in data.workflows)
            _WorkflowTile(
              w,
              onTap: () => showActionSheet(
                context,
                RunWorkflowSheet(client: client, workflow: w),
              ),
            ),
        const _Header('Recent runs'),
        if (data.runs.isEmpty)
          const ListTile(title: Text('No runs yet.'))
        else
          for (final r in data.runs)
            _RunTile(
              r,
              onTap: () => openPage(
                context,
                RunDetailScreen(
                  client: client,
                  feed: feed,
                  runId: r.id,
                  title: r.workflowName,
                ),
              ),
            ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _WorkflowTile extends StatelessWidget {
  const _WorkflowTile(this.workflow, {required this.onTap});

  final Workflow workflow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    title: Text(workflow.name),
    subtitle: workflow.description == null
        ? null
        : Text(
            workflow.description!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
    trailing: workflow.enabled
        ? (workflow.openRuns > 0
              ? StatePill('${workflow.openRuns} running', Colors.blue)
              : null)
        : const StatePill('disabled', Colors.grey),
  );
}

class _RunTile extends StatelessWidget {
  const _RunTile(this.run, {required this.onTap});

  final WorkflowRun run;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    title: Text(run.workflowName),
    subtitle: Text(
      [timeAgo(run.createdAt), ?run.error].join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: StatePill(run.state.name, runStateColor(run.state)),
  );
}

/// Start a run: `POST /v1/workflows/{name}/runs`. The inputs come from
/// the workflow definition (`GET /v1/workflows/{name}`); required ones
/// must be filled.
class RunWorkflowSheet extends StatefulWidget {
  const RunWorkflowSheet({
    super.key,
    required this.client,
    required this.workflow,
  });

  final TowerClient client;
  final Workflow workflow;

  @override
  State<RunWorkflowSheet> createState() => _RunWorkflowSheetState();
}

class _RunWorkflowSheetState extends State<RunWorkflowSheet> with ActionState {
  late final Future<WorkflowDetail> _detail = widget.client.workflow(
    widget.workflow.name,
  );
  final _fields = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _start(List<WorkflowInputSpec> specs) {
    final input = <String, String>{};
    for (final s in specs) {
      final v = _fields[s.name]?.text.trim() ?? '';
      if (v.isEmpty) {
        if (s.required) {
          setState(() => error = '"${s.name}" is required.');
          return;
        }
      } else {
        input[s.name] = v;
      }
    }
    perform(() async {
      final run = await widget.client.runWorkflow(widget.workflow.name, input);
      return 'Started ${widget.workflow.name} (${run.state.name})';
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<WorkflowDetail>(
    future: _detail,
    builder: (context, snap) {
      final title = Text(
        'Run ${widget.workflow.name}',
        style: Theme.of(context).textTheme.titleMedium,
      );
      if (snap.hasError) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            title,
            const SizedBox(height: 12),
            Text(describeError(snap.error!)),
          ],
        );
      }
      final detail = snap.data;
      if (detail == null) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final specs = detail.inputs;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          title,
          if (!widget.workflow.enabled)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('This workflow is disabled.'),
            ),
          const SizedBox(height: 12),
          if (specs.isEmpty) const Text('This workflow takes no inputs.'),
          for (final s in specs)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _fields.putIfAbsent(
                  s.name,
                  TextEditingController.new,
                ),
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: s.required ? '${s.name} *' : s.name,
                  helperText: s.description,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          errorStrip(),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: busy || !widget.workflow.enabled
                  ? null
                  : () => _start(specs),
              child: Text(busy ? 'Starting…' : 'Run'),
            ),
          ),
        ],
      );
    },
  );
}
