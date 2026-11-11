/// App entry: wires the registry, session controller, and screens.
library;

import 'package:flutter/material.dart';

import 'src/connection/registry.dart';
import 'src/connection/session.dart';
import 'src/features/shell/shell.dart';

void main() {
  runApp(const TowerMobileApp());
}

/// Root widget. Loads the registry, then shows the shell.
class TowerMobileApp extends StatefulWidget {
  const TowerMobileApp({super.key});

  @override
  State<TowerMobileApp> createState() => _TowerMobileAppState();
}

class _TowerMobileAppState extends State<TowerMobileApp> {
  MachineRegistry? _registry;
  SessionController? _session;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final registry = await MachineRegistry.create();
    final session = SessionController(registry);
    setState(() {
      _registry = registry;
      _session = session;
    });
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_registry == null || _session == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp(
      title: 'tower',
      theme: ThemeData(colorSchemeSeed: Colors.blueGrey, useMaterial3: true),
      home: AppShell(registry: _registry!, session: _session!),
    );
  }
}
