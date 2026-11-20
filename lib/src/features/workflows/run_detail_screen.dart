/// Run detail: follow one workflow run step by step, live, and cancel
/// it in place while open.
library;

import 'dart:async';

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart' hide StepState;

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../../api/tower_workflows.dart';
import '../common/actions.dart';
import '../common/live_resource.dart';

StatusTone runStateTone(RunState s) => switch (s) {
  RunState.waiting => StatusTone.warning,
  RunState.running => StatusTone.active,
  RunState.completed => StatusTone.positive,
  RunState.failed => StatusTone.danger,
  RunState.canceled => StatusTone.neutral,
};

StatusTone _stepTone(StepState s) => switch (s) {
  StepState.pending || StepState.canceled => StatusTone.neutral,
  StepState.ready => StatusTone.warning,
  StepState.running => StatusTone.active,
  StepState.completed => StatusTone.positive,
  StepState.failed => StatusTone.danger,
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
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom;
    return Scaffold(
      appBar: M3EAppBar.top(
        automaticallyImplyLeading: true,
        title: Text(title),
      ),
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
        refreshableBuilder: (context, view, refresh) {
          final run = view.detail.run;
          final names = view.agentNames;
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: EdgeInsets.only(bottom: 32 + bottomSafe),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StatePill(
                    run.state.name,
                    runStateTone(run.state),
                    showDot: true,
                  ),
                ),
              ),
              InfoCard(
                children: [
                  InfoRow('Started', timeAgo(run.createdAt)),
                  if (run.endedAt != null)
                    InfoRow('Ended', timeAgo(run.endedAt!)),
                  if (run.input.isNotEmpty)
                    InfoRow(
                      'Input',
                      run.input.entries
                          .map((e) => '${e.key}=${e.value}')
                          .join('\n'),
                    ),
                  if (view.detail.waitingFor.isNotEmpty)
                    InfoRow(
                      'Waiting for',
                      view.detail.waitingFor
                          .map((a) => names[a] ?? a)
                          .join(', '),
                    ),
                  if (run.error != null) InfoRow('Error', run.error!),
                ],
              ),
              if (run.result != null) ...[
                const SectionHeader('Result'),
                ContentCard(run.result!),
              ],
              SectionHeader('Steps (${view.detail.steps.length})'),
              if (view.detail.steps.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'No steps started yet.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              else
                SegmentedCardList(
                  itemCount: view.detail.steps.length,
                  itemBuilder: (context, i) {
                    final step = view.detail.steps[i];
                    final agent = step.agentId == null
                        ? null
                        : names[step.agentId] ?? step.agentId;
                    final detail = [
                      ?agent,
                      if (step.outcome != null) 'outcome ${step.outcome}',
                      if (step.startedAt != null) timeAgo(step.startedAt!),
                      ?step.error,
                    ].join(' · ');
                    final tone = _stepTone(step.state);
                    return M3EListItem(
                      leading: StatusLeadingDot(tone),
                      headline: step.visit > 1
                          ? '${step.nodeId} (x${step.visit})'
                          : step.nodeId,
                      supportingText: detail.isEmpty ? null : detail,
                      trailing: StatePill(step.state.name, tone),
                    );
                  },
                ),
              if (run.state.isOpen) ...[
                const SectionHeader('Actions'),
                _CancelRun(client: client, run: run, onCanceled: refresh),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Cancel an open run (`POST /v1/runs/{id}/cancel`) in place, two presses
/// with a 3s auto-reset timer.
class _CancelRun extends StatefulWidget {
  const _CancelRun({
    required this.client,
    required this.run,
    required this.onCanceled,
  });

  final TowerClient client;
  final WorkflowRun run;
  final Future<void> Function() onCanceled;

  @override
  State<_CancelRun> createState() => _CancelRunState();
}

class _CancelRunState extends State<_CancelRun> with ActionState {
  var _confirm = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _cancel() {
    if (!_confirm) {
      _reset?.cancel();
      setState(() => _confirm = true);
      _reset = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _confirm = false);
      });
      return;
    }
    _reset?.cancel();
    setState(() => _confirm = false);
    performInline(() async {
      await widget.client.cancelRun(widget.run.id);
      return 'Run canceled';
    }, onSuccess: widget.onCanceled);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          errorStrip(),
          M3EButton(
            style: _confirm ? M3EButtonStyle.filled : M3EButtonStyle.tonal,
            decoration: M3EButtonDecoration(
              backgroundColor: _confirm
                  ? WidgetStatePropertyAll(scheme.error)
                  : WidgetStatePropertyAll(scheme.errorContainer),
              foregroundColor: WidgetStatePropertyAll(
                _confirm ? scheme.onError : scheme.onErrorContainer,
              ),
            ),
            onPressed: busy ? null : _cancel,
            child: Text(_confirm ? 'Tap again to cancel run' : 'Cancel run'),
          ),
        ],
      ),
    );
  }
}
