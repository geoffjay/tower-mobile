/// App shell: 4-tab operational navigation (Fleet, Inbox, Jobs, Workflows)
/// with an interactive host switcher pill in the app bar and a live
/// connection/recovery banner.
library;

import 'dart:async';

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../api/live_feed.dart';
import '../../api/models.dart';
import '../../api/tower_client.dart';
import '../../connection/registry.dart';
import '../../connection/session.dart';
import '../common/live_resource.dart';
import '../fleet/fleet_screen.dart';
import '../inbox/inbox_screen.dart';
import '../jobs/jobs_screen.dart';
import '../machines/machines_screen.dart';
import '../workflows/workflows_screen.dart';

/// Primary operational screens in bottom-navigation order.
enum AppTab { fleet, inbox, jobs, workflows }

/// Scaffold with M3 Expressive navigation, native Inbox badge counter, and
/// app-bar host switcher.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.registry, required this.session});

  final MachineRegistry registry;
  final SessionController session;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  AppTab _tab = AppTab.fleet;

  int _inboxCount = 0;
  LiveFeed? _watchedFeed;
  TowerClient? _watchedClient;
  StreamSubscription<SessionState>? _sessionSub;
  StreamSubscription<TowerEvent>? _feedSub;
  Timer? _inboxDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncInboxWatcher(widget.session.state);
    _sessionSub = widget.session.listen(_syncInboxWatcher);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionSub?.cancel();
    _detachFeed();
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

  void _syncInboxWatcher(SessionState state) {
    final ready = state.phase == SessionPhase.ready;
    final feed = ready ? state.feed : null;
    final client = ready ? state.client : null;
    if (identical(feed, _watchedFeed) && identical(client, _watchedClient)) {
      return;
    }
    _detachFeed();
    _watchedFeed = feed;
    _watchedClient = client;
    if (feed == null || client == null) {
      if (_inboxCount != 0 && mounted) {
        setState(() => _inboxCount = 0);
      }
      return;
    }
    _feedSub = feed.events.listen((e) {
      if (e.kind.startsWith('message.')) _scheduleInboxRefresh();
    });
    feed.status.addListener(_onFeedStatus);
    _refreshInboxCount();
  }

  void _detachFeed() {
    _feedSub?.cancel();
    _feedSub = null;
    _inboxDebounce?.cancel();
    _inboxDebounce = null;
    _watchedFeed?.status.removeListener(_onFeedStatus);
    _watchedFeed = null;
    _watchedClient = null;
  }

  void _onFeedStatus() {
    if (_watchedFeed?.status.value == FeedStatus.live) {
      _scheduleInboxRefresh();
    }
  }

  void _scheduleInboxRefresh() {
    _inboxDebounce?.cancel();
    _inboxDebounce = Timer(
      const Duration(milliseconds: 300),
      _refreshInboxCount,
    );
  }

  Future<void> _refreshInboxCount() async {
    final client = _watchedClient;
    if (client == null) return;
    try {
      final n = (await client.inbox()).length;
      if (mounted && identical(client, _watchedClient) && n != _inboxCount) {
        setState(() => _inboxCount = n);
      }
    } catch (_) {
      // The Inbox screen displays errors; the badge keeps its last count.
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
        final content = ready
            ? switch (_tab) {
                AppTab.fleet => FleetScreen(
                  client: state.client!,
                  feed: state.feed!,
                ),
                AppTab.inbox => InboxScreen(
                  client: state.client!,
                  feed: state.feed!,
                ),
                AppTab.jobs => JobsScreen(
                  client: state.client!,
                  feed: state.feed!,
                ),
                AppTab.workflows => WorkflowsScreen(
                  client: state.client!,
                  feed: state.feed!,
                ),
              }
            : _NotConnectedView(
                registry: widget.registry,
                session: session,
                state: state,
                onStateChanged: () => setState(() {}),
              );
        return Scaffold(
          appBar: M3EAppBar.top(
            title: Text(_titleFor(_tab)),
            actions: [
              if (ready) _FeedDropButton(state.feed!),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _HostSwitcherChip(
                  registry: widget.registry,
                  session: session,
                  state: state,
                  onClosed: () => setState(() {}),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              _SessionStatusBanner(
                registry: widget.registry,
                session: session,
                state: state,
              ),
              Expanded(child: content),
            ],
          ),
          bottomNavigationBar: M3ENavigationBar(
            selectedIndex: _tab.index,
            onDestinationSelected: (i) =>
                setState(() => _tab = AppTab.values[i]),
            destinations: [
              const M3ENavigationBarDestination(
                icon: Icon(Icons.people_outline_rounded),
                selectedIcon: Icon(Icons.people_rounded),
                label: 'Fleet',
              ),
              M3ENavigationBarDestination(
                icon: const Icon(Icons.inbox_outlined),
                selectedIcon: const Icon(Icons.inbox_rounded),
                label: 'Inbox',
                badgeCount: ready && _inboxCount > 0 ? _inboxCount : null,
              ),
              const M3ENavigationBarDestination(
                icon: Icon(Icons.work_outline_rounded),
                selectedIcon: Icon(Icons.work_rounded),
                label: 'Jobs',
              ),
              const M3ENavigationBarDestination(
                icon: Icon(Icons.account_tree_outlined),
                selectedIcon: Icon(Icons.account_tree_rounded),
                label: 'Workflows',
              ),
            ],
          ),
        );
      },
    );
  }

  String _titleFor(AppTab tab) => switch (tab) {
    AppTab.fleet => 'Fleet',
    AppTab.inbox => 'Inbox',
    AppTab.jobs => 'Jobs',
    AppTab.workflows => 'Workflows',
  };
}

