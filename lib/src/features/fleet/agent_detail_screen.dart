/// Agent detail: facts in an Expressive card, live terminal tail, the
/// agent's jobs in a segmented card list, and an M3EExtendedFab prompt CTA.
library;

import 'dart:async';

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../common/actions.dart';
import '../common/live_resource.dart';
import '../jobs/job_detail_screen.dart';
import '../jobs/jobs_screen.dart' show taskStateTone;
import 'fleet_screen.dart' show agentStateTone;
import 'prompt_sheet.dart';

/// How often the terminal snapshot refreshes while the page is open.
/// Terminal output is excluded from the live feed, so this polls.
const _terminalPoll = Duration(seconds: 5);

/// Lines of terminal output shown (the tail).
const _terminalLines = 60;

/// Jobs listed on the page: open ones first, then the latest closed.
const _jobsShown = 8;

class _AgentView {
  const _AgentView(this.agent, this.jobs);

  final Agent agent;
  final List<Task> jobs;
}

class AgentDetailScreen extends StatefulWidget {
  const AgentDetailScreen({
    super.key,
    required this.client,
    required this.feed,
    required this.agent,
  });

  final TowerClient client;
  final LiveFeed feed;

  /// Initial snapshot from the Fleet list; updated live on each load.
  final Agent agent;

  @override
  State<AgentDetailScreen> createState() => _AgentDetailScreenState();
}

class _AgentDetailScreenState extends State<AgentDetailScreen> {
  late Agent _latestAgent = widget.agent;

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom;
    return Scaffold(
      appBar: M3EAppBar.top(
        automaticallyImplyLeading: true,
        title: Text(widget.agent.name),
      ),
      floatingActionButton: M3EExtendedFab(
        label: 'Prompt',
        icon: const Icon(Icons.send_rounded),
        onPressed: () => showActionSheet(
          context,
          PromptSheet(client: widget.client, agent: _latestAgent),
        ),
      ),
      body: LiveResource<_AgentView>(
        feed: widget.feed,
        kinds: const ['agent.state', 'task.'],
        load: () async {
          final (fresh, tasks) = await (
            widget.client.agent(widget.agent.id),
            widget.client.tasks(),
          ).wait;
          _latestAgent = fresh;
          final mine = tasks
              .where(
                (t) =>
                    t.agentId == widget.agent.id ||
                    t.ownerId == widget.agent.id,
              )
              .toList();
          final open = mine.where((t) => t.state.isOpen).toList();
          final closed = mine.where((t) => !t.state.isOpen).toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return _AgentView(
            fresh,
            [...open, ...closed].take(_jobsShown).toList(),
          );
        },
        builder: (context, view) {
          final a = view.agent;
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: EdgeInsets.only(bottom: 96 + bottomSafe),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Row(
                  children: [
                    StatePill(
                      a.state.name,
                      agentStateTone(a.state),
                      showDot: true,
                    ),
                    if (a.desiredState != a.state.name) ...[
                      const SizedBox(width: 10),
                      Text(
                        'wants ${a.desiredState}',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              InfoCard(
                children: [
                  InfoRow('Kind', a.kind),
                  if (a.model != null) InfoRow('Model', a.model!),
                  if (a.workdir != null) InfoRow('Workdir', a.workdir!),
                  if (a.worktree != null) InfoRow('Worktree', a.worktree!),
                  InfoRow('Permissions', a.permissions),
                  InfoRow('Adopted', a.adopted ? 'yes' : 'no'),
                  InfoRow('Updated', timeAgo(a.updatedAt)),
                ],
              ),
              const SectionHeader('Terminal'),
              _TerminalView(client: widget.client, agentId: a.id),
              SectionHeader('Jobs (${view.jobs.length})'),
              if (view.jobs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'No jobs for this agent.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              else
                SegmentedCardList(
                  itemCount: view.jobs.length,
                  itemBuilder: (context, i) {
                    final t = view.jobs[i];
                    final tone = taskStateTone(t.state);
                    return M3EListItem(
                      leading: StatusLeadingDot(tone),
                      headline: t.title,
                      supportingText:
                          'p${t.priority} · ${timeAgo(t.updatedAt)}',
                      trailing: StatePill(t.state.name, tone),
                      onTap: () => openPage(
                        context,
                        JobDetailScreen(
                          client: widget.client,
                          feed: widget.feed,
                          taskId: t.id,
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Tail of the agent's terminal, refreshed on a timer and manually.
class _TerminalView extends StatefulWidget {
  const _TerminalView({required this.client, required this.agentId});

  final TowerClient client;
  final String agentId;

  @override
  State<_TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<_TerminalView> {
  String? _text;
  Object? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_terminalPoll, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final out = await widget.client.readAgent(widget.agentId, ansi: false);
      if (!mounted) return;
      setState(() {
        _text = out;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    if (text == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _error == null
            ? const Center(child: M3ELoadingIndicator())
            : Text(describeError(_error!)),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final lines = text.trimRight().split('\n');
    final tail = lines.length > _terminalLines
        ? lines.sublist(lines.length - _terminalLines)
        : lines;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF121417),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            color: const Color(0xFF1C1F24),
            child: Row(
              children: [
                const Icon(
                  Icons.terminal_rounded,
                  size: 14,
                  color: Color(0xFF9AA4B2),
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Last $_terminalLines lines · 5s live poll',
                    style: TextStyle(fontSize: 11, color: Color(0xFF9AA4B2)),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _load,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: Color(0xFF9AA4B2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 280,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: SingleChildScrollView(
                // Anchored to the bottom: the newest output is what matters.
                reverse: true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    tail.isEmpty || (tail.length == 1 && tail.first.isEmpty)
                        ? '(terminal is blank)'
                        : tail.join('\n'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.3,
                      color: Color(0xFFE2E8F0),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
