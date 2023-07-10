import '../../../pocketbase_drift.dart';
import '../../database/daos/admins.dart';

class $AdminService extends $BaseService<AdminModel> implements AdminService {
  $AdminService(super.client);

  late final _base = AdminService(client);

  @override
  String get baseCrudPath => _base.baseCrudPath;

  late final dao = client.db.adminsDao;

  @override
  AdminModel itemFactoryFunc(Map<String, dynamic> json) {
    return _base.itemFactoryFunc(json);
  }

  @override
  Future<List<AdminModel>> getFullList({
    int batch = 200,
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) {
    return fetchPolicy.fetch<List<AdminModel>>(
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
        final items = await dao.getAll(
          fields: fields,
          filter: filter,
          sort: sort,
          expand: expand,
        );
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
  Future<ResultList<AdminModel>> getList({
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
    return fetchPolicy.fetch<ResultList<AdminModel>>(
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
          fields: fields,
          filter: filter,
          sort: sort,
          expand: expand,
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
  Future<AdminModel> getOne(
    String id, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) {
    return fetchPolicy.fetch<AdminModel>(
      remote: () => _base.getOne(
        id,
        expand: expand,
        query: query,
        headers: headers,
        fields: fields,
      ),
      getLocal: () => dao
          .get(
            id,
            fields: fields,
            expand: expand,
          )
          .then((value) => value!.toModel()),
      setLocal: (value) => dao.updateItem(value.toModel(
        deleted: false,
        synced: null,
      )),
    );
  }

  @override
  Future<void> setLocal(List<AdminModel> items) async {
    for (final item in items) {
      await client.db.adminsDao.updateItem(item.toModel(
        deleted: false,
        synced: null,
        local: true,
      ));
    }
  }

  @override
  Future<AdminAuth> authWithPassword(
    String email,
    String password, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.authWithPassword(
      email,
      password,
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  Future<void> confirmPasswordReset(
    String passwordResetToken,
    String password,
    String passwordConfirm, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.confirmPasswordReset(
      passwordResetToken,
      password,
      passwordConfirm,
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  Future<AdminAuth> refresh({
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.refresh(
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  Future<void> requestPasswordReset(
    String email, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.requestPasswordReset(
      email,
      body: body,
      query: query,
      headers: headers,
    );
  }
}
