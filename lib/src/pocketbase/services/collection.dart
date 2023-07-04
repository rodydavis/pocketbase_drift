import 'package:pocketbase_drift/pocketbase_drift.dart';

class $CollectionService extends $BaseService<CollectionModel>
    implements CollectionService {
  $CollectionService(super.client);

  late final _base = CollectionService(client);

  @override
  String get baseCrudPath => _base.baseCrudPath;

  late final dao = client.db.collectionsDao;

  @override
  Future<void> import(
    List<CollectionModel> collections, {
    bool deleteMissing = false,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.import(
      collections,
      deleteMissing: deleteMissing,
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  CollectionModel itemFactoryFunc(Map<String, dynamic> json) {
    return _base.itemFactoryFunc(json);
  }

  @override
  Future<List<CollectionModel>> getFullList({
    int batch = 200,
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) async {
    List<CollectionModel> items = [];

    if (fetchPolicy == FetchPolicy.networkOnly ||
        fetchPolicy == FetchPolicy.cacheAndNetwork) {
      try {
        items = await super.getFullList(
          batch: batch,
          expand: expand,
          filter: filter,
          fields: fields,
          sort: sort,
          query: query,
          headers: headers,
        );
      } catch (e) {
        throw Exception(
          'Failed to get collections $e',
        );
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork) {
      if (items.isNotEmpty) {
        await dao.addAll(items.map((e) => e.toModel()).toList());
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.cacheOnly) {
      if (items.isEmpty) {
        items = (await dao.getAll()).map((e) => e.toModel()).toList();
      }
    }

    return items;
  }

  @override
  Future<ResultList<CollectionModel>> getList({
    int page = 1,
    int perPage = 30,
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) async {
    ResultList<CollectionModel> result = ResultList(items: []);
    if (fetchPolicy == FetchPolicy.networkOnly ||
        fetchPolicy == FetchPolicy.cacheAndNetwork) {
      try {
        result = await super.getList(
          page: page,
          perPage: perPage,
          expand: expand,
          filter: filter,
          fields: fields,
          sort: sort,
          query: query,
          headers: headers,
        );
      } catch (e) {
        if (fetchPolicy == FetchPolicy.networkOnly) {
          throw Exception(
            'Failed to get collections $e',
          );
        }
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork) {
      if (result.items.isNotEmpty) {
        await dao.addAll(result.items.map((e) => e.toModel()).toList());
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.cacheOnly) {
      if (result.items.isEmpty) {
        final items = await dao.getAll(
          page: page,
          perPage: perPage,
        );
        final count = await dao.getCount();
        result = ResultList(
          page: page,
          perPage: perPage,
          items: items.map((e) => e.toModel()).toList(),
          totalItems: count,
          totalPages: (count / perPage).floor(),
        );
      }
    }

    return result;
  }
}
