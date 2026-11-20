/// Inbox screen: pending questions and approvals for the operator,
/// live from `GET /v1/messages?to=me&status=pending`. Tap a message to
/// answer, approve, deny or dismiss it.
library;

import 'dart:async';

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

({String label, StatusTone tone}) _deadlineBadge(int dueMs) {
  final left = DateTime.fromMillisecondsSinceEpoch(dueMs)
      .difference(DateTime.now());
  if (left.isNegative) {
    return (label: 'overdue', tone: StatusTone.danger);
  }
  if (left.inMinutes < 15) {
    return (label: 'due ${left.inMinutes}m', tone: StatusTone.warning);
  }
  if (left.inMinutes < 60) {
    return (label: 'due ${left.inMinutes}m', tone: StatusTone.neutral);
  }
  return (label: 'due ${left.inHours}h', tone: StatusTone.neutral);
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
    builder: (context, data) {
      if (data.messages.isEmpty) {
        return ListView(
          children: emptyRow(
            'Inbox is clear',
            icon: Icons.inbox_rounded,
            subtitle:
                'Questions and approval requests from agents appear here.',
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionHeader('Pending (${data.messages.length})'),
          SegmentedCardList(
            itemCount: data.messages.length,
            itemBuilder: (context, i) {
              final m = data.messages[i];
              final text = _textOf(m);
              final from = data.agentNames[m.fromId] ?? m.fromId;
              final isApproval = m.kind == MessageKind.approval;
              final tone = isApproval ? StatusTone.warning : StatusTone.active;
              final colors = resolveStatusColors(context, tone);
              final due = m.deadlineAt == null
                  ? null
                  : _deadlineBadge(m.deadlineAt!);
              return M3EListItem(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.container,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isApproval
                        ? Icons.verified_user_outlined
                        : Icons.help_outline_rounded,
                    size: 18,
                    color: colors.onContainer,
                  ),
                ),
                overline:
                    '${m.kind.name.toUpperCase()} · $from · '
                    '${timeAgo(m.createdAt)}',
                headline: text.isEmpty ? '(no text)' : text,
                trailing: due == null ? null : StatePill(due.label, due.tone),
                onTap: () => showActionSheet(
                  context,
                  RespondSheet(client: client, message: m, from: from),
                ),
              );
            },
          ),
        ],
      );
    },
  );
}

/// Respond to one message. Approvals get Approve / Deny
/// (`POST /v1/messages/{id}/respond` with `approve`); anything else gets
/// a text answer. Dismiss requires two presses so a stray tap never drops
/// an agent's question.
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
  var _confirmDismiss = false;
  Timer? _dismissReset;

  bool get _isApproval => widget.message.kind == MessageKind.approval;

  @override
  void dispose() {
    _dismissReset?.cancel();
    _answer.dispose();
    super.dispose();
  }

  void _approve(bool yes) => perform(() async {
    await widget.client.respond(widget.message.id, approve: yes);
    return yes ? 'Approved' : 'Denied';
  });

  void _answerText() {
    final text = _answer.text.trim();
    if (text.isEmpty) {
      setState(() => error = 'Enter an answer first.');
      return;
    }
    perform(() async {
      await widget.client.respond(widget.message.id, answer: text);
      return 'Answer sent to ${widget.from}';
    });
  }

  void _dismiss() {
    if (!_confirmDismiss) {
      _dismissReset?.cancel();
      setState(() => _confirmDismiss = true);
      _dismissReset = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _confirmDismiss = false);
      });
      return;
    }
    _dismissReset?.cancel();
    perform(() async {
      await widget.client.dismiss(widget.message.id);
      return 'Dismissed';
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = _textOf(widget.message);
    final scheme = Theme.of(context).colorScheme;
    final due = widget.message.deadlineAt == null
        ? null
        : _deadlineBadge(widget.message.deadlineAt!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_isApproval ? 'Approval' : 'Question'} from ${widget.from}',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (due != null) StatePill(due.label, due.tone),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(text.isEmpty ? '(no text)' : text),
        ),
        const SizedBox(height: 12),
        if (!_isApproval) ...[
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
          const SizedBox(height: 12),
        ],
        errorStrip(),
        Row(
          children: [
            TextButton(
              style: _confirmDismiss
                  ? TextButton.styleFrom(foregroundColor: scheme.error)
                  : null,
              onPressed: busy ? null : _dismiss,
              child: Text(_confirmDismiss ? 'Tap again to dismiss' : 'Dismiss'),
            ),
            const Spacer(),
            if (_isApproval) ...[
              M3EButton(
                style: M3EButtonStyle.outlined,
                onPressed: busy ? null : () => _approve(false),
                child: const Text('Deny'),
              ),
              const SizedBox(width: 8),
              M3EButton(
                onPressed: busy ? null : () => _approve(true),
                child: const Text('Approve'),
              ),
            ] else
              M3EButton.icon(
                icon: const Icon(Icons.send_rounded, size: 18),
                onPressed: busy ? null : _answerText,
                label: Text(busy ? 'Sending…' : 'Send'),
              ),
          ],
        ),
      ],
    );
  }
}
