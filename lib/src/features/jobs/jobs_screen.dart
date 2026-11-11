/// Jobs screen: the open queue and the most recent closed jobs, live
/// from `GET /v1/tasks`.
library;

import 'package:flutter/material.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../common/live_resource.dart';

/// How many closed jobs to show under the queue (herdr shows ten).
const _closedShown = 10;

class JobsData {
  const JobsData(this.open, this.closed, this.agentNames);

  final List<Task> open;
  final List<Task> closed;
  final Map<String, String> agentNames;
}

class JobsScreen extends StatelessWidget {
  const JobsScreen({super.key, required this.client, required this.feed});

  final TowerClient client;
  final LiveFeed feed;

  @override
  Widget build(BuildContext context) => LiveResource<JobsData>(
    feed: feed,
    kinds: const ['task.'],
    load: () async {
      final (tasks, agents) = await (client.tasks(), client.agents()).wait;
      final open = tasks.where((t) => t.state.isOpen).toList()
        ..sort((a, b) {
          final p = b.priority.compareTo(a.priority);
          return p != 0 ? p : a.createdAt.compareTo(b.createdAt);
        });
      final closed = tasks.where((t) => !t.state.isOpen).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return JobsData(
        open,
        closed.take(_closedShown).toList(),
        {for (final a in agents) a.id: a.name},
      );
    },
    builder: (context, data) => ListView(
      children: [
        _Header('Queue (${data.open.length})'),
        if (data.open.isEmpty)
          const ListTile(title: Text('No open jobs.'))
        else
          for (final t in data.open) _TaskTile(t, data.agentNames),
        if (data.closed.isNotEmpty) ...[
          const _Header('Recently closed'),
          for (final t in data.closed) _TaskTile(t, data.agentNames),
        ],
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

class _TaskTile extends StatelessWidget {
  const _TaskTile(this.task, this.names);

  final Task task;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final owner = task.agentId == null
        ? null
        : names[task.agentId] ?? task.agentId;
    return ListTile(
      title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          'p${task.priority}',
          ?owner,
          ...task.tags,
          timeAgo(task.updatedAt),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: StatePill(task.state.name, _color(task.state)),
    );
  }

  static Color _color(TaskState s) => switch (s) {
    TaskState.queued => Colors.grey,
    TaskState.assigned => Colors.teal,
    TaskState.working => Colors.blue,
    TaskState.inputRequired => Colors.orange,
    TaskState.completed => Colors.green,
    TaskState.failed || TaskState.rejected => Colors.red,
    TaskState.canceled => Colors.blueGrey,
  };
}
