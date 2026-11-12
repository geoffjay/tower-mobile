/// Agent detail: facts, a live terminal snapshot, the agent's jobs, and
/// the prompt action.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../common/actions.dart';
import '../common/live_resource.dart';
import '../jobs/job_detail_screen.dart';
import '../jobs/jobs_screen.dart' show taskStateColor;
import 'fleet_screen.dart' show agentStateColor;
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

class AgentDetailScreen extends StatelessWidget {
  const AgentDetailScreen({
    super.key,
    required this.client,
    required this.feed,
    required this.agent,
  });

  final TowerClient client;
  final LiveFeed feed;

  /// The row the list showed; the page refetches the live one.
  final Agent agent;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(agent.name)),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () =>
          showActionSheet(context, PromptSheet(client: client, agent: agent)),
      icon: const Icon(Icons.send),
      label: const Text('Prompt'),
    ),
    body: LiveResource<_AgentView>(
      feed: feed,
      kinds: const ['agent.state', 'task.'],
      load: () async {
        final (fresh, tasks) = await (
          client.agent(agent.id),
          client.tasks(),
        ).wait;
        final mine = tasks
            .where((t) => t.agentId == agent.id || t.ownerId == agent.id)
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
        return ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  StatePill(a.state.name, agentStateColor(a.state)),
                  const SizedBox(width: 8),
                  if (a.desiredState != a.state.name)
                    Text('wants ${a.desiredState}'),
                ],
              ),
            ),
            InfoRow('Kind', a.kind),
            if (a.model != null) InfoRow('Model', a.model!),
            if (a.workdir != null) InfoRow('Workdir', a.workdir!),
            if (a.worktree != null) InfoRow('Worktree', a.worktree!),
            InfoRow('Permissions', a.permissions),
            InfoRow('Adopted', a.adopted ? 'yes' : 'no'),
            InfoRow('Updated', timeAgo(a.updatedAt)),
            const SectionHeader('Terminal'),
            _TerminalView(client: client, agentId: a.id),
            SectionHeader('Jobs (${view.jobs.length})'),
            if (view.jobs.isEmpty)
              const ListTile(title: Text('No jobs for this agent.')),
            for (final t in view.jobs)
              ListTile(
                title: Text(
                  t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('p${t.priority} · ${timeAgo(t.updatedAt)}'),
                trailing: StatePill(t.state.name, taskStateColor(t.state)),
                onTap: () => openPage(
                  context,
                  JobDetailScreen(client: client, feed: feed, taskId: t.id),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// Tail of the agent's terminal, refreshed on a timer.
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
            ? const Center(child: CircularProgressIndicator())
            : Text(describeError(_error!)),
      );
    }
    final lines = text.trimRight().split('\n');
    final tail = lines.length > _terminalLines
        ? lines.sublist(lines.length - _terminalLines)
        : lines;
    return Container(
      height: 320,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        // Anchored to the bottom: the newest output is what matters.
        reverse: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            tail.join('\n'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.25,
              color: Color(0xFFDDDDDD),
            ),
          ),
        ),
      ),
    );
  }
}
