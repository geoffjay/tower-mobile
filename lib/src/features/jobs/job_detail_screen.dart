/// Job detail: facts in an Expressive card, result, in-place actions
/// (assign, release, cancel), and the event trail in a segmented card list.
library;

import 'dart:async';

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../common/actions.dart';
import '../common/live_resource.dart';
import 'jobs_screen.dart' show taskStateTone, waitingNote;

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
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom;
    return Scaffold(
      appBar: M3EAppBar.top(
        automaticallyImplyLeading: true,
        title: const Text('Job'),
      ),
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
        refreshableBuilder: (context, view, refresh) {
          final t = view.detail.task;
          final names = {for (final a in view.agents) a.id: a.name};
          final owner = t.ownerId == null
              ? null
              : names[t.ownerId] ?? t.ownerId;
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: EdgeInsets.only(bottom: 32 + bottomSafe),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Text(
                  t.title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StatePill(
                    t.state.name,
                    taskStateTone(t.state),
                    showDot: true,
                  ),
                ),
              ),
              InfoCard(
                children: [
                  InfoRow('Priority', 'p${t.priority}'),
                  if (owner != null) InfoRow('Owner', owner),
                  if (t.tags.isNotEmpty) InfoRow('Tags', t.tags.join(', ')),
                  InfoRow('Attempts', '${t.attemptCount} of ${t.maxAttempts}'),
                  InfoRow('Created', timeAgo(t.createdAt)),
                  InfoRow('Updated', timeAgo(t.updatedAt)),
                ],
              ),
              if (t.description != null && t.description!.isNotEmpty) ...[
                const SectionHeader('Description'),
                ContentCard(t.description!),
              ],
              if (t.result != null) ...[
                const SectionHeader('Result'),
                ContentCard(t.result!),
              ],
              if (t.state.isOpen) ...[
                const SectionHeader('Actions'),
                InfoCard(
                  children: [
                    _JobActions(
                      client: client,
                      task: t,
                      agents: view.agents,
                      onMutated: refresh,
                    ),
                  ],
                ),
              ],
              SectionHeader('Trail (${view.detail.trail.length})'),
              if (view.detail.trail.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'No events recorded yet.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              else
                SegmentedCardList(
                  itemCount: view.detail.trail.length,
                  itemBuilder: (context, i) {
                    final e = view.detail.trail[i];
                    return M3EListItem(
                      headline: _describe(e, names),
                      supportingText: timeAgo(e.ts),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

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

/// In-place assign (`/assign`), release (`/release`) and cancel (`/cancel`,
/// two presses with 3s auto-reset). Keeps the detail page open so the
/// operator sees the updated state and trail immediately.
class _JobActions extends StatefulWidget {
  const _JobActions({
    required this.client,
    required this.task,
    required this.agents,
    required this.onMutated,
  });

  final TowerClient client;
  final Task task;
  final List<Agent> agents;
  final Future<void> Function() onMutated;

  @override
  State<_JobActions> createState() => _JobActionsState();
}

class _JobActionsState extends State<_JobActions> with ActionState {
  String? _agent;
  var _confirmCancel = false;
  Timer? _cancelReset;

  Task get _task => widget.task;

  bool get _canAssign =>
      _task.state == TaskState.queued || _task.state == TaskState.assigned;
  bool get _canRelease =>
      _task.ownerId != null &&
      (_task.state == TaskState.assigned ||
          _task.state == TaskState.working ||
          _task.state == TaskState.inputRequired);

  @override
  void dispose() {
    _cancelReset?.cancel();
    super.dispose();
  }

  void _assign() {
    final agent = _agent;
    if (agent == null) {
      setState(() => error = 'Pick an agent first.');
      return;
    }
    performInline(() async {
      final r = await widget.client.assignTask(_task.id, agent);
      return 'Job ${r.task.state.name} for $agent${waitingNote(r.waiting)}';
    }, onSuccess: widget.onMutated);
  }

  void _release() => performInline(() async {
    await widget.client.releaseTask(_task.id, owner: _task.ownerId!);
    return 'Job released to the queue';
  }, onSuccess: widget.onMutated);

  void _cancel() {
    if (!_confirmCancel) {
      _cancelReset?.cancel();
      setState(() => _confirmCancel = true);
      _cancelReset = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _confirmCancel = false);
      });
      return;
    }
    _cancelReset?.cancel();
    setState(() => _confirmCancel = false);
    performInline(() async {
      await widget.client.cancelTask(_task.id);
      return 'Job canceled';
    }, onSuccess: widget.onMutated);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
                M3EButton(
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
                M3EButton(
                  style: M3EButtonStyle.outlined,
                  onPressed: busy ? null : _release,
                  child: const Text('Release'),
                ),
              const Spacer(),
              M3EButton(
                style: _confirmCancel
                    ? M3EButtonStyle.filled
                    : M3EButtonStyle.tonal,
                decoration: M3EButtonDecoration(
                  backgroundColor: _confirmCancel
                      ? WidgetStatePropertyAll(scheme.error)
                      : WidgetStatePropertyAll(scheme.errorContainer),
                  foregroundColor: WidgetStatePropertyAll(
                    _confirmCancel ? scheme.onError : scheme.onErrorContainer,
                  ),
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
