/// Inbox screen: pending questions and approvals.
/// M3 replaces this stub with the real list and respond actions.
library;

import 'package:flutter/material.dart';

import '../../api/tower_client.dart';

/// Inbox list. Placeholder body until M3.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, required this.client});

  final TowerClient client;

  @override
  Widget build(BuildContext context) => const Center(
    child: Text('Inbox arrives at M3.'),
  );
}
