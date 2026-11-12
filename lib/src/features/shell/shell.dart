/// App shell: navigation between the five screens, with the machine
/// switcher in the app bar.
library;

import 'package:flutter/material.dart';

import '../../api/live_feed.dart';
import '../../connection/registry.dart';
import '../../connection/session.dart';
import '../fleet/fleet_screen.dart';
import '../inbox/inbox_screen.dart';
import '../jobs/jobs_screen.dart';
import '../machines/machines_screen.dart';
import '../workflows/workflows_screen.dart';

/// The visible screen, in navigation order.
enum AppTab { machines, fleet, inbox, jobs, workflows }

/// Scaffold with bottom navigation; the active machine's session drives
/// the action screens.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.registry, required this.session});

  final MachineRegistry registry;
  final SessionController session;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppTab _tab = AppTab.machines;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return StreamBuilder<SessionState>(
      stream: session,
      initialData: session.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? session.state;
        final ready = state.phase == SessionPhase.ready;
        return Scaffold(
          appBar: AppBar(
            title: Text(_titleFor(_tab)),
            actions: [
              if (ready) _FeedIndicator(state.feed!),
              if (state.machine != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Text(
                      state.machine!.name,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
            ],
          ),
          body: switch (_tab) {
            AppTab.machines => MachinesScreen(
              registry: widget.registry,
              session: session,
            ),
            AppTab.fleet =>
              ready
                  ? FleetScreen(client: state.client!, feed: state.feed!)
                  : const _NotConnected(),
            AppTab.inbox =>
              ready
                  ? InboxScreen(client: state.client!, feed: state.feed!)
                  : const _NotConnected(),
            AppTab.jobs =>
              ready
                  ? JobsScreen(client: state.client!, feed: state.feed!)
                  : const _NotConnected(),
            AppTab.workflows =>
              ready
                  ? WorkflowsScreen(client: state.client!, feed: state.feed!)
                  : const _NotConnected(),
          },
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab.index,
            onDestinationSelected: (i) =>
                setState(() => _tab = AppTab.values[i]),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dns_outlined),
                selectedIcon: Icon(Icons.dns),
                label: 'Machines',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Fleet',
              ),
              NavigationDestination(
                icon: Icon(Icons.inbox_outlined),
                selectedIcon: Icon(Icons.inbox),
                label: 'Inbox',
              ),
              NavigationDestination(
                icon: Icon(Icons.work_outline),
                selectedIcon: Icon(Icons.work),
                label: 'Jobs',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_tree_outlined),
                selectedIcon: Icon(Icons.account_tree),
                label: 'Workflows',
              ),
            ],
          ),
        );
      },
    );
  }

  String _titleFor(AppTab tab) => switch (tab) {
    AppTab.machines => 'Machines',
    AppTab.fleet => 'Fleet',
    AppTab.inbox => 'Inbox',
    AppTab.jobs => 'Jobs',
    AppTab.workflows => 'Workflows',
  };
}

/// Placeholder shown when an action screen is selected without a ready
/// session.
class _NotConnected extends StatelessWidget {
  const _NotConnected();

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Connect a machine first (Machines tab).'));
}

/// Live-feed health in the app bar: a green dot while the event stream
/// is open, a tappable red icon after it drops.
class _FeedIndicator extends StatelessWidget {
  const _FeedIndicator(this.feed);

  final LiveFeed feed;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<FeedStatus>(
    valueListenable: feed.status,
    builder: (context, status, _) => status == FeedStatus.live
        ? const Tooltip(
            message: 'Live updates on',
            child: Icon(Icons.circle, size: 10, color: Colors.green),
          )
        : IconButton(
            tooltip: '${feed.error ?? 'Live updates off'} - tap to reconnect',
            icon: const Icon(Icons.sync_problem, color: Colors.red),
            onPressed: feed.reconnect,
          ),
  );
}
