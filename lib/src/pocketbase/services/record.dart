// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import "package:http/http.dart" as http;
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../database/database.dart';
import 'base.dart';

class $RecordService extends $BaseService<RecordModel>
    implements RecordService {
  $RecordService(super.client, this.collection);

  final CollectionModel collection;

  late final dao = client.db.recordsDao;

  late final _base = RecordService(client, collection.id);

  @override
  String get baseCrudPath => _base.baseCrudPath;

  @override
  RecordModel itemFactoryFunc(Map<String, dynamic> json) {
    return _base.itemFactoryFunc(json);
  }

  @override
  Future<void> setLocal(List<RecordModel> items) async {
    for (final item in items) {
      await client.db.recordsDao.updateItem(item.toModel(
        deleted: false,
        synced: null,
        local: true,
      ));
    }
  }

  Future<List<Record>> getPending() async {
    final items = await dao.getPending(collection: collection.id);
    return items;
  }

  Stream<RetryProgressEvent?> retryLocal({
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    int? batch,
  }) async* {
    var pending = await dao.getPending();
    if (batch != null) {
      pending = pending.take(batch).toList();
    }
    yield RetryProgressEvent(
      message: 'Found ${pending.length} pending records',
      total: pending.length,
      current: 0,
    );
    final futures = <Future>[];
    for (final item in pending) {
      futures.add(Future(() async {
        try {
          if (item.metadata['deleted'] == true) {
            await delete(
              item.id,
              query: query,
              headers: headers,
              body: item.data,
            );
          } else if (item.metadata['deleted'] == false) {
            if (item.metadata['new'] == true) {
              await create(
                query: query,
                headers: headers,
                body: {
                  ...item.data,
                  'id': item.id,
                },
              );
            } else {
              await update(
                item.id,
                query: query,
                headers: headers,
                body: item.data,
              );
            }
          }
        } catch (e) {
          if (client.logging) debugPrint('retryLocal: ${item.id} $e');
        }
      }));
    }
    for (final item in futures) {
      yield RetryProgressEvent(
        message: 'Retry record',
        total: pending.length,
        current: futures.indexOf(item) + 1,
      );
      await item;
    }
    await dao.removeSyncedDeletedRecords();
    yield null;
  }

  Future<List<RecordModel>> search(String query) {
    return client.db.search(query, collectionId: collection.id);
  }

  Future<void> onEvent(RecordSubscriptionEvent e) async {
    if (e.record != null) {
      if (e.action == 'create') {
        await dao.createItem(
          e.record!.toModel(
            deleted: false,
            synced: true,
          ),
        );
      } else if (e.action == 'update') {
        await dao.updateItem(
          e.record!.toModel(
            deleted: false,
            synced: true,
          ),
        );
      } else if (e.action == 'delete') {
        await dao.deleteItem(
          e.record!.id,
          collection: collection.id,
        );
      }
    }
  }

  Future<(Stream<RecordModel?>, UnsubscribeFunc)> watchRecord(
    String id, {
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
    bool? deleted = false,
    bool? synced,
    String? fields,
    String? expand,
  }) async {
    var stream = client //
        .db
        .recordsDao
        .watch(
      id,
      collection: collection.id,
      fields: fields,
      expand: expand,
    )
        .map((e) {
      if (deleted != null) {
        if (e?.data['deleted'] != deleted) return null;
      }
      if (synced != null) {
        if (e?.data['synced'] != synced) return null;
      }
      return e?.toModel();
    });
    final cancel = await subscribe(id, onEvent);
    await getOneOrNull(id, fetchPolicy: fetchPolicy);
    return (stream, cancel);
  }

  Future<(Stream<List<RecordModel>>, UnsubscribeFunc)> watchRecords({
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
    bool? deleted = false,
    bool? synced,
    String? fields,
    String? expand,
    String? sort,
    String? filter,
  }) async {
    final stream = dao
        .watchAll(
      collection: collection.id,
      fields: fields,
      expand: expand,
      sort: sort,
      filter: filter,
    )
        .map((e) {
      var items = e.toList();
      if (deleted != null) {
        items = items.where((e) => e.metadata['deleted'] == deleted).toList();
      }
      if (synced != null) {
        items = items.where((e) => e.metadata['synced'] == synced).toList();
      }
      return items.map((e) => e.toModel()).toList();
    });
    final cancel = await subscribe('*', onEvent);
    await getFullList(fetchPolicy: fetchPolicy);
    return (stream, cancel);
  }

  @override
  Future<List<RecordModel>> getFullList({
    int batch = 200,
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) async {
    return fetchPolicy.fetch<List<RecordModel>>(
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
  Future<ResultList<RecordModel>> getList({
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
    return fetchPolicy.fetch<ResultList<RecordModel>>(
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
  Future<RecordModel> getOne(
    String id, {
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    RecordModel? record;
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
            'Failed to get record $id in collection $collection.name $e',
          );
        }
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.cacheOnly) {
      final model = await dao.get(
        id,
        collection: collection.id,
        fields: fields,
        expand: expand,
      );
      if (model != null) {
        record = model.toModel();
        await dao.updateItem(record.toModel(
          deleted: false,
          synced: true,
        ));
      }
    }

    if (record == null) {
      throw Exception(
        'Record $id does not exist in collection $collection.name',
      );
    }

    return record;
  }

  @override
  Future<void> delete(
    String id, {
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    Record? record = await dao.get(
      id,
      collection: collection.id,
      fields: null,
      expand: null,
    );
    if (fetchPolicy == FetchPolicy.cacheOnly && record != null) {
      record.metadata['deleted'] = true;
      record.metadata['synced'] = false;
      await dao.updateItem(record);
    }
    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.networkOnly) {
      try {
        await _base.delete(
          id,
          body: body,
          query: query,
          headers: headers,
        );
        if (fetchPolicy == FetchPolicy.cacheAndNetwork) {
          await dao.deleteItem(
            id,
            collection: collection.id,
          );
        }
      } catch (e) {
        if (fetchPolicy == FetchPolicy.networkOnly) {
          throw Exception(
            'Failed to delete record $id in collection $collection.name $e',
          );
        } else if (record != null) {
          record.metadata['deleted'] = true;
          record.metadata['synced'] = false;
          await dao.updateItem(record);
        }
      }
    }
  }

  @override
  Future<RecordModel> update(
    String id, {
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    RecordModel? record;
    bool saved = false;
    // final local = await dao.get(
    //   id,
    //   collection: collection.id,
    // );

    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.networkOnly) {
      try {
        record = await _base.update(
          id,
          body: body,
          query: query,
          headers: headers,
          expand: expand,
          files: files,
          fields: fields,
        );
        saved = true;
      } catch (e) {
        if (fetchPolicy == FetchPolicy.networkOnly) {
          throw Exception(
            'Failed to update record $id in collection $collection.name $e',
          );
        }
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.cacheOnly) {
      if (record == null) {
        throw Exception(
          'Record $id does not exist in collection $collection.name',
        );
      }
      record.data.addAll(body);
      await dao.updateItem(record.toModel(
        deleted: false,
        synced: saved,
      ));
    }

    return record!;
  }

  @override
  Future<RecordModel> create({
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    RecordModel? record;
    bool saved = false;

    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.networkOnly) {
      try {
        record = await _base.create(
          body: body,
          query: query,
          headers: headers,
          expand: expand,
          files: files,
          fields: fields,
        );
        saved = true;
      } catch (e) {
        if (fetchPolicy == FetchPolicy.networkOnly) {
          throw Exception(
            'Failed to create record ${record?.id} in collection $collection.name $e',
          );
        }
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.cacheOnly) {
      if (record == null) {
        final id = body['id'] ?? '';
        final recordModel = Record(
          id: id,
          data: body,
          created: DateTime.now(),
          updated: DateTime.now(),
          collectionId: collection.id,
          collectionName: collection.name,
          metadata: {
            'deleted': false,
            'synced': saved,
            if (!saved) 'new': true,
          },
        );
        final result = await dao.createItem(
          recordModel,
        );
        final item = await dao.get(
          result,
          collection: collection.id,
          fields: fields,
          expand: expand,
        );
        record = item?.toModel();
      } else {
        await dao.updateItem(record.toModel(
          deleted: false,
          synced: saved,
          isNew: !saved ? true : null,
        ));
      }
    }

    return record!;
  }

  @override
  Future<RecordAuth> authRefresh({
    String? expand,
    String? fields,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.authRefresh(
      expand: expand,
      fields: fields,
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  Future<RecordAuth> authWithOAuth2(
    String providerName,
    OAuth2UrlCallbackFunc urlCallback, {
    List<String> scopes = const [],
    Map<String, dynamic> createData = const {},
    String? expand,
    String? fields,
  }) {
    return _base.authWithOAuth2(
      providerName,
      urlCallback,
      scopes: scopes,
      createData: createData,
      expand: expand,
      fields: fields,
    );
  }

  @override
  Future<RecordAuth> authWithOAuth2Code(
    String provider,
    String code,
    String codeVerifier,
    String redirectUrl, {
    Map<String, dynamic> createData = const {},
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) {
    return _base.authWithOAuth2Code(
      provider,
      code,
      codeVerifier,
      redirectUrl,
      createData: createData,
      body: body,
      query: query,
      headers: headers,
      expand: expand,
      fields: fields,
    );
  }

  @override
  Future<RecordAuth> authWithPassword(
    String usernameOrEmail,
    String password, {
    String? expand,
    String? fields,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.authWithPassword(
      usernameOrEmail,
      password,
      expand: expand,
      fields: fields,
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  String get baseCollectionPath => _base.baseCollectionPath;

  @override
  Future<void> confirmEmailChange(
    String emailChangeToken,
    String userPassword, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.confirmEmailChange(
      emailChangeToken,
      userPassword,
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
  Future<void> confirmVerification(
    String verificationToken, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.confirmVerification(
      verificationToken,
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  Future<AuthMethodsList> listAuthMethods({
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.listAuthMethods(
      query: query,
      headers: headers,
    );
  }

  @override
  Future<List<ExternalAuthModel>> listExternalAuths(
    String recordId, {
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.listExternalAuths(
      recordId,
      query: query,
      headers: headers,
    );
  }

  @override
  Future<void> requestEmailChange(
    String newEmail, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.requestEmailChange(
      newEmail,
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

  @override
  Future<void> requestVerification(
    String email, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.requestVerification(
      email,
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  Future<UnsubscribeFunc> subscribe(
    String topic,
    RecordSubscriptionFunc callback,
  ) {
    return _base.subscribe(topic, callback);
  }

  @override
  Future<void> unlinkExternalAuth(
    String recordId,
    String provider, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return _base.unlinkExternalAuth(
      recordId,
      provider,
      body: body,
      query: query,
      headers: headers,
    );
  }

  @override
  Future<void> unsubscribe([String topic = ""]) {
    return _base.unsubscribe(topic);
  }
}

extension RecordServiceUtils on $RecordService {
  Future<RecordModel?> getOneOrNull(
    String id, {
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
    String? expand,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    try {
      final result = await getOne(
        id,
        fetchPolicy: fetchPolicy,
        expand: expand,
        query: query,
        headers: headers,
      );
      return result;
    } catch (e) {
      if (client.logging) {
        debugPrint('cannot find $id in $collection.name $e');
      }
    }
    return null;
  }
}

class RetryProgressEvent {
  final int total;
  final int current;
  final String message;

  const RetryProgressEvent({
    required this.total,
    required this.current,
    required this.message,
  });

  double get progress => current / total;
}
