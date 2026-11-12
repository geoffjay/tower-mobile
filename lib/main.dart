/// App entry: wires the registry, session controller, and screens.
library;

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

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

  static const _seed = Colors.blueGrey;

  @override
  Widget build(BuildContext context) {
    final registry = _registry;
    final session = _session;
    return M3EMaterialApp(
      title: 'tower',
      data: M3EThemeData.light(seedColor: _seed),
      autoTheming: true,
      dynamicColoring: true,
      drawUnderSystemBars: true,
      debugShowCheckedModeBanner: false,
      home: registry == null || session == null
          ? const Scaffold(body: Center(child: M3ELoadingIndicator()))
          : AppShell(registry: registry, session: session),
    );
  }
}
