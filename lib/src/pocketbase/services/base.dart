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
