/// One SSE subscription per ready session, fanned out to the screens.
///
/// Screens refetch their REST list when an event of interest arrives;
/// the feed carries no state of its own. When the stream drops the feed
/// goes [FeedStatus.down] and [reconnect] reopens it (cursor resume and
/// automatic retry come with M6).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'tower_client.dart';

enum FeedStatus { live, down }

class LiveFeed {
  LiveFeed(this._client) {
    _open();
  }

  final TowerClient _client;
  final _events = StreamController<TowerEvent>.broadcast();
  StreamSubscription<TowerEvent>? _sub;
  bool _disposed = false;

  /// Status of the subscription. A change back to [FeedStatus.live]
  /// tells listeners they may have missed events and should refetch.
  final ValueNotifier<FeedStatus> status = ValueNotifier(FeedStatus.live);

  /// Why the feed went down, when it did.
  String? error;

  Stream<TowerEvent> get events => _events.stream;

  void _open() {
    _sub = _client
        // Terminal output is the bulk of the traffic and no list needs it.
        .events(exclude: 'type:agent.output')
        .listen(
          _events.add,
          onError: (Object e) => _fail('$e'),
          onDone: () => _fail('event feed closed'),
          cancelOnError: true,
        );
  }

  void _fail(String message) {
    if (_disposed) return;
    error = message;
    status.value = FeedStatus.down;
  }

  /// Reopen after a drop.
  void reconnect() {
    if (_disposed || status.value == FeedStatus.live) return;
    _sub?.cancel();
    error = null;
    _open();
    status.value = FeedStatus.live;
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _events.close();
    status.dispose();
  }
}
