import 'package:pocketbase/pocketbase.dart';

import '../pocketbase.dart';

abstract class $BaseService<M extends Jsonable> extends BaseCrudService<M> {
  $BaseService(this.client) : super(client);

  @override
  final $PocketBase client;

  Future<void> setLocal(List<M> items);
}

enum FetchPolicy {
  cacheOnly,
  networkOnly,
  cacheAndNetwork,
}

extension FetchPolicyUtils on FetchPolicy {
  bool get isNetwork =>
      this == FetchPolicy.networkOnly || this == FetchPolicy.cacheAndNetwork;
  bool get isCache =>
      this == FetchPolicy.cacheOnly || this == FetchPolicy.cacheAndNetwork;

  Future<T> fetch<T>({
    required Future<T> Function() remote,
    required Future<T> Function() getLocal,
    required Future<void> Function(T) setLocal,
  }) async {
    T? result;

    if (isNetwork) {
      try {
        result = await remote();
      } catch (e) {
        if (this == FetchPolicy.networkOnly) {
          throw Exception('Failed to get $e');
        }
      }
    }

    if (isCache) {
      if (result != null) {
        await setLocal(result);
      } else {
        result = await getLocal();
      }
    }

    if (result == null) {
      throw Exception(
        'Failed to get',
      );
    }

    return result;
  }
}
