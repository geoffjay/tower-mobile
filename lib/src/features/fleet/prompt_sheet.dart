/// Prompt sheet for one agent.
library;

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../common/actions.dart';

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
        child: M3EButton(
          onPressed: busy ? null : _send,
          child: Text(busy ? 'Sending…' : 'Send'),
        ),
      ),
    ],
  );
}
