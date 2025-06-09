import '../../../pocketbase_drift.dart';

class $CollectionService extends CollectionService
    with ServiceMixin<CollectionModel> {
  $CollectionService(this.client) : super(client);

  @override
  final $PocketBase client;

  @override
  final String service = 'schema';

  @override
  Future<CollectionModel> getOne(
    String id, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    return requestPolicy.fetch<CollectionModel>(
      label: service,
      client: client,
      remote: () {
        // We bypass the ServiceMixin.getOne by replicating the base network call.
        // This prevents a nested requestPolicy.fetch with the wrong policy.
        final path = '/api/collections/${Uri.encodeComponent(id)}';
        final q = Map<String, dynamic>.of(query);
        q['expand'] ??= expand;
        q['fields'] ??= fields;
        return client
            .send(
              path,
              query: q,
              headers: headers,
            )
            .then((data) => itemFactoryFunc(data));
      },
      getLocal: () async {
        final result = await client.db
            .$query(
              service,
              expand: expand,
              fields: fields,
              filter: "id = '$id'",
            )
            .getSingleOrNull();
        if (result == null) {
          throw Exception(
            'Record ($id) not found in collection $service [cache]',
          );
        }
        return itemFactoryFunc(result);
      },
      setLocal: (value) async {
        await client.db.setLocal(
          service,
          [value.toJson()],
          removeAll: false,
        );
      },
    );
  }

  @override
  Future<CollectionModel> getFirstListItem(
    String filter, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) {
    return requestPolicy.fetch<CollectionModel>(
      label: service,
      client: client,
      remote: () {
        return getList(
          perPage: 1,
          filter: filter,
          expand: expand,
          fields: fields,
          query: query,
          headers: headers,
          requestPolicy: requestPolicy,
        ).then((result) {
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
        });
      },
      getLocal: () async {
        final item = await client.db
            .$query(
              service,
              expand: expand,
              fields: fields,
              filter: filter,
            )
            .getSingleOrNull();
        if (item == null) {
          throw Exception(
            'No item found for filter "$filter" in collection $service [cache]',
          );
        }
        return itemFactoryFunc(item);
      },
      setLocal: (value) async {
        await client.db.setLocal(
          service,
          [value.toJson()],
          removeAll: false,
        );
      },
    );
  }
}
