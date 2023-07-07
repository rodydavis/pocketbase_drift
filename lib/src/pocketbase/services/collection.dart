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
  }) async {
    final existing = await dao.getAll();
    for (final item in collections) {
      await dao.createItem(item.toModel(
        deleted: false,
        synced: null,
      ));
    }
    if (deleteMissing) {
      final missing = existing.where((e) {
        return !collections.any((c) => c.id == e.id);
      });
      for (final item in missing) {
        await dao.deleteItem(item.id);
      }
    }
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
        items = await _base.getFullList(
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
        for (final item in items) {
          await dao.updateItem(item.toModel(
            deleted: false,
            synced: null,
          ));
        }
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
        result = await _base.getList(
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
        for (final item in result.items) {
          await dao.updateItem(item.toModel(
            deleted: false,
            synced: null,
          ));
        }
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

  @override
  Future<CollectionModel> getOne(
    String id, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) async {
    CollectionModel? record;
    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.networkOnly) {
      try {
        record = await _base.getOne(
          id,
          expand: expand,
          query: query,
          headers: headers,
          fields: fields,
        );
      } catch (e) {
        if (fetchPolicy == FetchPolicy.networkOnly) {
          throw Exception(
            'Failed to get collection $id $e',
          );
        }
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.cacheOnly) {
      final model = await dao.get(id);
      if (model != null) {
        record = model.toModel();
      }
    }

    if (record == null) {
      throw Exception(
        'Collection $id does not exist',
      );
    }

    return record;
  }

  @override
  Future<void> setLocal(List<CollectionModel> items) async {
    for (final item in items) {
      await client.db.collectionsDao.updateItem(item.toModel(
        deleted: false,
        synced: null,
      ));
    }
  }
}
