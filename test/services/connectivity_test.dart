import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectivityService', () {
    setUp(() {
      ConnectivityService.enableProbes = true;
    });

    test('probes immediately on start and schedules keepalive probes', () {
      fakeAsync((async) {
        var probes = 0;
        final service = ConnectivityService(
          probe: () async {
            probes++;
            return true;
          },
          onlineProbeInterval: const Duration(seconds: 10),
        );
        service.start();
        async.elapse(const Duration(milliseconds: 1));
        expect(probes, 1, reason: 'An initial probe runs immediately.');
        expect(service.isConnected, isTrue);

        async.elapse(const Duration(seconds: 10));
        expect(probes, 2, reason: 'Keepalive probes run while online.');

        service.dispose();
      });
    });

    test('marks offline on failed probes and recovers via backoff', () {
      fakeAsync((async) {
        var reachable = false;
        var probes = 0;
        final events = <bool>[];
        final service = ConnectivityService(
          probe: () async {
            probes++;
            return reachable;
          },
          offlineBackoffMin: const Duration(seconds: 5),
          offlineBackoffMax: const Duration(seconds: 20),
        );
        service.statusStream.listen(events.add);
        service.start();

        async.elapse(const Duration(milliseconds: 1));
        expect(probes, 1);
        expect(service.isConnected, isFalse,
            reason: 'A failed probe marks the server as unreachable.');
        expect(events, contains(false));

        // First backoff probe after offlineBackoffMin.
        async.elapse(const Duration(seconds: 6));
        expect(probes, 2);

        // Second backoff doubles to 10s; the server comes back.
        reachable = true;
        async.elapse(const Duration(seconds: 11));
        expect(probes, 3);
        expect(service.isConnected, isTrue);
        expect(events.last, isTrue);

        service.dispose();
      });
    });

    test('request outcomes flip the status instantly', () async {
      final service = ConnectivityService();
      final events = <bool>[];
      service.statusStream.listen(events.add);
      await Future<void>.delayed(Duration.zero);

      expect(service.isConnected, isTrue,
          reason: 'Optimistic online default.');

      service.reportNetworkFailure();
      await Future<void>.delayed(Duration.zero);
      expect(service.isConnected, isTrue,
          reason: 'A single failure is not enough to go offline.');

      service.reportNetworkFailure();
      await Future<void>.delayed(Duration.zero);
      expect(service.isConnected, isFalse,
          reason: 'Consecutive failures mark the service offline.');
      expect(events.last, isFalse);

      service.reportNetworkSuccess();
      await Future<void>.delayed(Duration.zero);
      expect(service.isConnected, isTrue);
      expect(events.last, isTrue);

      service.dispose();
    });

    test('new listeners immediately receive the current status', () async {
      final service = ConnectivityService();
      service.setConnectivityStatus(false);

      expect(await service.statusStream.first, isFalse);

      service.dispose();
    });

    test('setConnectivityStatus drives both interface and status', () {
      final service = ConnectivityService();
      final events = <bool>[];
      service.statusStream.listen(events.add);

      service.setConnectivityStatus(false);
      expect(service.shouldAttemptNetwork, isFalse,
          reason:
              'Without a network interface, requests should not be attempted.');
      expect(service.isConnected, isFalse);

      service.setConnectivityStatus(true);
      expect(service.shouldAttemptNetwork, isTrue);
      expect(service.isConnected, isTrue);

      service.dispose();
    });

    test('dispose stops probes and closes the status stream', () {
      fakeAsync((async) {
        var probes = 0;
        final service = ConnectivityService(
          probe: () async {
            probes++;
            return false;
          },
          offlineBackoffMin: const Duration(milliseconds: 10),
        );
        service.start();
        async.elapse(const Duration(milliseconds: 1));
        final probesAtDispose = probes;
        service.dispose();
        async.elapse(const Duration(seconds: 5));
        expect(probes, probesAtDispose,
            reason: 'No probes may run after dispose.');
      });
    });
  });
}
