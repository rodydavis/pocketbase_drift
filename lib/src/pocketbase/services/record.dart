import 'dart:async';

import 'package:flutter/foundation.dart';
import "package:http/http.dart" as http;
import 'package:pocketbase/pocketbase.dart';

import '../../database/database.dart';
import '../pocketbase.dart';

typedef IdGenerator = String Function();

// TODO: Files to path provider, web?
class $RecordService extends RecordService {
  $RecordService(
    this.client, {
    required this.collectionName,
    required this.collectionId,
    required this.idGenerator,
  }) : super(client, collectionId);

  @override
  final $PocketBase client;

  final String collectionName;

  final String collectionId;

  final IdGenerator idGenerator;

  Future<void> retryLocal({
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    final deleted = await client.db.getRecords(
      collectionName,
      deleted: true,
    );
    final pending = await client.db.getRecords(
      collectionName,
      synced: false,
    );

    final futures = <Future>[];
    for (final item in pending) {
      futures.add(Future(() async {
        final isDeleted = deleted.indexWhere((e) => e.id == item.id) != -1;
        if (isDeleted) {
          await delete(
            item.id,
            query: query,
            headers: headers,
            body: item.data,
          );
        } else {
          await update(
            item.id,
            query: query,
            headers: headers,
            body: item.data,
          );
        }
      }));
    }
    for (final item in futures) {
      await item;
    }
    final stale = await client.db.getRecords(
      collectionName,
      deleted: true,
      synced: true,
    );
    futures.clear();
    for (final item in stale) {
      futures.add(Future(() async {
        await client.db.deleteRecord(collectionName, item.id);
      }));
    }
    for (final item in futures) {
      await item;
    }
  }

  Future<void> setLocal(List<Map<String, dynamic>> list) async {
    final items = list.map((e) {
      return RecordModel(
        id: e['id'],
        data: e,
        collectionId: collectionId,
        collectionName: collectionName,
        created: e['created'] ?? DateTime.now().toIso8601String(),
        updated: e['updated'] ?? DateTime.now().toIso8601String(),
      );
    }).toList();
    await client.db.setRecords(items);
  }

  StreamController<RecordModel?> watchRecord(
    String id, {
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
    bool deleted = false,
    bool? synced,
  }) {
    UnsubscribeFunc? cancel;
    final controller = StreamController<RecordModel?>.broadcast(
      onListen: () async {
        if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
            fetchPolicy == FetchPolicy.networkOnly) {
          try {
            cancel = await subscribe(id, (e) async {
              // create, update, delete
              if (e.record != null) {
                if (e.action == 'create' || e.action == 'update') {
                  await client.db.setRecord(
                    e.record!,
                    deleted: false,
                    synced: true,
                  );
                } else if (e.action == 'delete') {
                  await client.db.setRecord(
                    e.record!,
                    deleted: true,
                    synced: true,
                  );
                }
              }
            });
          } catch (e) {
            debugPrint('watchRecord: $e');
          }
        }
      },
      onCancel: () async {
        await cancel?.call();
      },
    );
    controller.addStream(client.db.watchRecord(
      collectionName,
      id,
      deleted: deleted,
      synced: synced,
    ));
    return controller;
  }

