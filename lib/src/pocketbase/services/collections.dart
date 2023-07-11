import '../../../pocketbase_drift.dart';

import 'service.dart';

class $CollectionsService extends $Service<CollectionModel>
    implements CollectionService {
  $CollectionsService($PocketBase client) : super(client, 'schema');

  late final _base = CollectionService(client);

  @override
  String get baseCrudPath => _base.baseCrudPath;

  @override
  CollectionModel itemFactoryFunc(Map<String, dynamic> json) {
    return _base.itemFactoryFunc(json);
  }

  @override
  Future<void> import(
    List<CollectionModel> collections, {
    bool deleteMissing = false,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    await setLocal(collections);
    return _base.import(
      collections,
      deleteMissing: deleteMissing,
      body: body,
      query: query,
      headers: headers,
    );
  }
}
