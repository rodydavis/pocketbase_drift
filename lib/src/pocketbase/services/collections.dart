import '../../../pocketbase_drift.dart';

class $CollectionService extends CollectionService with ServiceMixin<CollectionModel> {
  $CollectionService(this.client) : super(client);

  @override
  final $PocketBase client;

  @override
  final String service = 'schema';
}
