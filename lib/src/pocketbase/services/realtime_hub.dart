import 'dart:async';

import 'package:logging/logging.dart';
import 'package:pocketbase/pocketbase.dart';

import '../pocketbase.dart';

/// A live query kept fresh by the [RealtimeHub].
abstract class LiveQuery {
  /// Whether realtime events for the query's topic must be written to the
  /// cache (false for `networkOnly` queries, which never use the cache).
  bool get writesCache;

  /// The hub's [RealtimeHub.connectEpoch] when the last refresh started.
  int get fetchEpoch;

  /// Whether the last refresh was skipped or failed because the server was
  /// unreachable.
  bool get isStale;

  /// Called for every realtime event of the query's topic, after the cache
  /// was updated.
  void onRealtimeEvent(RecordSubscriptionEvent event);

  /// Refetches the query from the server.
  Future<void> refresh();
}

class _Topic {
  _Topic(this.service, this.topic);

  final String service;
  final String topic;
  final queries = <LiveQuery>{};
  SubscriptionFunc? listener;

  /// Completes when the realtime subscription of [listener] is active.
  Future<UnsubscribeFunc>? subscription;

  String get key => '$service/$topic';
  bool get writesCache => queries.any((q) => q.writesCache);
}

/// Shares one realtime subscription per collection topic between all live
/// queries, writes each event to the cache once, and refreshes the queries
/// after the realtime connection is re-established or connectivity returns,
/// so changes made while disconnected are not missed.
class RealtimeHub {
  RealtimeHub(this.client);

  final $PocketBase client;
  final _topics = <String, _Topic>{};
  final _logger = Logger('PocketBaseDrift.realtime');

  /// Increments on every realtime (re)connect (`PB_CONNECT`).
  int connectEpoch = 0;

  SubscriptionFunc? _connectListener;
  Future<void> _events = Future.value();
  Timer? _refreshTimer;
  bool _disposed = false;

  /// Delay before reconnect refreshes run, so the SDK has re-submitted the
  /// subscriptions first and bursts of triggers coalesce.
  static const refreshDelay = Duration(milliseconds: 250);

  /// Adds [query] to the topic and returns once the realtime subscription is
  /// active. The future may take long (or fail) while the server is down;
  /// the subscription stays registered either way and activates when the
  /// connection is established.
  Future<void> attach(String service, String topic, LiveQuery query) async {
    if (_disposed) return;
    final key = '$service/$topic';
    final entry = _topics.putIfAbsent(key, () => _Topic(service, topic));
    entry.queries.add(query);

    if (_connectListener == null) {
      final onConnect = _connectListener = (_) => _onConnect();
      unawaited(
        client.realtime
            .subscribe('PB_CONNECT', onConnect)
            .then<void>(
              (_) {},
              onError: (Object e) {
                _logger.fine('Realtime connect listener not active yet', e);
              },
            ),
      );
    }
    if (entry.listener == null) {
      final listener = entry.listener = (message) {
        final RecordSubscriptionEvent event;
        try {
          event = RecordSubscriptionEvent.fromJson(message.jsonData());
        } catch (e) {
          _logger.warning('Malformed realtime message for $key', e);
          return;
        }
        _events = _events.then((_) => _dispatch(entry, event));
      };
      entry.subscription = client.realtime.subscribe(key, listener);
    }
    await entry.subscription;
  }

  /// Removes [query]; the realtime subscription closes with the last query.
  Future<void> detach(String service, String topic, LiveQuery query) async {
    final key = '$service/$topic';
    final entry = _topics[key];
    if (entry == null || !entry.queries.remove(query)) return;
    if (entry.queries.isNotEmpty) return;
    _topics.remove(key);
    _removeListener(key, entry.listener);
    if (_topics.isEmpty) _removeConnectListener();
  }

  void _removeConnectListener() {
    final listener = _connectListener;
    if (listener == null) return;
    _connectListener = null;
    _removeListener('PB_CONNECT', listener);
  }

  /// Removes [listener] right away, also while its subscribe still waits
  /// for the connection (the SDK drops the connection with the last one).
  void _removeListener(String key, SubscriptionFunc? listener) {
    if (listener == null) return;
    unawaited(
      client.realtime.unsubscribeByTopicAndListener(key, listener).catchError((
        Object e,
      ) {
        _logger.fine('Unsubscribing from $key failed (connection closed?)', e);
      }),
    );
  }

  Future<void> _dispatch(_Topic entry, RecordSubscriptionEvent event) async {
    // An event of a connection still authenticated as the previous account.
    if (_disposed || !client.realtimeMatchesSession) return;
    if (entry.writesCache) {
      try {
        await client.collection(entry.service).onEvent(event);
      } catch (e, st) {
        _logger.warning(
          'Realtime event for ${entry.service} not cached',
          e,
          st,
        );
      }
    }
    for (final query in entry.queries.toList()) {
      try {
        query.onRealtimeEvent(event);
      } catch (e, st) {
        _logger.warning('Live query failed to handle a realtime event', e, st);
      }
    }
  }

  void _onConnect() {
    connectEpoch++;
    _logger.fine('Realtime connected (epoch $connectEpoch)');
    scheduleRefresh();
  }

  /// Refreshes, after [refreshDelay], every query that missed the current
  /// connection epoch or is stale because the server was unreachable.
  void scheduleRefresh() {
    if (_disposed) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(refreshDelay, () {
      final queries = {for (final t in _topics.values) ...t.queries};
      for (final query in queries) {
        if (query.isStale || query.fetchEpoch < connectEpoch) {
          unawaited(query.refresh());
        }
      }
    });
  }

  /// Removes the hub's realtime listeners (the SDK closes the realtime
  /// connection when no other subscription is left) and stops handling
  /// events.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _refreshTimer?.cancel();
    final topics = _topics.values.toList();
    _topics.clear();
    for (final entry in topics) {
      _removeListener(entry.key, entry.listener);
    }
    _removeConnectListener();
  }
}
