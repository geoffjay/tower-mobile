/// Fleet screen: every agent seat, live from `GET /v1/agents`. Tap an
/// agent to send it a prompt.
library;

import 'package:flutter/material.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../common/actions.dart';
import '../common/live_resource.dart';

class FleetScreen extends StatelessWidget {
  const FleetScreen({super.key, required this.client, required this.feed});

  final TowerClient client;
  final LiveFeed feed;

  @override
  Widget build(BuildContext context) => LiveResource<List<Agent>>(
    feed: feed,
    kinds: const ['agent.'],
    load: () async {
      final agents = await client.agents();
      agents.sort((a, b) => a.name.compareTo(b.name));
      return agents;
    },
    builder: (context, agents) => ListView(
      children: agents.isEmpty
          ? emptyRow('No agents.')
          : [
              for (final a in agents)
                _AgentTile(
                  a,
                  onTap: () => showActionSheet(
                    context,
                    PromptSheet(client: client, agent: a),
                  ),
                ),
            ],
    ),
  );
}

class _AgentTile extends StatelessWidget {
  const _AgentTile(this.agent, {required this.onTap});

  final Agent agent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dir = agent.workdir?.split('/').where((s) => s.isNotEmpty).lastOrNull;
    return ListTile(
      onTap: onTap,
      title: Text(agent.name),
      subtitle: Text(
        [agent.kind, ?dir, ?agent.model].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: StatePill(agent.state.name, _color(agent.state)),
    );
  }

  static Color _color(AgentState s) => switch (s) {
    AgentState.working => Colors.blue,
    AgentState.idle => Colors.green,
    AgentState.blocked => Colors.orange,
    AgentState.dead => Colors.red,
    AgentState.launching => Colors.teal,
    _ => Colors.grey,
  };
}

/// Send a prompt to one agent: `POST /v1/agents/{id}/prompt`.
class PromptSheet extends StatefulWidget {
  const PromptSheet({super.key, required this.client, required this.agent});

  final TowerClient client;
  final Agent agent;

  @override
  State<PromptSheet> createState() => _PromptSheetState();
}

class _PromptSheetState extends State<PromptSheet> with ActionState {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    perform(() async {
      final r = await widget.client.prompt(widget.agent.name, text);
      return r.stalled
          ? 'Prompt sent to ${widget.agent.name}, but it has not started '
                'working (${r.state})'
          : 'Prompt sent to ${widget.agent.name} (${r.state})';
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Prompt ${widget.agent.name}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Text(
        'State: ${widget.agent.state.name}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _text,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        enabled: !busy,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Prompt',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      errorStrip(),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: busy ? null : _send,
          child: Text(busy ? 'Sending…' : 'Send'),
        ),
      ),
    ],
  );
}
