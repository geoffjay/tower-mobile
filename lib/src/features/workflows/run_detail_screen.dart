/// Run detail: follow one workflow run step by step, live, and cancel
/// it while it is open.
library;

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart' hide StepState;

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../../api/tower_workflows.dart';
import '../common/actions.dart';
import '../common/live_resource.dart';

Color runStateColor(RunState s) => switch (s) {
  RunState.waiting => Colors.orange,
  RunState.running => Colors.blue,
  RunState.completed => Colors.green,
  RunState.failed => Colors.red,
  RunState.canceled => Colors.blueGrey,
};

Color _stepColor(StepState s) => switch (s) {
  StepState.pending => Colors.grey,
  StepState.ready => Colors.orange,
  StepState.running => Colors.blue,
  StepState.completed => Colors.green,
  StepState.failed => Colors.red,
  StepState.canceled => Colors.blueGrey,
};

class _RunView {
  const _RunView(this.detail, this.agentNames);

  final RunDetail detail;
  final Map<String, String> agentNames;
}

class RunDetailScreen extends StatelessWidget {
  const RunDetailScreen({
    super.key,
    required this.client,
    required this.feed,
    required this.runId,
    required this.title,
  });

  final TowerClient client;
  final LiveFeed feed;
  final String runId;

  /// The workflow name, shown while the run loads.
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: M3EAppBar.top(automaticallyImplyLeading: true, title: Text(title)),
    body: LiveResource<_RunView>(
      feed: feed,
      kinds: const ['workflow.'],
      load: () async {
        final (detail, agents) = await (
          client.run(runId),
          client.agents(),
        ).wait;
        return _RunView(detail, {for (final a in agents) a.id: a.name});
      },
      builder: (context, view) {
        final run = view.detail.run;
        final names = view.agentNames;
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatePill(run.state.name, runStateColor(run.state)),
              ),
            ),
            InfoRow('Started', timeAgo(run.createdAt)),
            if (run.endedAt != null) InfoRow('Ended', timeAgo(run.endedAt!)),
            if (run.input.isNotEmpty)
              InfoRow(
                'Input',
                run.input.entries.map((e) => '${e.key}=${e.value}').join('\n'),
              ),
            if (view.detail.waitingFor.isNotEmpty)
              InfoRow(
                'Waiting for',
                view.detail.waitingFor.map((a) => names[a] ?? a).join(', '),
              ),
            if (run.error != null) InfoRow('Error', run.error!),
            if (run.result != null) InfoRow('Result', run.result!),
            SectionHeader('Steps (${view.detail.steps.length})'),
            if (view.detail.steps.isEmpty)
              const ListTile(title: Text('No steps yet.')),
            for (final s in view.detail.steps) _StepTile(s, names),
            if (run.state.isOpen) ...[
              const SectionHeader('Actions'),
              _CancelRun(client: client, run: run),
            ],
          ],
        );
      },
    ),
  );
}

class _StepTile extends StatelessWidget {
  const _StepTile(this.step, this.names);

  final WorkflowStep step;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final agent = step.agentId == null
        ? null
        : names[step.agentId] ?? step.agentId;
    final detail = [
      ?agent,
      if (step.outcome != null) 'outcome ${step.outcome}',
      if (step.startedAt != null) timeAgo(step.startedAt!),
      ?step.error,
    ].join(' · ');
    return ListTile(
      title: Text(
        step.visit > 1 ? '${step.nodeId} (x${step.visit})' : step.nodeId,
      ),
      subtitle: detail.isEmpty ? null : Text(detail, maxLines: 3),
      trailing: StatePill(step.state.name, _stepColor(step.state)),
    );
  }
}

/// Cancel an open run (`POST /v1/runs/{id}/cancel`), two presses.
class _CancelRun extends StatefulWidget {
  const _CancelRun({required this.client, required this.run});

  final TowerClient client;
  final WorkflowRun run;

  @override
  State<_CancelRun> createState() => _CancelRunState();
}

class _CancelRunState extends State<_CancelRun> with ActionState {
  var _confirm = false;

  void _cancel() {
    if (!_confirm) {
      setState(() => _confirm = true);
      return;
    }
    perform(() async {
      await widget.client.cancelRun(widget.run.id);
      return 'Run canceled';
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        errorStrip(),
        M3EButton(
          style: M3EButtonStyle.tonal,
          decoration: M3EButtonDecoration(
            foregroundColor: WidgetStatePropertyAll(
              Theme.of(context).colorScheme.error,
            ),
          ),
          onPressed: busy ? null : _cancel,
          child: Text(_confirm ? 'Tap again to cancel run' : 'Cancel run'),
        ),
      ],
    ),
  );
}
