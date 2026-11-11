/// Inbox screen: pending questions and approvals for the operator,
/// live from `GET /v1/messages?to=me&status=pending`.
library;

import 'package:flutter/material.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../common/live_resource.dart';

class InboxData {
  const InboxData(this.messages, this.agentNames);

  final List<Message> messages;

  /// Agent id to name, to show who a message came from.
  final Map<String, String> agentNames;
}

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, required this.client, required this.feed});

  final TowerClient client;
  final LiveFeed feed;

  @override
  Widget build(BuildContext context) => LiveResource<InboxData>(
    feed: feed,
    kinds: const ['message.'],
    load: () async {
      final (messages, agents) = await (client.inbox(), client.agents()).wait;
      messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return InboxData(messages, {for (final a in agents) a.id: a.name});
    },
    builder: (context, data) => ListView(
      children: data.messages.isEmpty
          ? emptyRow('Inbox is empty.')
          : [for (final m in data.messages) _MessageTile(m, data.agentNames)],
    ),
  );
}

class _MessageTile extends StatelessWidget {
  const _MessageTile(this.message, this.names);

  final Message message;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final text = message.parts
        .map((p) => p.text)
        .whereType<String>()
        .join('\n')
        .trim();
    final from = names[message.fromId] ?? message.fromId;
    final due = message.deadlineAt;
    return ListTile(
      leading: Icon(
        message.kind == MessageKind.approval
            ? Icons.verified_user_outlined
            : Icons.help_outline,
      ),
      title: Text(
        text.isEmpty ? '(no text)' : text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          message.kind.name,
          'from $from',
          timeAgo(message.createdAt),
          if (due != null) _deadline(due),
        ].join(' · '),
      ),
      isThreeLine: true,
    );
  }

  static String _deadline(int dueMs) {
    final left = DateTime.fromMillisecondsSinceEpoch(dueMs).difference(
      DateTime.now(),
    );
    if (left.isNegative) return 'overdue';
    if (left.inMinutes < 60) return 'due in ${left.inMinutes}m';
    return 'due in ${left.inHours}h';
  }
}
