/// App shell: navigation between the five screens, with the machine
/// switcher in the app bar.
library;

import 'dart:async';

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
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

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  AppTab _tab = AppTab.machines;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Battery: no event stream while the app is in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        widget.session.pause();
      case AppLifecycleState.resumed:
        widget.session.resume();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

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
          appBar: M3EAppBar.top(
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
          bottomNavigationBar: M3ENavigationBar(
            selectedIndex: _tab.index,
            onDestinationSelected: (i) =>
                setState(() => _tab = AppTab.values[i]),
            destinations: [
              const M3ENavigationBarDestination(
                icon: Icon(Icons.dns_outlined),
                selectedIcon: Icon(Icons.dns),
                label: 'Machines',
              ),
              const M3ENavigationBarDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Fleet',
              ),
              M3ENavigationBarDestination(
                icon: _InboxIcon(state, selected: false),
                selectedIcon: _InboxIcon(state, selected: true),
                label: 'Inbox',
              ),
              const M3ENavigationBarDestination(
                icon: Icon(Icons.work_outline),
                selectedIcon: Icon(Icons.work),
                label: 'Jobs',
              ),
              const M3ENavigationBarDestination(
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

/// The Inbox tab icon, with a count of pending messages when connected.
class _InboxIcon extends StatelessWidget {
  const _InboxIcon(this.state, {required this.selected});

  final SessionState state;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(selected ? Icons.inbox : Icons.inbox_outlined);
    final client = state.client;
    final feed = state.feed;
    if (state.phase != SessionPhase.ready || client == null || feed == null) {
      return icon;
    }
    return _InboxCount(client: client, feed: feed, child: icon);
  }
}

/// Keeps the pending-message count fresh: fetched once, then refetched
/// when the feed reports a message change or comes back after a drop.
class _InboxCount extends StatefulWidget {
  const _InboxCount({
    required this.client,
    required this.feed,
    required this.child,
  });

  final TowerClient client;
  final LiveFeed feed;
  final Widget child;

  @override
  State<_InboxCount> createState() => _InboxCountState();
}

class _InboxCountState extends State<_InboxCount> {
  int _count = 0;
  StreamSubscription<TowerEvent>? _sub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _sub = widget.feed.events.listen((e) {
      if (e.kind.startsWith('message.')) _schedule();
    });
    widget.feed.status.addListener(_onStatus);
    _refresh();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    widget.feed.status.removeListener(_onStatus);
    super.dispose();
  }

  void _onStatus() {
    if (widget.feed.status.value == FeedStatus.live) _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _refresh);
  }

  Future<void> _refresh() async {
    try {
      final n = (await widget.client.inbox()).length;
      if (mounted) setState(() => _count = n);
    } catch (_) {
      // The Inbox tab shows the error; the badge just keeps its last count.
    }
  }

  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: _count > 0,
    label: Text('$_count'),
    child: widget.child,
  );
}