/// Interactive pill in the top app bar showing the active host and live
/// connection/feed state. Tapping opens the host switcher sheet.
class _HostSwitcherChip extends StatelessWidget {
  const _HostSwitcherChip({
    required this.registry,
    required this.session,
    required this.state,
    required this.onClosed,
  });

  final MachineRegistry registry;
  final SessionController session;
  final SessionState state;
  final VoidCallback onClosed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final machines = registry.machines();
    final label =
        state.machine?.name ??
        (machines.isEmpty ? 'Add host' : machines.first.name);
    final feed = state.feed;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await showMachinesSheet(
            context,
            registry: registry,
            session: session,
          );
          onClosed();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIndicator(context, feed),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIndicator(BuildContext context, LiveFeed? feed) {
    switch (state.phase) {
      case SessionPhase.connecting:
      case SessionPhase.connected:
        return const SizedBox(
          width: 12,
          height: 12,
          child: M3ELoadingIndicator(),
        );
      case SessionPhase.ready:
        if (feed == null) return _dot(context, StatusTone.positive);
        return ValueListenableBuilder<FeedStatus>(
          valueListenable: feed.status,
          builder: (context, status, _) => _dot(
            context,
            status == FeedStatus.live
                ? StatusTone.positive
                : StatusTone.warning,
          ),
        );
      case SessionPhase.failed:
        return _dot(context, StatusTone.danger);
      case SessionPhase.disconnected:
        return _dot(context, StatusTone.neutral);
    }
  }

