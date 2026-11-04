import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';

/// SharedPreferences provider (overridden at app startup in main.dart).
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope at startup.',
  );
});

/// Active request policy provider with local persistence.
final activeRequestPolicyProvider =
    StateNotifierProvider<RequestPolicyNotifier, RequestPolicy>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return RequestPolicyNotifier(prefs);
});

class RequestPolicyNotifier extends StateNotifier<RequestPolicy> {
  RequestPolicyNotifier(this._prefs) : super(_loadInitialPolicy(_prefs));

  final SharedPreferences _prefs;

  static RequestPolicy _loadInitialPolicy(SharedPreferences prefs) {
    final saved = prefs.getString(AppConstants.keyRequestPolicy);
    if (saved != null) {
      return RequestPolicy.values.firstWhere(
        (p) => p.name == saved,
        orElse: () => RequestPolicy.cacheAndNetwork,
      );
    }
    return RequestPolicy.cacheAndNetwork;
  }

  void setPolicy(RequestPolicy policy) {
    state = policy;
    _prefs.setString(AppConstants.keyRequestPolicy, policy.name);
  }
}

/// Creates the PocketBase client backed by Drift SQLite and caches the
/// collection schema before returning, so validation and the first queries
/// (including seeding) already see every collection.
Future<$PocketBase> createPocketBaseClient(
  SharedPreferences prefs,
  String schemaJson,
) async {
  final client = $PocketBase.database(
    AppConstants.defaultServerUrl,
    authStore: $AuthStore.prefs(prefs, AppConstants.keyPbAuth),
    dbName: AppConstants.databaseName,
    cacheTtl: const Duration(days: 30),
  );
  await client.setSchema(schemaJson);
  return client;
}

/// Core PocketBase client provider (overridden at app startup in main.dart
/// with the client from [createPocketBaseClient]).
final pocketBaseProvider = Provider<$PocketBase>((ref) {
  throw UnimplementedError(
    'pocketBaseProvider must be overridden in ProviderScope at startup.',
  );
});

/// Stream of connectivity status (online / offline).
final connectivityStatusProvider = StreamProvider<bool>((ref) {
  final client = ref.watch(pocketBaseProvider);
  return client.connectivity.statusStream;
});
