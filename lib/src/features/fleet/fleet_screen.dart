/// Fleet screen: every agent seat, live from `GET /v1/agents`.
library;

import 'package:flutter/material.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
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
          : [for (final a in agents) _AgentTile(a)],
    ),
  );
}

class _AgentTile extends StatelessWidget {
  const _AgentTile(this.agent);

  final Agent agent;

  @override
  Widget build(BuildContext context) {
    final dir = agent.workdir
        ?.split('/')
        .where((s) => s.isNotEmpty)
        .lastOrNull;
    return ListTile(
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
