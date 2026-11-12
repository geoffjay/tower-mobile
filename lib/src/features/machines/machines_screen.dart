/// Machines screen: list of added machines, connect status, add-machine
/// wizard with first-connection key bootstrap.
library;

import 'package:flutter/material.dart';

import '../../connection/registry.dart';
import '../../connection/session.dart';

/// The machine list and add wizard.
class MachinesScreen extends StatefulWidget {
  const MachinesScreen({
    super.key,
    required this.registry,
    required this.session,
  });

  final MachineRegistry registry;
  final SessionController session;

  @override
  State<MachinesScreen> createState() => _MachinesScreenState();
}

class _MachinesScreenState extends State<MachinesScreen> {
  List<StoredMachine> _machines = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() {
    _machines = widget.registry.machines();
  });

  Future<void> _connect(
    StoredMachine machine, {
    bool forcePassword = false,
  }) async {
    String? password;
    if (!machine.keyBootstrapped || forcePassword) {
      password = await _promptPassword(machine, reinstallKey: forcePassword);
      if (password == null) return;
    }
    await widget.session.connect(machine, password: password);
    if (!mounted) return;
    final state = widget.session.state;
    if (state.phase == SessionPhase.failed) {
      if (state.needsPassword) {
        // Key auth was refused: re-bootstrap the key with a password.
        await _connect(machine, forcePassword: true);
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.error ?? 'connect failed')));
    }
    _reload();
  }

  Future<String?> _promptPassword(
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
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  Future<void> _addMachine() async {
    final machine = await showDialog<StoredMachine>(
      context: context,
      builder: (context) => const _AddMachineDialog(),
    );
    if (machine == null) return;
    final machines = [...widget.registry.machines(), machine];
    await widget.registry.saveMachines(machines);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return StreamBuilder<SessionState>(
      stream: session,
      initialData: session.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? session.state;
        return Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: _addMachine,
            child: const Icon(Icons.add),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              if (state.machine != null && state.phase == SessionPhase.ready) {
                await session.connect(state.machine!);
              }
              _reload();
            },
            child: _machines.isEmpty
                ? ListView(
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No machines yet. Add one with + to connect '
                            'to a tower host.',
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    children: [
                      for (final m in _machines)
                        _MachineTile(
                          machine: m,
                          state: state,
                          onConnect: () => _connect(m),
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// One machine row: name, host, connect button, status.
class _MachineTile extends StatelessWidget {
  const _MachineTile({
    required this.machine,
    required this.state,
    required this.onConnect,
  });

  final StoredMachine machine;
  final SessionState state;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final isActive = state.machine?.id == machine.id;
    final phase = isActive ? state.phase : SessionPhase.disconnected;
    return ListTile(
      leading: Icon(
        isActive && phase == SessionPhase.ready
            ? Icons.dns
            : Icons.dns_outlined,
        color: isActive && phase == SessionPhase.ready
            ? Theme.of(context).colorScheme.primary
            : null,
      ),
      title: Text(machine.name),
      subtitle: Text(
        '${machine.username}@${machine.host}:${machine.port}'
        '${isActive ? ' · ${phase.name}' : ''}',
      ),
      trailing: isActive && phase == SessionPhase.connecting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(onPressed: onConnect, child: const Text('Connect')),
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
      title: const Text('Add machine'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'required' : null,
            ),
            TextFormField(
              controller: _host,
              decoration: const InputDecoration(labelText: 'Host'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'required' : null,
            ),
            TextFormField(
              controller: _port,
              decoration: const InputDecoration(labelText: 'SSH port'),
              keyboardType: TextInputType.number,
            ),
            TextFormField(
              controller: _username,
              decoration: const InputDecoration(labelText: 'SSH username'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'required' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
