/// Fleet screen: every agent seat, live from `GET /v1/agents`. Tap an
/// agent to open its detail page.
library;

import 'package:material_ui/material_ui.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../common/live_resource.dart';
import 'agent_detail_screen.dart';

Color agentStateColor(AgentState s) => switch (s) {
  AgentState.working => Colors.blue,
  AgentState.idle => Colors.green,
  AgentState.blocked => Colors.orange,
  AgentState.dead => Colors.red,
  AgentState.launching => Colors.teal,
  _ => Colors.grey,
};

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
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AgentDetailScreen(
                        client: client,
                        feed: feed,
                        agent: a,
                      ),
                    ),
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
      trailing: StatePill(agent.state.name, agentStateColor(agent.state)),
    );
  }
}
