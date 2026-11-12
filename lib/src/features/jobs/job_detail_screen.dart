/// Job detail: facts, result, the event trail, and the job's actions
/// (assign, release, cancel).
library;

import 'package:flutter/material.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../common/actions.dart';
import '../common/live_resource.dart';
import 'jobs_screen.dart' show taskStateColor, waitingNote;

class _JobView {
  const _JobView(this.detail, this.agents);

  final TaskDetail detail;
  final List<Agent> agents;
}

class JobDetailScreen extends StatelessWidget {
  const JobDetailScreen({
    super.key,
    required this.client,
    required this.feed,
    required this.taskId,
  });

  final TowerClient client;
  final LiveFeed feed;
  final String taskId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Job')),
    body: LiveResource<_JobView>(
      feed: feed,
      kinds: const ['task.'],
      load: () async {
        final (detail, agents) = await (
          client.task(taskId),
          client.agents(),
        ).wait;
        agents.sort((a, b) => a.name.compareTo(b.name));
        return _JobView(detail, agents);
      },
      builder: (context, view) {
        final t = view.detail.task;
        final names = {for (final a in view.agents) a.id: a.name};
        final owner = t.ownerId == null ? null : names[t.ownerId] ?? t.ownerId;
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                t.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatePill(t.state.name, taskStateColor(t.state)),
              ),
            ),
            InfoRow('Priority', '${t.priority}'),
            if (owner != null) InfoRow('Owner', owner),
            if (t.tags.isNotEmpty) InfoRow('Tags', t.tags.join(', ')),
            InfoRow('Attempts', '${t.attemptCount} of ${t.maxAttempts}'),
            InfoRow('Created', timeAgo(t.createdAt)),
            InfoRow('Updated', timeAgo(t.updatedAt)),
            if (t.description != null && t.description!.isNotEmpty) ...[
              const SectionHeader('Description'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SelectableText(t.description!),
              ),
            ],
            if (t.result != null) ...[
              const SectionHeader('Result'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SelectableText(t.result!),
              ),
            ],
            const SectionHeader('Actions'),
            _JobActions(client: client, task: t, agents: view.agents),
            SectionHeader('Trail (${view.detail.trail.length})'),
            if (view.detail.trail.isEmpty)
              const ListTile(title: Text('No events yet.')),
            for (final e in view.detail.trail)
              ListTile(
                dense: true,
                title: Text(_describe(e, names)),
                subtitle: Text(timeAgo(e.ts)),
              ),
          ],
        );
      },
    ),
  );

  /// One line for a trail event: `created`, `→ canceled`,
  /// `→ queued · released_by dev-pm`, and so on.
  static String _describe(TowerEvent e, Map<String, String> names) {
    final parts = <String>[];
    final state = e.payload['state'];
    if (state is String) parts.add('→ $state');
    for (final key in const [
      'agent_id',
      'owner_id',
      'to',
      'released_by',
      'reason',
    ]) {
      final v = e.payload[key];
      if (v is String && v.isNotEmpty) parts.add('$key ${names[v] ?? v}');
    }
    final label = e.kind.replaceFirst('task.', '');
    return parts.isEmpty ? label : '$label ${parts.join(' · ')}';
  }
}

/// Assign (`/assign`), release (`/release`) and cancel (`/cancel`, two
/// presses). Only the actions that fit the job's state are offered.
class _JobActions extends StatefulWidget {
  const _JobActions({
    required this.client,
    required this.task,
    required this.agents,
  });

  final TowerClient client;
  final Task task;
  final List<Agent> agents;

  @override
  State<_JobActions> createState() => _JobActionsState();
}

class _JobActionsState extends State<_JobActions> with ActionState {
  String? _agent;
  var _confirmCancel = false;

  Task get _task => widget.task;

  bool get _canAssign =>
      _task.state == TaskState.queued || _task.state == TaskState.assigned;
  bool get _canRelease =>
      _task.ownerId != null &&
      (_task.state == TaskState.assigned ||
          _task.state == TaskState.working ||
          _task.state == TaskState.inputRequired);

  void _assign() {
    final agent = _agent;
    if (agent == null) {
      setState(() => error = 'Pick an agent first.');
      return;
    }
    perform(() async {
      final r = await widget.client.assignTask(_task.id, agent);
      return 'Job ${r.task.state.name} for $agent${waitingNote(r.waiting)}';
    });
  }

  void _release() => perform(() async {
    await widget.client.releaseTask(_task.id, owner: _task.ownerId!);
    return 'Job released to the queue';
  });

  void _cancel() {
    if (!_confirmCancel) {
      setState(() => _confirmCancel = true);
      return;
    }
    perform(() async {
      await widget.client.cancelTask(_task.id);
      return 'Job canceled';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_task.state.isOpen) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('This job is closed; no actions apply.'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_canAssign) ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _agent,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Assign to',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final a in widget.agents)
                        DropdownMenuItem(
                          value: a.name,
                          child: Text(
                            '${a.name} (${a.state.name})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: busy ? null : (v) => setState(() => _agent = v),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy ? null : _assign,
                  child: const Text('Assign'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          errorStrip(),
          Row(
            children: [
              if (_canRelease)
                OutlinedButton(
                  onPressed: busy ? null : _release,
                  child: const Text('Release'),
                ),
              const Spacer(),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: busy ? null : _cancel,
                child: Text(
                  _confirmCancel ? 'Tap again to cancel' : 'Cancel job',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
