/// One SSE subscription per ready session, fanned out to the screens.
///
/// Screens refetch their REST list when an event of interest arrives;
/// the feed carries no state of its own beyond the resume cursor. When
/// the stream drops the feed goes [FeedStatus.down] and retries with
/// backoff, resuming after the last seen event. [pause] and [resume]
/// close and reopen it around app backgrounding.
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

  /// Retry delays double up to this cap.
  static const _maxBackoff = Duration(seconds: 30);

  /// A stream that stayed up this long counts as healthy: the next drop
  /// retries at once instead of continuing the backoff.
  static const _stable = Duration(seconds: 20);

  final TowerClient _client;
  final _events = StreamController<TowerEvent>.broadcast();
  StreamSubscription<TowerEvent>? _sub;
  Timer? _retry;
  DateTime _openedAt = DateTime.now();
  int _attempt = 0;
  int? _cursor;
  bool _paused = false;
  bool _disposed = false;

  /// Status of the subscription. A change back to [FeedStatus.live]
  /// tells listeners they may have missed events and should refetch.
  final ValueNotifier<FeedStatus> status = ValueNotifier(FeedStatus.live);

  /// Why the feed went down, when it did.
  String? error;

  Stream<TowerEvent> get events => _events.stream;

  void _open() {
    _openedAt = DateTime.now();
    _sub = _client
        // Terminal output is the bulk of the traffic and no list needs it.
        .events(exclude: 'type:agent.output', cursor: _cursor)
        .listen(
          (e) {
            _cursor = e.seq;
            _events.add(e);
          },
          onError: (Object e) => _fail('$e'),
          onDone: () => _fail('event feed closed'),
          cancelOnError: true,
        );
  }

  void _fail(String message) {
    if (_disposed || _paused) return;
    error = message;
    status.value = FeedStatus.down;
    if (DateTime.now().difference(_openedAt) >= _stable) _attempt = 0;
    final delay = Duration(
      seconds: (1 << _attempt.clamp(0, 5)).clamp(1, _maxBackoff.inSeconds),
    );
    _attempt++;
    _retry?.cancel();
    _retry = Timer(delay, reconnect);
  }

  /// Reopen now (the retry timer and the app-bar indicator call this).
  void reconnect() {
    if (_disposed || _paused || status.value == FeedStatus.live) return;
    _retry?.cancel();
    _sub?.cancel();
    error = null;
    _open();
    status.value = FeedStatus.live;
  }

  /// Close the stream while the app is in the background. Down, so the
  /// next [resume] is a change that makes screens refetch.
  void pause() {
    if (_disposed || _paused) return;
    _paused = true;
    _retry?.cancel();
    _sub?.cancel();
    _sub = null;
    error = 'paused';
    status.value = FeedStatus.down;
  }

  void resume() {
    if (_disposed || !_paused) return;
    _paused = false;
    _attempt = 0;
    reconnect();
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _sub?.cancel();
    _events.close();
    status.dispose();
  }
}
