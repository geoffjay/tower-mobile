/// Jobs screen: the open queue and the most recent closed jobs, live
/// from `GET /v1/tasks`. The button queues a job; tapping a job opens
/// its detail page (trail, assign, release, cancel).
library;

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../common/actions.dart';
import '../common/live_resource.dart';
import 'job_detail_screen.dart';

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
    onTap: () => openPage(
      context,
      JobDetailScreen(client: client, feed: feed, taskId: t.id),
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
      trailing: StatePill(task.state.name, taskStateColor(task.state)),
    );
  }
}

Color taskStateColor(TaskState s) => switch (s) {
  TaskState.queued => Colors.grey,
  TaskState.assigned => Colors.teal,
  TaskState.working => Colors.blue,
  TaskState.inputRequired => Colors.orange,
  TaskState.completed => Colors.green,
  TaskState.failed || TaskState.rejected => Colors.red,
  TaskState.canceled => Colors.blueGrey,
};

/// `Reserved` explanation from an assign or create response, if any.
String waitingNote(WaitingInfo w) =>
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
      return '$target (${r.task.state.name})${waitingNote(r.waiting)}';
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
        child: M3EButton(
          onPressed: busy ? null : _submit,
          child: Text(busy ? 'Queuing…' : 'Queue'),
        ),
      ),
    ],
  );
}
