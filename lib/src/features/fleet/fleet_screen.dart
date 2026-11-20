/// Fleet screen: every agent seat, live from `GET /v1/agents`. Active
/// agents sort to the top; tap a row for detail or tap the send icon to
/// prompt in one step.
library;

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../common/actions.dart';
import '../common/live_resource.dart';
import 'agent_detail_screen.dart';
import 'prompt_sheet.dart';

StatusTone agentStateTone(AgentState s) => switch (s) {
  AgentState.working || AgentState.launching => StatusTone.active,
  AgentState.idle => StatusTone.positive,
  AgentState.blocked => StatusTone.warning,
  AgentState.dead => StatusTone.danger,
  AgentState.done || AgentState.unknown => StatusTone.neutral,
};

int _agentSortRank(AgentState s) => switch (s) {
  AgentState.working => 0,
  AgentState.blocked => 1,
  AgentState.launching => 2,
  AgentState.idle => 3,
  AgentState.done => 4,
  AgentState.unknown => 5,
  AgentState.dead => 6,
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
      agents.sort((a, b) {
        final r = _agentSortRank(a.state).compareTo(_agentSortRank(b.state));
        return r != 0 ? r : a.name.compareTo(b.name);
      });
      return agents;
    },
    builder: (context, agents) {
      if (agents.isEmpty) {
        return ListView(
          children: emptyRow(
            'No agents on this host',
            icon: Icons.people_outline_rounded,
            subtitle:
                'Spawn or adopt agents on the tower host to monitor them.',
          ),
        );
      }
      final activeCount = agents
          .where(
            (a) =>
                a.state == AgentState.working ||
                a.state == AgentState.launching ||
                a.state == AgentState.blocked,
          )
          .length;
      final idleCount = agents.where((a) => a.state == AgentState.idle).length;
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionHeader(
            'Agents (${agents.length}) · $activeCount active · $idleCount idle',
          ),
          SegmentedCardList(
            itemCount: agents.length,
            itemBuilder: (context, i) {
              final a = agents[i];
              final dir = a.workdir
                  ?.split('/')
                  .where((s) => s.isNotEmpty)
                  .lastOrNull;
              final tone = agentStateTone(a.state);
              return M3EListItem(
                leading: StatusLeadingDot(tone),
                headline: a.name,
                supportingText: [a.kind, ?dir, ?a.model].join(' · '),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        AgentDetailScreen(client: client, feed: feed, agent: a),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatePill(a.state.name, tone),
                    const SizedBox(width: 6),
                    M3EIconButton(
                      variant: M3EIconButtonVariant.tonal,
                      size: M3EIconButtonSize.xs,
                      tooltip: 'Prompt ${a.name}',
                      icon: const Icon(Icons.send_rounded, size: 16),
                      onPressed: () => showActionSheet(
                        context,
                        PromptSheet(client: client, agent: a),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      );
    },
  );
}
