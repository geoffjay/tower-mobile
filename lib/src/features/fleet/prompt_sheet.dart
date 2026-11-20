/// Prompt sheet for one agent.
library;

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../common/actions.dart';
import '../common/live_resource.dart';
import 'fleet_screen.dart' show agentStateTone;

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
    if (text.isEmpty) {
      setState(() => error = 'Enter a prompt first.');
      return;
    }
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
      Row(
        children: [
          Expanded(
            child: Text(
              'Prompt ${widget.agent.name}',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          StatePill(
            widget.agent.state.name,
            agentStateTone(widget.agent.state),
            showDot: true,
          ),
        ],
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
          hintText: 'Describe what this agent should work on…',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      errorStrip(),
      Align(
        alignment: Alignment.centerRight,
        child: M3EButton.icon(
          icon: const Icon(Icons.send_rounded, size: 18),
          onPressed: busy ? null : _send,
          label: Text(busy ? 'Sending…' : 'Send prompt'),
        ),
      ),
    ],
  );
}
