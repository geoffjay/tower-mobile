/// Host switcher sheet, add-host dialog, and shared connect/bootstrap flow.
library;

import 'dart:async';

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../connection/registry.dart';
import '../../connection/session.dart';
import '../common/actions.dart';
import '../common/live_resource.dart';

/// Open the host switcher modal sheet from the app bar or empty state.
Future<void> showMachinesSheet(
  BuildContext context, {
  required MachineRegistry registry,
  required SessionController session,
}) => showTypedSheet<void>(
  context,
  MachinesSheet(registry: registry, session: session),
);

/// Open the Add Host dialog, persist the entry on submit, and return it.
Future<StoredMachine?> showAddMachineDialog(
  BuildContext context,
  MachineRegistry registry,
) async {
  final machine = await showDialog<StoredMachine>(
    context: context,
    builder: (context) => const _AddMachineDialog(),
  );
  if (machine == null) return null;
  final machines = [...registry.machines(), machine];
  await registry.saveMachines(machines);
  return machine;
}

/// Connect [machine], prompting for the SSH password on first bootstrap or
/// when key sign-in is refused. Returns `true` when the session reaches
/// [SessionPhase.ready].
Future<bool> connectMachineWithPrompt(
  BuildContext context, {
  required MachineRegistry registry,
  required SessionController session,
  required StoredMachine machine,
  bool forcePassword = false,
}) async {
  String? password;
  if (!machine.keyBootstrapped || forcePassword) {
    password = await _promptPassword(
      context,
      machine,
      reinstallKey: forcePassword,
    );
    if (password == null) return false;
  }
  await session.connect(machine, password: password);
  final state = session.state;
  if (state.phase == SessionPhase.ready) return true;
  if (state.phase == SessionPhase.failed) {
    if (state.needsPassword && context.mounted) {
      return connectMachineWithPrompt(
        context,
        registry: registry,
        session: session,
        machine: machine,
        forcePassword: true,
      );
    }
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.error ?? 'Connect failed')));
    }
  }
  return false;
}

Future<String?> _promptPassword(
  BuildContext context,
  StoredMachine machine, {
  bool reinstallKey = false,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Connect to ${machine.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            reinstallKey
                ? 'Key sign-in was refused. Enter the SSH password to '
                      'reinstall this device\'s key.'
                : 'First connection uses your SSH password and installs '
                      'this device\'s public key for future connects.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(context, v),
            decoration: const InputDecoration(
              labelText: 'SSH password',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        M3EButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Connect'),
        ),
      ],
    ),
  );
}

/// Modal bottom sheet listing saved hosts with connect, disconnect, add,
/// and two-press remove controls.
class MachinesSheet extends StatefulWidget {
  const MachinesSheet({
    super.key,
    required this.registry,
    required this.session,
  });

  final MachineRegistry registry;
  final SessionController session;

  @override
  State<MachinesSheet> createState() => _MachinesSheetState();
}

