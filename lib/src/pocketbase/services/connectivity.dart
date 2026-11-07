import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Asynchronous probe that returns `true` when the PocketBase server can be
/// reached.
typedef ServerProbe = Future<bool> Function();

/// Realtime connectivity monitor for a PocketBase server.
///
/// Unlike generic "internet checkers" that poll external hosts, this service
/// tracks reachability of the *actual* PocketBase server by combining three
/// signals:
///
/// 1. **Interface events** ([connectivity_plus]): the OS reports wifi/cellular/
///    ethernet changes instantly. Losing the last interface marks the device
///    offline immediately; regaining one triggers an immediate probe.
/// 2. **Server probes**: a lightweight probe (usually `GET /api/health`)
///    confirms the server is actually reachable. While online, probes run at a
///    slow keepalive interval; while offline, they back off exponentially
///    ([offlineBackoffMin] doubling up to [offlineBackoffMax]) so restoration
///    is detected within seconds, not minutes.
/// 3. **Request outcomes**: real CRUD traffic reports back through
///    [reportNetworkSuccess] / [reportNetworkFailure] for instant state flips
///    without waiting for the next probe.
///
/// Each `$PocketBase` client owns its own instance so that apps talking to
/// multiple servers track each server independently.
class ConnectivityService {
  ConnectivityService({
    ServerProbe? probe,
    this.probeTimeout = const Duration(seconds: 5),
    this.onlineProbeInterval = const Duration(seconds: 60),
    this.offlineBackoffMin = const Duration(seconds: 5),
    this.offlineBackoffMax = const Duration(seconds: 60),
  })  : _probe = probe,
        _logger = Logger('ConnectivityService');

  /// Disables probes and interface listeners. Testing only.
  @visibleForTesting
  static bool enableProbes = true;

  /// Number of consecutive request failures before marking as offline.
  static const _failureThreshold = 2;

  final ServerProbe? _probe;
  final Duration probeTimeout;
  final Duration onlineProbeInterval;
  final Duration offlineBackoffMin;
  final Duration offlineBackoffMax;

  final _statusController = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _interfaceSubscription;
  Timer? _probeTimer;
  Future<void>? _inFlightProbe;
  int _consecutiveFailures = 0;
  int _backoffStep = 0;
  bool _started = false;
  bool _disposed = false;

  late final Logger _logger;

  /// Whether the OS currently reports a network interface (wifi/cellular/
  /// ethernet). Treated as `true` when the platform plugin is unavailable.
  bool _interfaceAvailable = true;

  /// The current server connectivity status. Optimistic: `true` unless
  /// proven otherwise, so UI banners don't flicker at app start.
  bool isConnected = true;

  /// A stream that emits `true` when the server is reachable and `false`
  /// otherwise. Each new listener first receives the current status; other
  /// listeners only see real status changes.
  Stream<bool> get statusStream => Stream<bool>.multi((listener) {
        listener.add(isConnected);
        final sub = _statusController.stream.listen(
          listener.add,
          onError: listener.addError,
          onDone: listener.close,
        );
        listener
          ..onPause = sub.pause
          ..onResume = sub.resume
          ..onCancel = sub.cancel;
      }, isBroadcast: true);

  /// Whether a network request should be attempted.
  ///
  /// `true` while any network interface is available, regardless of whether
  /// recent requests have succeeded. Used by the strict policies
  /// (`networkOnly`, `networkFirst` writes) that must try the server.
  bool get shouldAttemptNetwork => _interfaceAvailable;

  /// Whether the server is believed reachable: an interface is up and the
  /// last probe or request did not fail.
  ///
  /// Offline-first policies skip the network (and its timeouts) while this
  /// is `false` and serve or queue locally instead; probes keep running in
  /// the background and flip it back.
  bool get canReachServer => _interfaceAvailable && isConnected;

