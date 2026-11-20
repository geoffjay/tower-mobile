/// Loads a REST resource and refetches it when the live feed reports a
/// change. Shared by the Fleet, Inbox, Jobs and Workflows screens.
library;

import 'dart:async';

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../api/live_feed.dart';

class LiveResource<T> extends StatefulWidget {
  const LiveResource({
    super.key,
    required this.feed,
    required this.load,
    required this.kinds,
    this.builder,
    this.refreshableBuilder,
  }) : assert(
         builder != null || refreshableBuilder != null,
         'Provide builder or refreshableBuilder',
       );

  final LiveFeed feed;
  final Future<T> Function() load;

  /// Event kind prefixes that invalidate the data, e.g. `['task.']`.
  final List<String> kinds;

  /// Must return a scrollable (a `ListView`): pull-to-refresh wraps it.
  final Widget Function(BuildContext context, T data)? builder;

  /// Variant of [builder] that also receives an explicit [refresh] trigger
  /// for screens that mutate state in place.
  final Widget Function(
    BuildContext context,
    T data,
    Future<void> Function() refresh,
  )?
  refreshableBuilder;

  @override
  State<LiveResource<T>> createState() => _LiveResourceState<T>();
}

class _LiveResourceState<T> extends State<LiveResource<T>> {
  T? _data;
  Object? _error;
  var _loaded = false;
  var _generation = 0;
  StreamSubscription<Object?>? _sub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _attach();
    _refresh();
  }

  @override
  void didUpdateWidget(LiveResource<T> old) {
    super.didUpdateWidget(old);
    if (old.feed != widget.feed) {
      _detach(old.feed);
      _attach();
      _loaded = false;
      _data = null;
      _refresh();
    }
  }

  @override
  void dispose() {
    _detach(widget.feed);
    super.dispose();
  }

  void _attach() {
    _sub = widget.feed.events.listen((e) {
      if (widget.kinds.any(e.kind.startsWith)) _schedule();
    });
    widget.feed.status.addListener(_onStatus);
  }

  void _detach(LiveFeed feed) {
    _sub?.cancel();
    _debounce?.cancel();
    feed.status.removeListener(_onStatus);
  }

  /// Back to live after a drop: events may have been missed.
  void _onStatus() {
    if (widget.feed.status.value == FeedStatus.live) _schedule();
  }

  /// A burst of events collapses into one refetch.
  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _refresh);
  }

  Future<void> _refresh() async {
    final gen = ++_generation;
    try {
      final data = await widget.load();
      if (!mounted || gen != _generation) return;
      setState(() {
        _data = data;
        _error = null;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: M3ELoadingIndicator());
    final data = _data;
    if (data == null) {
      return _ErrorView(error: '$_error', onRetry: _refresh);
    }
    final child = widget.refreshableBuilder != null
        ? widget.refreshableBuilder!(context, data, _refresh)
        : widget.builder!(context, data);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (_error != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Refresh failed: $_error',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
                TextButton(onPressed: _refresh, child: const Text('Retry')),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(onRefresh: _refresh, child: child),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 40,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(error, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          M3EButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

/// Relative time for ms-epoch timestamps: `just now`, `5m ago`, `3h ago`.
String timeAgo(int epochMs) {
  final d = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(epochMs),
  );
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 48) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// Semantic status role, harmonized against the active dynamic color scheme.
enum StatusTone { neutral, active, positive, warning, danger }

/// Resolve `(container, onContainer, indicator)` colors for [tone] at the
/// active brightness, harmonized with wallpaper/seed primary.
({Color container, Color onContainer, Color dot}) resolveStatusColors(
  BuildContext context,
  StatusTone tone,
) {
  final scheme = Theme.of(context).colorScheme;
  switch (tone) {
    case StatusTone.neutral:
      return (
        container: scheme.surfaceContainerHighest,
        onContainer: scheme.onSurfaceVariant,
        dot: scheme.outline,
      );
    case StatusTone.danger:
      return (
        container: scheme.errorContainer,
        onContainer: scheme.onErrorContainer,
        dot: scheme.error,
      );
    case StatusTone.active:
      return _harmonizedRole(scheme, const Color(0xFF1976D2));
    case StatusTone.positive:
      return _harmonizedRole(scheme, const Color(0xFF2E7D32));
    case StatusTone.warning:
      return _harmonizedRole(scheme, const Color(0xFFED6C02));
  }
}

({Color container, Color onContainer, Color dot}) _harmonizedRole(
  ColorScheme active,
  Color seed,
) {
  final harmonized = seed.harmonizeWith(active.primary);
  final derived = ColorScheme.fromSeed(
    seedColor: harmonized,
    brightness: active.brightness,
  );
  return (
    container: derived.primaryContainer,
    onContainer: derived.onPrimaryContainer,
    dot: derived.primary,
  );
}

/// A borderless M3 tonal pill for a state name, harmonized to the theme.
class StatePill extends StatelessWidget {
  const StatePill(this.label, this.tone, {this.showDot = false, super.key});

  final String label;
  final StatusTone tone;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final colors = resolveStatusColors(context, tone);
    final withDot = showDot || tone == StatusTone.active;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.container,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (withDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: colors.dot,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.onContainer,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Leading circular status dot for list items.
class StatusLeadingDot extends StatelessWidget {
  const StatusLeadingDot(this.tone, {super.key});

  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = resolveStatusColors(context, tone);
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.container,
        shape: BoxShape.circle,
      ),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: colors.dot, shape: BoxShape.circle),
      ),
    );
  }
}

/// Scrollable empty-state view so pull-to-refresh still works.
List<Widget> emptyRow(
  String text, {
  IconData icon = Icons.inbox_outlined,
  String? subtitle,
}) => [
  Padding(
    padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
    child: Builder(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 26, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: textTheme.titleSmall?.copyWith(color: scheme.onSurface),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
      },
    ),
  ),
];
