/// Workflows screen: definitions and recent runs, live from
/// `GET /v1/workflows` and `GET /v1/runs`.
library;

import 'package:flutter/material.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../../api/tower_workflows.dart';
import '../common/live_resource.dart';

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
          for (final w in data.workflows) _WorkflowTile(w),
        const _Header('Recent runs'),
        if (data.runs.isEmpty)
          const ListTile(title: Text('No runs yet.'))
        else
          for (final r in data.runs) _RunTile(r),
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
  const _WorkflowTile(this.workflow);

  final Workflow workflow;

  @override
  Widget build(BuildContext context) => ListTile(
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
  const _RunTile(this.run);

  final WorkflowRun run;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(run.workflowName),
    subtitle: Text(
      [timeAgo(run.createdAt), ?run.error].join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: StatePill(run.state.name, _color(run.state)),
  );

  static Color _color(RunState s) => switch (s) {
    RunState.waiting => Colors.orange,
    RunState.running => Colors.blue,
    RunState.completed => Colors.green,
    RunState.failed => Colors.red,
    RunState.canceled => Colors.blueGrey,
  };
}