class _MachinesSheetState extends State<MachinesSheet> {
  List<StoredMachine> _machines = const [];
  String? _armedDeleteId;
  Timer? _deleteReset;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _deleteReset?.cancel();
    super.dispose();
  }

  void _reload() => setState(() {
    _machines = widget.registry.machines();
  });

  Future<void> _connect(StoredMachine machine) async {
    final ok = await connectMachineWithPrompt(
      context,
      registry: widget.registry,
      session: widget.session,
      machine: machine,
    );
    if (!mounted) return;
    _reload();
    if (ok) Navigator.of(context).pop();
  }

  Future<void> _add() async {
    final machine = await showAddMachineDialog(context, widget.registry);
    if (machine == null || !mounted) return;
    _reload();
    await _connect(machine);
  }

  Future<void> _delete(StoredMachine machine, bool isActive) async {
    if (_armedDeleteId != machine.id) {
      _deleteReset?.cancel();
      setState(() => _armedDeleteId = machine.id);
      _deleteReset = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _armedDeleteId = null);
      });
      return;
    }
    _deleteReset?.cancel();
    setState(() => _armedDeleteId = null);
    if (isActive) {
      await widget.session.disconnect();
    }
    await widget.registry.removeMachine(machine.id);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<SessionState>(
      stream: session,
      initialData: session.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? session.state;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tower hosts',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                M3EButton.icon(
                  style: M3EButtonStyle.tonal,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  onPressed: _add,
                  label: const Text('Add host'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (state.error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: state.phase == SessionPhase.connecting
                      ? scheme.secondaryContainer
                      : scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  state.error!,
                  style: TextStyle(
                    color: state.phase == SessionPhase.connecting
                        ? scheme.onSecondaryContainer
                        : scheme.onErrorContainer,
                  ),
                ),
              ),
            if (_machines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No hosts saved yet. Add a tower host over SSH to monitor '
                    'agents, jobs, inbox messages, and workflows.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              SegmentedCardList(
                margin: EdgeInsets.zero,
                itemCount: _machines.length,
                itemBuilder: (context, i) {
                  final m = _machines[i];
                  final isActive = state.machine?.id == m.id;
                  final phase = isActive
                      ? state.phase
                      : SessionPhase.disconnected;
                  final armed = _armedDeleteId == m.id;
                  final tone = switch (phase) {
                    SessionPhase.ready => StatusTone.positive,
                    SessionPhase.connecting ||
                    SessionPhase.connected => StatusTone.active,
                    SessionPhase.failed => StatusTone.danger,
                    SessionPhase.disconnected => StatusTone.neutral,
                  };
                  final statusLabel = switch (phase) {
                    SessionPhase.ready => 'connected',
                    SessionPhase.connecting ||
                    SessionPhase.connected => 'connecting',
                    SessionPhase.failed => 'failed',
                    SessionPhase.disconnected =>
                      m.keyBootstrapped ? 'key ready' : 'setup',
                  };
                  return M3EListItem(
                    selected: isActive && phase == SessionPhase.ready,
                    leading: StatusLeadingDot(tone),
                    headline: m.name,
                    supportingText:
                        '${m.username}@${m.host}:${m.port}'
                        '${armed ? ' · tap trash again to remove' : ''}',
                    onTap: phase == SessionPhase.connecting
                        ? null
                        : () {
                            if (isActive && phase == SessionPhase.ready) {
                              Navigator.of(context).pop();
                            } else {
                              _connect(m);
                            }
                          },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isActive && phase == SessionPhase.connecting)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: M3ELoadingIndicator(),
                          )
                        else
                          StatePill(statusLabel, tone),
                        if (isActive && phase == SessionPhase.ready) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Disconnect',
                            icon: const Icon(Icons.link_off_rounded, size: 20),
                            onPressed: session.disconnect,
                          ),
                        ],
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: armed ? 'Confirm remove' : 'Remove host',
                          icon: Icon(
                            armed
                                ? Icons.delete_forever_rounded
                                : Icons.delete_outline_rounded,
                            size: 20,
                            color: armed ? scheme.error : null,
                          ),
                          onPressed: () => _delete(m, isActive),
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
}

/// Add-machine form: name, host, port, username. Password is asked at
/// first connect, not stored here.
class _AddMachineDialog extends StatefulWidget {
  const _AddMachineDialog();

  @override
  State<_AddMachineDialog> createState() => _AddMachineDialogState();
}

class _AddMachineDialogState extends State<_AddMachineDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _username = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      final machine = StoredMachine(
        id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
        name: _name.text.trim(),
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 22,
        username: _username.text.trim(),
        hostKeyFingerprint: '',
      );
      Navigator.pop(context, machine);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add tower host'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'kobo',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _host,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Host or IP',
                hintText: 'kobo.tailnet.ts.net',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'required' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _username,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'SSH user',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'required' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        M3EButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
