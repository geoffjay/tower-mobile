/// Jobs screen: the open queue and the most recent closed jobs, live
/// from `GET /v1/tasks`. The button queues a job; tapping a job opens
/// its actions (assign, release, cancel).
library;

import 'package:flutter/material.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../common/actions.dart';
import '../common/live_resource.dart';

/// How many closed jobs to show under the queue (herdr shows ten).
const _closedShown = 10;

class JobsData {
  const JobsData(this.open, this.closed, this.agents);

  final List<Task> open;
  final List<Task> closed;
  final List<Agent> agents;

  Map<String, String> get agentNames => {for (final a in agents) a.id: a.name};
}

class JobsScreen extends StatelessWidget {
  const JobsScreen({super.key, required this.client, required this.feed});

  final TowerClient client;
  final LiveFeed feed;

  @override
  Widget build(BuildContext context) => LiveResource<JobsData>(
    feed: feed,
    kinds: const ['task.', 'agent.state'],
    load: () async {
      final (tasks, agents) = await (client.tasks(), client.agents()).wait;
      final open = tasks.where((t) => t.state.isOpen).toList()
        ..sort((a, b) {
          final p = b.priority.compareTo(a.priority);
          return p != 0 ? p : a.createdAt.compareTo(b.createdAt);
        });
      final closed = tasks.where((t) => !t.state.isOpen).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      agents.sort((a, b) => a.name.compareTo(b.name));
      return JobsData(open, closed.take(_closedShown).toList(), agents);
    },
    builder: (context, data) => Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showActionSheet(
          context,
          QueueJobSheet(client: client, agents: data.agents),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Queue job'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          _Header('Queue (${data.open.length})'),
          if (data.open.isEmpty)
            const ListTile(title: Text('No open jobs.'))
          else
            for (final t in data.open) _tile(context, t, data),
          if (data.closed.isNotEmpty) ...[
            const _Header('Recently closed'),
            for (final t in data.closed) _tile(context, t, data),
          ],
        ],
      ),
    ),
  );

  Widget _tile(BuildContext context, Task t, JobsData data) => _TaskTile(
    t,
    data.agentNames,
    onTap: () => showActionSheet(
      context,
      TaskSheet(client: client, task: t, agents: data.agents),
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
  const _TaskTile(this.task, this.names, {required this.onTap});

  final Task task;
  final Map<String, String> names;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final owner = task.agentId == null
        ? null
        : names[task.agentId] ?? task.agentId;
    return ListTile(
      onTap: onTap,
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

/// `Reserved` explanation from an assign or create response, if any.
String _waitingNote(WaitingInfo w) =>
    w.reason.isEmpty ? '' : ' - waiting: ${w.reason}';

/// Queue a job: `POST /v1/tasks`, optionally pre-assigned to an agent.
class QueueJobSheet extends StatefulWidget {
  const QueueJobSheet({super.key, required this.client, required this.agents});

  final TowerClient client;
  final List<Agent> agents;

  @override
  State<QueueJobSheet> createState() => _QueueJobSheetState();
}

class _QueueJobSheetState extends State<QueueJobSheet> with ActionState {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _priority = TextEditingController();
  String? _assign;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _priority.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => error = 'A title is required.');
      return;
    }
    final priorityText = _priority.text.trim();
    final priority = priorityText.isEmpty ? null : int.tryParse(priorityText);
    if (priorityText.isNotEmpty && priority == null) {
      setState(() => error = 'Priority must be a whole number.');
      return;
    }
    final description = _description.text.trim();
    perform(() async {
      final r = await widget.client.createTask(
        CreateTaskBody(
          title: title,
          description: description.isEmpty ? null : description,
          priority: priority,
          assign: _assign,
        ),
      );
      final target = _assign == null ? 'Job queued' : 'Job sent to $_assign';
      return '$target (${r.task.state.name})${_waitingNote(r.waiting)}';
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Queue a job', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      TextField(
        controller: _title,
        autofocus: true,
        enabled: !busy,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Title',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _description,
        enabled: !busy,
        minLines: 2,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Description (optional)',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _priority,
              enabled: !busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Priority',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String?>(
              initialValue: _assign,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Assign to',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Queue only')),
                for (final a in widget.agents)
                  DropdownMenuItem(
                    value: a.name,
                    child: Text(a.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: busy ? null : (v) => setState(() => _assign = v),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      errorStrip(),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: busy ? null : _submit,
          child: Text(busy ? 'Queuing…' : 'Queue'),
        ),
      ),
    ],
  );
}

/// Actions on one job: assign (`/assign`), release (`/release`) and
/// cancel (`/cancel`, two presses). Only the actions that fit the job's
/// state are offered.
class TaskSheet extends StatefulWidget {
  const TaskSheet({
    super.key,
    required this.client,
    required this.task,
    required this.agents,
  });

  final TowerClient client;
  final Task task;
  final List<Agent> agents;

  @override
  State<TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<TaskSheet> with ActionState {
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
      return 'Job ${r.task.state.name} for $agent${_waitingNote(r.waiting)}';
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
    final description = _task.description;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_task.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '${_task.state.name} · p${_task.priority}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(description, maxLines: 6, overflow: TextOverflow.ellipsis),
        ],
        if (_task.result != null) ...[
          const SizedBox(height: 8),
          Text(
            'Result: ${_task.result}',
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 12),
        if (!_task.state.isOpen)
          const Text('This job is closed; no actions apply.'),
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
        if (_task.state.isOpen)
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
    );
  }
}
