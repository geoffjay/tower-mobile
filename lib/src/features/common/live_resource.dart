/// Loads a REST resource and refetches it when the live feed reports a
/// change. Shared by the Fleet, Inbox, Jobs and Workflows screens.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/live_feed.dart';

class LiveResource<T> extends StatefulWidget {
  const LiveResource({
    super.key,
    required this.feed,
    required this.load,
    required this.kinds,
    required this.builder,
  });

  final LiveFeed feed;
  final Future<T> Function() load;

  /// Event kind prefixes that invalidate the data, e.g. `['task.']`.
  final List<String> kinds;

  /// Must return a scrollable (a `ListView`): pull-to-refresh wraps it.
  final Widget Function(BuildContext context, T data) builder;

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
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final data = _data;
    if (data == null) {
      return _ErrorView(error: '$_error', onRetry: _refresh);
    }
    return Column(
      children: [
        if (_error != null)
          MaterialBanner(
            content: Text('Refresh failed: $_error'),
            actions: [
              TextButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: widget.builder(context, data),
          ),
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
          Text(error, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
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

/// A small colored pill for a state name.
class StatePill extends StatelessWidget {
  const StatePill(this.label, this.color, {super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 12)),
  );
}

/// The empty-list row: scrollable so pull-to-refresh still works.
List<Widget> emptyRow(String text) => [
  Padding(
    padding: const EdgeInsets.only(top: 80),
    child: Center(child: Text(text)),
  ),
];
