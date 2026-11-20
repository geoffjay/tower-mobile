/// Workflows screen: definitions and recent runs in segmented M3E cards,
/// live from `GET /v1/workflows` and `GET /v1/runs`. Starting a workflow
/// opens its live [RunDetailScreen] immediately.
library;

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

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

  Future<void> _startWorkflow(BuildContext context, Workflow w) async {
    final messenger = ScaffoldMessenger.of(context);
    final run = await showTypedSheet<WorkflowRun>(
      context,
      RunWorkflowSheet(client: client, workflow: w),
    );
    if (run == null || !context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Started ${w.name} (${run.state.name})')),
    );
    await openPage(
      context,
      RunDetailScreen(
        client: client,
        feed: feed,
        runId: run.id,
        title: run.workflowName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LiveResource<WorkflowsData>(
    feed: feed,
    kinds: const ['workflow.'],
    load: () async {
      final (workflows, runs) = await (client.workflows(), client.runs()).wait;
      workflows.sort((a, b) => a.name.compareTo(b.name));
      return WorkflowsData(workflows, runs.take(_runsShown).toList());
    },
    builder: (context, data) {
      final scheme = Theme.of(context).colorScheme;
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionHeader('Workflows (${data.workflows.length})'),
          if (data.workflows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'No workflows defined on this host.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else
            SegmentedCardList(
              itemCount: data.workflows.length,
              itemBuilder: (context, i) {
                final w = data.workflows[i];
                final active = w.openRuns > 0;
                final tone = !w.enabled
                    ? StatusTone.neutral
                    : (active ? StatusTone.active : StatusTone.positive);
                return M3EListItem(
                  leading: StatusLeadingDot(tone),
                  headline: w.name,
                  supportingText: w.description,
                  trailing: !w.enabled
                      ? const StatePill('disabled', StatusTone.neutral)
                      : (active
                            ? StatePill('${w.openRuns} running', tone)
                            : const Icon(Icons.play_arrow_rounded)),
                  onTap: () => _startWorkflow(context, w),
                );
              },
            ),
          SectionHeader('Recent runs (${data.runs.length})'),
          if (data.runs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'No runs yet.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else
            SegmentedCardList(
              itemCount: data.runs.length,
              itemBuilder: (context, i) {
                final r = data.runs[i];
                final tone = runStateTone(r.state);
                return M3EListItem(
                  leading: StatusLeadingDot(tone),
                  headline: r.workflowName,
                  supportingText: [timeAgo(r.createdAt), ?r.error].join(' · '),
                  trailing: StatePill(r.state.name, tone),
                  onTap: () => openPage(
                    context,
                    RunDetailScreen(
                      client: client,
                      feed: feed,
                      runId: r.id,
                      title: r.workflowName,
                    ),
                  ),
                );
              },
            ),
        ],
      );
    },
  );
}

/// Start a run: `POST /v1/workflows/{name}/runs`. Pops with the created
/// [WorkflowRun] so the caller can navigate straight to [RunDetailScreen].
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

  Future<void> _start(List<WorkflowInputSpec> specs) async {
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
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final run = await widget.client.runWorkflow(widget.workflow.name, input);
      if (mounted) Navigator.of(context).pop(run);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<WorkflowDetail>(
    future: _detail,
    builder: (context, snap) {
      final title = Text(
        'Run ${widget.workflow.name}',
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
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
          child: Center(child: M3ELoadingIndicator()),
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
              child: StatePill('disabled', StatusTone.neutral),
            ),
          const SizedBox(height: 12),
          if (specs.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'This workflow takes no inputs.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
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
            child: M3EButton.icon(
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              onPressed: busy || !widget.workflow.enabled
                  ? null
                  : () => _start(specs),
              label: Text(busy ? 'Starting…' : 'Run workflow'),
            ),
          ),
        ],
      );
    },
  );
}
