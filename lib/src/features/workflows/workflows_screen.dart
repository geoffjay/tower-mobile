/// Workflows screen: definitions, runs, and run initiation.
/// M3 replaces this stub with the real list, detail, and run form.
library;

import 'package:flutter/material.dart';

import '../../api/tower_client.dart';

/// Workflows list. Placeholder body until M3.
class WorkflowsScreen extends StatelessWidget {
  const WorkflowsScreen({super.key, required this.client});

  final TowerClient client;

  @override
  Widget build(BuildContext context) => const Center(
    child: Text('Workflows arrive at M3.'),
  );
}
