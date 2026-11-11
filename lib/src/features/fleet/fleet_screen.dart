/// Fleet screen: every agent seat, live from `GET /v1/agents`.
/// M3 replaces this stub with the real list and detail views.
library;

import 'package:flutter/material.dart';

import '../../api/tower_client.dart';

/// Fleet list. Placeholder body until M3.
class FleetScreen extends StatelessWidget {
  const FleetScreen({super.key, required this.client});

  final TowerClient client;

  @override
  Widget build(BuildContext context) => const Center(
    child: Text('Fleet arrives at M3.'),
  );
}