  StreamController<List<RecordModel>> watchRecords({
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
    bool deleted = false,
    bool? synced,
  }) {
    UnsubscribeFunc? cancel;
    final controller = StreamController<List<RecordModel>>.broadcast(
      onListen: () async {
        if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
            fetchPolicy == FetchPolicy.networkOnly) {
          try {
            cancel = await subscribe('*', (e) async {
              // create, update, delete
              if (e.record != null) {
                if (e.action == 'create' || e.action == 'update') {
                  await client.db.setRecord(
                    e.record!,
                    deleted: false,
                    synced: true,
                  );
                } else if (e.action == 'delete') {
                  await client.db.setRecord(
                    e.record!,
                    deleted: true,
                    synced: true,
                  );
                }
              }
            });
          } catch (e) {
            debugPrint('watchRecord: $e');
          }
        }
      },
      onCancel: () async {
        await cancel?.call();
      },
    );
    controller.addStream(client.db.watchRecords(
      collectionName,
      deleted: deleted,
      synced: synced,
    ));
    return controller;
  }

  @override
  Future<List<RecordModel>> getFullList({
    int batch = 200,
    String? expand,
    String? filter,
    String? sort,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
    bool deleted = false,
    bool? synced,
  }) async {
    List<RecordModel> result = [];

    if (fetchPolicy == FetchPolicy.networkOnly) {
      try {
        result = await super.getFullList(
          batch: batch,
          expand: expand,
          filter: filter,
          sort: sort,
          query: query,
          headers: headers,
        );
      } catch (e) {
        if (fetchPolicy == FetchPolicy.networkOnly) {
          throw Exception(
            'Failed to get records in collection $collectionName $e',
          );
        }
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork) {
      if (result.isNotEmpty) {
        await client.db.setRecords(result);
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.cacheOnly) {
      result = await client.db.getRecords(
        collectionName,
        deleted: deleted,
        synced: synced,
      );
    }

    return result;
  }

  @override
  Future<ResultList<RecordModel>> getList({
    int page = 1,
    int perPage = 30,
    String? expand,
    String? filter,
    String? sort,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
    bool deleted = false,
    bool? synced,
  }) async {
    ResultList<RecordModel> result = ResultList(items: []);
    if (fetchPolicy == FetchPolicy.networkOnly ||
        fetchPolicy == FetchPolicy.cacheAndNetwork) {
      try {
        result = await super.getList(
          page: page,
          perPage: perPage,
          expand: expand,
          filter: filter,
          sort: sort,
          query: query,
          headers: headers,
        );
      } catch (e) {
        if (fetchPolicy == FetchPolicy.networkOnly) {
          throw Exception(
            'Failed to get records in collection $collectionName $e',
          );
        }
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork) {
      if (result.items.isNotEmpty) {
        await client.db.setRecords(result.items);
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.cacheOnly) {
      if (result.items.isEmpty) {
        final items = await client.db.getRecords(
          collectionName,
          deleted: deleted,
          synced: synced,
          page: page,
          perPage: perPage,
        );
        final count = await client.db.getRecordCount(
          collectionName,
          deleted: deleted,
          synced: synced,
        );
        result = ResultList(
          page: page,
          perPage: perPage,
          items: items,
          totalItems: count,
          totalPages: (count / perPage).floor(),
        );
      }
    }

    return result;
  }

  @override
  Future<RecordModel> getOne(
    String id, {
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
    String? expand,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    RecordModel? record;
    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.networkOnly) {
      try {
        record = await super.getOne(
          id,
          expand: expand,
          query: query,
          headers: headers,
        );
      } catch (e) {
        if (fetchPolicy == FetchPolicy.networkOnly) {
          throw Exception(
            'Failed to get record $id in collection $collectionName $e',
          );
        }
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.cacheOnly) {
      final model = await client.db.getRawRecord(collectionName, id);
      if (model?.deleted != true) {
        record = model?.toModel();
      }
    }

    if (record == null) {
      throw Exception(
        'Record $id does not exist in collection $collectionName',
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
    if (fetchPolicy == FetchPolicy.cacheAndNetwork) {
      await client.db.deleteRecord(collectionName, id);
    }
    RecordModel? record = await client.db.getRecord(collectionName, id);
    if (fetchPolicy == FetchPolicy.cacheOnly && record != null) {
      await client.db.setRecord(record, deleted: true, synced: false);
    }
    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.networkOnly) {
      try {
        await super.delete(
          id,
          body: body,
          query: query,
          headers: headers,
        );
      } catch (e) {
        if (fetchPolicy == FetchPolicy.networkOnly) {
          throw Exception(
            'Failed to delete record $id in collection $collectionName $e',
          );
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
  }) async {
    assert(expand == null && fetchPolicy != FetchPolicy.cacheOnly);
    RecordModel? record = await client.db.getRecord(collectionName, id);
    bool saved = false;
    if (record == null && fetchPolicy == FetchPolicy.cacheAndNetwork) {
      record = await super.getOne(
        id,
        expand: expand,
        query: query,
        headers: headers,
      );
    }
    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.networkOnly) {
      try {
        record = await super.update(
          id,
          body: body,
          query: query,
          headers: headers,
          expand: expand,
          files: files,
        );
        saved = true;
      } catch (e) {
        if (fetchPolicy == FetchPolicy.networkOnly) {
          throw Exception(
            'Failed to update record $id in collection $collectionName $e',
          );
        }
      }
    }
    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.cacheOnly) {
      if (record == null) {
        throw Exception(
          'Record $id does not exist in collection $collectionName',
        );
      }
      record.data.addAll(body);
      await client.db.setRecord(
        record,
        synced: saved,
      );
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
  }) async {
    assert(expand == null && fetchPolicy != FetchPolicy.cacheOnly);
    final data = {...body, 'id': idGenerator()};
    final id = data['id'] as String;
    RecordModel? record;
    bool saved = false;

    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.networkOnly) {
      try {
        record = await super.create(
          body: data,
          query: query,
          headers: headers,
          expand: expand,
          files: files,
        );
        saved = true;
      } catch (e) {
        if (fetchPolicy == FetchPolicy.networkOnly) {
          throw Exception(
            'Failed to create record $id in collection $collectionName $e',
          );
        }
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.cacheOnly) {
      record = toRecord(data);
      await client.db.setRecord(
        record,
        synced: saved,
      );
    }

    return record!;
  }

  RecordModel toRecord(Map<String, dynamic> data) {
    final id = data['id'].toString();
    return RecordModel(
      id: id,
      data: data,
      created: DateTime.now().toIso8601String(),
      updated: DateTime.now().toIso8601String(),
      collectionId: collectionId,
      collectionName: collectionName,
    );
  }
}

enum FetchPolicy {
  cacheOnly,
  networkOnly,
  cacheAndNetwork,
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
      return getOne(
        id,
        fetchPolicy: fetchPolicy,
        expand: expand,
        query: query,
        headers: headers,
      );
    } catch (e) {
      debugPrint('cannot find $id in $collectionName');
      return null;
    }
  }
}
