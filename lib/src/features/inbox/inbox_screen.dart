/// Inbox screen: pending questions and approvals for the operator,
/// live from `GET /v1/messages?to=me&status=pending`. Tap a message to
/// answer, approve, deny or dismiss it.
library;

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../common/actions.dart';
import '../common/live_resource.dart';

class InboxData {
  const InboxData(this.messages, this.agentNames);

  final List<Message> messages;

  /// Agent id to name, to show who a message came from.
  final Map<String, String> agentNames;
}

String _textOf(Message m) =>
    m.parts.map((p) => p.text).whereType<String>().join('\n').trim();

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
          : [
              for (final m in data.messages)
                _MessageTile(
                  m,
                  data.agentNames,
                  onTap: () => showActionSheet(
                    context,
                    RespondSheet(
                      client: client,
                      message: m,
                      from: data.agentNames[m.fromId] ?? m.fromId,
                    ),
                  ),
                ),
            ],
    ),
  );
}

class _MessageTile extends StatelessWidget {
  const _MessageTile(this.message, this.names, {required this.onTap});

  final Message message;
  final Map<String, String> names;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = _textOf(message);
    final from = names[message.fromId] ?? message.fromId;
    final due = message.deadlineAt;
    return ListTile(
      onTap: onTap,
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
    final left = DateTime.fromMillisecondsSinceEpoch(dueMs)
        .difference(DateTime.now());
    if (left.isNegative) return 'overdue';
    if (left.inMinutes < 60) return 'due in ${left.inMinutes}m';
    return 'due in ${left.inHours}h';
  }
}

/// Respond to one message. Approvals get Approve / Deny
/// (`POST /v1/messages/{id}/respond` with `approve`); anything else gets
/// a text answer. Dismiss closes the message without an answer.
class RespondSheet extends StatefulWidget {
  const RespondSheet({
    super.key,
    required this.client,
    required this.message,
    required this.from,
  });

  final TowerClient client;
  final Message message;
  final String from;

  @override
  State<RespondSheet> createState() => _RespondSheetState();
}

class _RespondSheetState extends State<RespondSheet> with ActionState {
  final _answer = TextEditingController();

  bool get _isApproval => widget.message.kind == MessageKind.approval;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _approve(bool yes) => perform(() async {
    await widget.client.respond(widget.message.id, approve: yes);
    return yes ? 'Approved' : 'Denied';
  });

  void _answerText() {
    final text = _answer.text.trim();
    if (text.isEmpty) return;
    perform(() async {
      await widget.client.respond(widget.message.id, answer: text);
      return 'Answer sent to ${widget.from}';
    });
  }

  void _dismiss() => perform(() async {
    await widget.client.dismiss(widget.message.id);
    return 'Dismissed';
  });

  @override
  Widget build(BuildContext context) {
    final text = _textOf(widget.message);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_isApproval ? 'Approval' : 'Question'} from ${widget.from}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(text.isEmpty ? '(no text)' : text),
        const SizedBox(height: 12),
        if (!_isApproval)
          TextField(
            controller: _answer,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            enabled: !busy,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Answer',
              border: OutlineInputBorder(),
            ),
          ),
        if (!_isApproval) const SizedBox(height: 12),
        errorStrip(),
        Row(
          children: [
            TextButton(
              onPressed: busy ? null : _dismiss,
              child: const Text('Dismiss'),
            ),
            const Spacer(),
            if (_isApproval) ...[
              OutlinedButton(
                onPressed: busy ? null : () => _approve(false),
                child: const Text('Deny'),
              ),
              const SizedBox(width: 8),
              M3EButton(
                onPressed: busy ? null : () => _approve(true),
                child: const Text('Approve'),
              ),
            ] else
              M3EButton(
                onPressed: busy ? null : _answerText,
                child: Text(busy ? 'Sending…' : 'Send'),
              ),
          ],
        ),
      ],
    );
  }
}