  /// Starts monitoring. Idempotent; called by the owning `$PocketBase` client.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    if (!enableProbes) return;
    _listenInterface();
    if (_canProbe) {
      _logger.info('Connectivity monitoring started. Probing server...');
      _scheduleProbe(Duration.zero);
    }
  }

  bool get _canProbe => _probe != null;

  void _listenInterface() {
    try {
      _interfaceSubscription ??= Connectivity().onConnectivityChanged.listen(
        _onInterfaceChange,
        onError: (Object e) {
          _logger.fine('Interface events unavailable: $e');
        },
      );
    } catch (e) {
      // Platform without the plugin (tests, unsupported platforms):
      // fall back to probe- and request-based detection only.
      _logger.fine('Interface events unavailable: $e');
    }
  }

  /// Re-arms interface listeners and probes an immediate server check.
  ///
  /// Useful when the app resumes from background, where OS plugins may have
  /// dropped events while suspended.
  void resetSubscription() {
    if (_disposed) return;
    _logger.info('Resetting connectivity listeners.');
    _interfaceSubscription?.cancel();
    _interfaceSubscription = null;
    if (!enableProbes) return;
    _listenInterface();
    if (_canProbe) {
      _scheduleProbe(Duration.zero);
    }
  }

  /// Runs an immediate server probe and updates the status from its result.
  Future<void> checkConnectivity() async {
    if (!_canProbe || _disposed || !enableProbes) return;
    await _runProbe();
  }

  /// Probes the server now (if not already probing) while it is believed
  /// unreachable, e.g. when the user queues a change offline.
  void probeSoon() {
    if (isConnected || _inFlightProbe != null || !_interfaceAvailable) return;
    _scheduleProbe(Duration.zero);
  }

  /// Releases listeners and timers. The service cannot be restarted.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _started = true;
    _cancelProbeTimer();
    _interfaceSubscription?.cancel();
    _interfaceSubscription = null;
    _statusController.close();
  }

  Future<void> _onInterfaceChange(List<ConnectivityResult> results) async {
    final available =
        results.isNotEmpty && results.any((r) => r != ConnectivityResult.none);
    if (available == _interfaceAvailable) {
      // Interface switched identity (e.g. wifi -> cellular). If we are
      // currently offline, verify the new network reaches the server.
      if (available && !isConnected) {
        _scheduleProbe(Duration.zero);
      }
      return;
    }
    _interfaceAvailable = available;
    if (!available) {
      _logger.info('Network interface lost. Marking as offline.');
      _cancelProbeTimer();
      _setConnected(false);
    } else {
      _logger.fine('Network interface available. Probing server...');
      _scheduleProbe(Duration.zero);
    }
  }

  void _scheduleProbe(Duration delay) {
    if (!_canProbe || _disposed || !enableProbes) return;
    _cancelProbeTimer();
    _probeTimer = Timer(delay, _runProbe);
  }

  Future<void> _runProbe() async {
    if (!_canProbe || _disposed || !enableProbes) return;
    final inFlight = _inFlightProbe;
    if (inFlight != null) {
      // A probe is already running; it will schedule the next one.
      await inFlight;
      return;
    }
    final done = Completer<void>();
    _inFlightProbe = done.future;
    try {
      var reachable = false;
      try {
        reachable = await _probe!().timeout(probeTimeout);
      } catch (e) {
        _logger.fine('Server probe failed: $e');
        reachable = false;
      }

      if (reachable) {
        _backoffStep = 0;
        if (!isConnected) {
          _logger.info('Server probe succeeded - connectivity restored.');
        }
        _setConnected(true);
        _scheduleProbe(onlineProbeInterval);
      } else {
        if (isConnected) {
          _logger.info('Server probe failed - marking as offline.');
        }
        _setConnected(false);
        // Schedule with the current step first (== offlineBackoffMin on the
        // first failure), then grow for subsequent failures.
        _scheduleProbe(_currentBackoff());
        _backoffStep = min(_backoffStep + 1, 20);
      }
    } finally {
      _inFlightProbe = null;
      done.complete();
    }
  }

  Duration _currentBackoff() {
    // Millisecond math so sub-second floors don't collapse to zero.
    final base = offlineBackoffMin.inMilliseconds;
    final shifted = base << min(_backoffStep, 16);
    final capped = min(max(shifted, base), offlineBackoffMax.inMilliseconds);
    return Duration(milliseconds: capped);
  }

  /// Report that a network request failed.
  /// After [_failureThreshold] consecutive failures, marks as offline.
  void reportNetworkFailure() {
    _consecutiveFailures++;
    _logger.fine(
      'Network failure reported ($_consecutiveFailures consecutive failures)',
    );

    if (_consecutiveFailures >= _failureThreshold && isConnected) {
      _logger.info('Multiple network failures detected, marking as offline.');
      _setConnected(false);
      // Verify recovery on the regular backoff schedule.
      _scheduleProbe(_currentBackoff());
    }
  }

  /// Report that a network request succeeded.
  /// This confirms connectivity is working and resets failure counters.
  void reportNetworkSuccess() {
    _consecutiveFailures = 0;
    _backoffStep = 0;

    if (!isConnected) {
      _logger.info('Network request succeeded - connectivity restored.');
      _setConnected(true);
      _scheduleProbe(onlineProbeInterval);
    }
  }

  void _setConnected(bool value) {
    if (value != isConnected) {
      isConnected = value;
      _consecutiveFailures = 0; // Reset on any state change
      if (!_statusController.isClosed) {
        _statusController.add(isConnected);
      }
      _logger.info('Status changed: ${isConnected ? "Online" : "Offline"}');
    }
  }

  void _cancelProbeTimer() {
    _probeTimer?.cancel();
    _probeTimer = null;
  }

  /// Directly set the connectivity status. Only use for testing.
  @visibleForTesting
  void setConnectivityStatus(bool status) {
    _interfaceAvailable = status;
    _setConnected(status);
  }
}
