/// Jobs screen: the queue and recent closed jobs.
/// M3 replaces this stub with the real list, detail, and queue form.
library;

import 'package:flutter/material.dart';

import '../../api/tower_client.dart';

/// Jobs list. Placeholder body until M3.
class JobsScreen extends StatelessWidget {
  const JobsScreen({super.key, required this.client});

  final TowerClient client;

  @override
  Widget build(BuildContext context) => const Center(
    child: Text('Jobs arrive at M3.'),
  );
}
