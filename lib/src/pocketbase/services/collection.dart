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
  }) {
    return fetchPolicy.fetch<List<CollectionModel>>(
      remote: () => _base.getFullList(
        batch: batch,
        expand: expand,
        filter: filter,
        fields: fields,
        sort: sort,
        query: query,
        headers: headers,
      ),
      getLocal: () async {
        final items = await dao.getAll();
        return items.map((e) => e.toModel()).toList();
      },
      setLocal: (value) async {
        for (final item in value) {
          await dao.updateItem(item.toModel(
            deleted: false,
            synced: null,
          ));
        }
      },
    );
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
  }) {
    return fetchPolicy.fetch<ResultList<CollectionModel>>(
      remote: () => _base.getList(
        page: page,
        perPage: perPage,
        expand: expand,
        filter: filter,
        fields: fields,
        sort: sort,
        query: query,
        headers: headers,
      ),
      getLocal: () async {
        final items = await dao.getAll(
          page: page,
          perPage: perPage,
        );
        final count = await dao.getCount();
        return ResultList(
          page: page,
          perPage: perPage,
          items: items.map((e) => e.toModel()).toList(),
          totalItems: count,
          totalPages: (count / perPage).floor(),
        );
      },
      setLocal: (value) async {
        for (final item in value.items) {
          await dao.updateItem(item.toModel(
            deleted: false,
            synced: null,
          ));
        }
      },
    );
  }

  @override
  Future<CollectionModel> getOne(
    String id, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) {
    return fetchPolicy.fetch<CollectionModel>(
      remote: () => _base.getOne(
        id,
        expand: expand,
        query: query,
        headers: headers,
        fields: fields,
      ),
      getLocal: () => dao.get(id).then((value) => value!.toModel()),
      setLocal: (value) => dao.updateItem(value.toModel(
        deleted: false,
        synced: null,
      )),
    );
  }

  @override
  Future<void> setLocal(List<CollectionModel> items) async {
    for (final item in items) {
      await client.db.collectionsDao.updateItem(item.toModel(
        deleted: false,
        synced: null,
        local: true,
      ));
    }
  }
}
