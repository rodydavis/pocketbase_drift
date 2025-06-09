import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logging/logging.dart';

/// A service that monitors the device's network connectivity status.
class ConnectivityService {
  ConnectivityService() {
    _logger = Logger('ConnectivityService');
    _subscription = Connectivity().onConnectivityChanged.listen(_updateStatus);
    // Get the initial status.
    checkConnectivity();
  }

  final _statusController = StreamController<bool>.broadcast();
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  late final Logger _logger;

  /// A stream that emits `true` if the device is connected to a network,
  /// and `false` otherwise.
  Stream<bool> get statusStream => _statusController.stream;

  /// The current network connectivity status.
  bool isConnected = true;

  /// Checks the current connectivity and updates the status.
  Future<void> checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    _updateStatus(result);
  }

  void _updateStatus(List<ConnectivityResult> result) {
    // We consider the device connected if it's not 'none'.
    final newStatus = !result.contains(ConnectivityResult.none);
    if (newStatus != isConnected) {
      isConnected = newStatus;
      _statusController.add(isConnected);
      _logger.info('Status changed: ${isConnected ? "Online" : "Offline"}');
    }
  }

  void dispose() {
    _subscription.cancel();
    _statusController.close();
  }
}
