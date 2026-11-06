import '../../../pocketbase_drift.dart';

class $CollectionService extends CollectionService
    with ServiceMixin<CollectionModel> {
  $CollectionService(this.client) : super(client);

  @override
  final $PocketBase client;

  @override
  final String service = 'schema';

  Future<void> _cache(CollectionModel value) =>
      client.db.setLocal(service, [value.toJson()], removeAll: false);

  @override
  Future<CollectionModel> getOne(
    String id, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy? requestPolicy,
  }) async {
    final policy = resolvePolicy(requestPolicy);
    return policy.fetch<CollectionModel>(
      label: '$service/$id',
      client: client,
      remote: () {
        // The base network call; ServiceMixin.getOne would nest a second
        // policy fetch.
        final path = '/api/collections/${Uri.encodeComponent(id)}';
        final q = Map<String, dynamic>.of(query);
        q['expand'] ??= expand;
        q['fields'] ??= fields;
        return client
            .send(path, query: q, headers: headers)
            .then((data) => itemFactoryFunc(data));
      },
      getLocal: () async {
        final local =
            await client.db.collectionById(id) ??
            await client.db.collectionByName(id);
        if (local == null) {
          throw CacheMissException('Collection ($id) not found [cache]');
        }
        return local;
      },
      setLocal: _cache,
    );
  }

  @override
  Future<CollectionModel> getFirstListItem(
    String filter, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy? requestPolicy,
  }) {
    final policy = resolvePolicy(requestPolicy);
    return policy.fetch<CollectionModel>(
      label: '$service "$filter"',
      client: client,
      remote: () async {
        final result = await getList(
          perPage: 1,
          skipTotal: true,
          filter: filter,
          expand: expand,
          fields: fields,
          query: query,
          headers: headers,
          requestPolicy: RequestPolicy.networkOnly,
        );
        if (result.items.isEmpty) {
          throw ClientException(
            statusCode: 404,
            response: <String, dynamic>{
              "code": 404,
              "message": "The requested resource wasn't found.",
              "data": <String, dynamic>{},
            },
          );
        }
        return result.items.first;
      },
      getLocal: () async {
        final items = await client.db
            .$query(
              service,
              expand: expand,
              fields: fields,
              filter: filter,
              limit: 1,
            )
            .get();
        if (items.isEmpty) {
          throw CacheMissException('No collection matches "$filter" [cache]');
        }
        return itemFactoryFunc(items.first);
      },
      setLocal: _cache,
    );
  }
}