  Widget _dot(BuildContext context, StatusTone tone) {
    final color = resolveStatusColors(context, tone).dot;
    return Semantics(
      label: tone == StatusTone.positive ? 'Live updates on' : null,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// One-tap reconnect button shown in the app bar only when the SSE feed drops
/// while the SSH tunnel is still up.
class _FeedDropButton extends StatelessWidget {
  const _FeedDropButton(this.feed);

  final LiveFeed feed;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<FeedStatus>(
    valueListenable: feed.status,
    builder: (context, status, _) {
      if (status == FeedStatus.live) return const SizedBox.shrink();
      final warn = resolveStatusColors(context, StatusTone.warning).dot;
      return IconButton(
        tooltip: '${feed.error ?? 'Live updates paused'} - tap to reconnect',
        icon: Icon(Icons.sync_problem_rounded, color: warn),
        onPressed: feed.reconnect,
      );
    },
  );
}

/// Shell-wide strip surfacing `SessionState.error`, including M6's
/// `"connection to <host> lost; reconnecting (n/5)"` progress.
class _SessionStatusBanner extends StatelessWidget {
  const _SessionStatusBanner({
    required this.registry,
    required this.session,
    required this.state,
  });

  final MachineRegistry registry;
  final SessionController session;
  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final err = state.error;
    final machine = state.machine;
    if (err == null ||
        machine == null ||
        (state.phase != SessionPhase.connecting &&
            state.phase != SessionPhase.failed)) {
      return const SizedBox.shrink();
    }
    final reconnecting = state.phase == SessionPhase.connecting;
    final tone = reconnecting ? StatusTone.warning : StatusTone.danger;
    final colors = resolveStatusColors(context, tone);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.container,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (reconnecting)
            const SizedBox(width: 16, height: 16, child: M3ELoadingIndicator())
          else
            Icon(Icons.error_outline_rounded, size: 18, color: colors.dot),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              err,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onContainer),
            ),
          ),
          TextButton(
            onPressed: () => connectMachineWithPrompt(
              context,
              registry: registry,
              session: session,
              machine: machine,
              forcePassword: state.needsPassword,
            ),
            child: Text(reconnecting ? 'Retry now' : 'Reconnect'),
          ),
        ],
      ),
    );
  }
}

/// Actionable empty state when no session is ready yet.
class _NotConnectedView extends StatelessWidget {
  const _NotConnectedView({
    required this.registry,
    required this.session,
    required this.state,
    required this.onStateChanged,
  });

  final MachineRegistry registry;
  final SessionController session;
  final SessionState state;
  final VoidCallback onStateChanged;

  StoredMachine? _preferredTarget(List<StoredMachine> machines) {
    if (state.machine != null) return state.machine;
    final activeId = registry.activeMachineId();
    if (activeId != null) {
      for (final m in machines) {
        if (m.id == activeId) return m;
      }
    }
    return machines.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (state.phase == SessionPhase.connecting ||
        state.phase == SessionPhase.connected) {
      final hostName = state.machine?.name ?? 'host';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const M3ELoadingIndicator(),
              const SizedBox(height: 16),
              Text('Connecting to $hostName…', style: textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Opening SSH tunnel and verifying tower API',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final machines = registry.machines();
    final target = _preferredTarget(machines);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: M3ECard(
          variant: M3ECardVariant.filled,
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          focusable: false,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.dns_rounded,
                  size: 28,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                target == null
                    ? 'No tower host configured'
                    : 'Disconnected from ${target.name}',
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                target == null
                    ? 'Add a machine over SSH. Your password is used once to '
                          'install this device\'s Ed25519 key.'
                    : '${target.username}@${target.host}:${target.port}',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              if (target == null)
                M3EButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  onPressed: () async {
                    final added = await showAddMachineDialog(context, registry);
                    if (added == null || !context.mounted) return;
                    onStateChanged();
                    await connectMachineWithPrompt(
                      context,
                      registry: registry,
                      session: session,
                      machine: added,
                    );
                  },
                  label: const Text('Add tower host'),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    M3EButton.icon(
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      onPressed: () => connectMachineWithPrompt(
                        context,
                        registry: registry,
                        session: session,
                        machine: target,
                        forcePassword: state.needsPassword,
                      ),
                      label: Text('Connect ${target.name}'),
                    ),
                    M3EButton(
                      style: M3EButtonStyle.tonal,
                      onPressed: () async {
                        await showMachinesSheet(
                          context,
                          registry: registry,
                          session: session,
                        );
                        onStateChanged();
                      },
                      child: const Text('Switch host'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
