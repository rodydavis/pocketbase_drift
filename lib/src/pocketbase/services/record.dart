// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import "package:http/http.dart" as http;
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../database/database.dart';
import '../pocketbase.dart';
import 'base.dart';

typedef IdGenerator = String Function();

// TODO: Files to path provider, web?
class $RecordService extends RecordService {
  $RecordService(this.client, this.collection) : super(client, collection.id);

  @override
  final $PocketBase client;

  final CollectionModel collection;

  late final dao = client.db.recordsDao;

  Stream<RetryProgressEvent?> retryLocal({
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async* {
    final deleted = await dao.getPendingDeletes();
    final pending = await dao.getPending();
    yield RetryProgressEvent(
      message: 'Found ${pending.length} pending records',
      total: pending.length,
      current: 0,
    );
    final futures = <Future>[];
    for (final item in pending) {
      futures.add(Future(() async {
        try {
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
              merge: (current, remote) {
                final remoteDate = DateTime.parse(remote.updated);
                final currentDate = DateTime.parse(current.updated);
                if (remoteDate.isAfter(currentDate)) {
                  return remote;
                } else {
                  return current;
                }
              },
            );
          }
        } catch (e) {
          if (client.logging) debugPrint('retryLocal: ${item.id} $e');
        }
      }));
    }
    for (final item in futures) {
      yield RetryProgressEvent(
        message: 'Updating record',
        total: pending.length,
        current: futures.indexOf(item) + 1,
      );
      await item;
    }
    await dao.removeSyncedDeletedRecords();
    yield null;
  }

  Future<void> setLocal(List<Map<String, dynamic>> list) async {
    final items = list.map((e) {
      return RecordModel(
        id: e['id'] ?? client.db.generateId(),
        data: e,
        collectionId: collection.id,
        collectionName: collection.name,
        created: e['created'] ?? DateTime.now().toIso8601String(),
        updated: e['updated'] ?? DateTime.now().toIso8601String(),
      );
    }).toList();

    for (final item in items) {
      item.data['deleted'] = false;
      item.data['synced'] = null;
      await dao.updateItem(item.toModel());
    }
  }

  Future<List<RecordModel>> search(String query) {
    return client.db.search(query, collectionId: collection.id);
  }

  Future<void> onEvent(RecordSubscriptionEvent e) async {
    if (e.record != null) {
      if (e.action == 'create') {
        e.record!.data['deleted'] = false;
        e.record!.data['synced'] = true;
        await dao.createItem(
          e.record!.toModel(),
        );
      } else if (e.action == 'update') {
        e.record!.data['deleted'] = false;
        e.record!.data['synced'] = true;
        await dao.updateItem(
          e.record!.toModel(),
        );
      } else if (e.action == 'delete') {
        // e.record!.data['deleted'] = true;
        // e.record!.data['synced'] = true;
        // await dao.updateItem(
        //   e.record!.toModel(),
        // );
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
  }) async {
    var stream = client //
        .db
        .recordsDao
        .watch(id, collection: collection.id)
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
  }) async {
    final stream = dao
        .watchAll(
      collection: collection.id,
    )
        .map((e) {
      final items = e.map((r) => r.toModel()).toList();
      if (deleted != null) {
        return items.where((e) => e.data['deleted'] == deleted).toList();
      }
      if (synced != null) {
        return items.where((e) => e.data['synced'] == synced).toList();
      }
      return items;
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
    List<RecordModel> items = [];

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
        if (fetchPolicy == FetchPolicy.networkOnly) {
          throw Exception(
            'Failed to get records in collection $collection.name $e',
          );
        }
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork) {
      if (items.isNotEmpty) {
        for (final item in items) {
          item.data['deleted'] = false;
          item.data['synced'] = true;
          await dao.updateItem(item.toModel());
        }
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.cacheOnly) {
      if (items.isEmpty) {
        final local = await dao.getAll(
          collection: collection.id,
        );
        items = local.map((e) => e.toModel()).toList();
      }
    }

    return items;
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
    ResultList<RecordModel> result = ResultList(items: []);
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
            'Failed to get records in collection $collection.name $e',
          );
        }
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork) {
      if (result.items.isNotEmpty) {
        for (final item in result.items) {
          item.data['deleted'] = false;
          item.data['synced'] = true;
          await dao.updateItem(item.toModel());
        }
      }
    }

    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.cacheOnly) {
      if (result.items.isEmpty) {
        final items = await dao.getAll(
          collection: collection.id,
          page: page,
          perPage: perPage,
        );
        final count = await dao.getCount(
          collection: collection.id,
        );
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
        record = await super.getOne(
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
      );
      if (model != null) {
        record = model.toModel();
        record.data['deleted'] = false;
        record.data['synced'] = true;
        await dao.updateItem(record.toModel());
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
    );
    if (fetchPolicy == FetchPolicy.cacheAndNetwork) {
      await dao.deleteItem(
        id,
        collection: collection.id,
      );
    }
    if (fetchPolicy == FetchPolicy.cacheOnly && record != null) {
      record.data['deleted'] = true;
      record.data['synced'] = true;
      await dao.updateItem(record);
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
            'Failed to delete record $id in collection $collection.name $e',
          );
        } else if (record != null) {
          record.data['synced'] = false;
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
    RecordModel? Function(RecordModel current, RecordModel remote)? merge,
  }) async {
    RecordModel? record = (await dao.get(
      id,
      collection: collection.id,
    ))
        ?.toModel();
    bool saved = false;
    if (record == null && fetchPolicy == FetchPolicy.cacheAndNetwork) {
      record = await super.getOne(
        id,
        expand: expand,
        query: query,
        headers: headers,
        fields: fields,
      );
    }
    if (fetchPolicy == FetchPolicy.cacheAndNetwork ||
        fetchPolicy == FetchPolicy.networkOnly) {
      try {
        if (merge != null) {
          final remote = await getOneOrNull(
            id,
            expand: expand,
            query: query,
            headers: headers,
            fetchPolicy: FetchPolicy.networkOnly,
          );
          if (record != null) {
            record = merge(record, remote!);
          } else {
            record = remote;
          }
        }
        record = await super.update(
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
      record.data['deleted'] = false;
      record.data['synced'] = saved;
      await dao.updateItem(record.toModel());
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
        record = await super.create(
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
      final data = {...record?.data ?? body};
      data['deleted'] = false;
      data['synced'] = saved;
      final recordModel = RecordModel(
        id: record?.id ?? '',
        data: data,
        created: DateTime.now().toIso8601String(),
        updated: DateTime.now().toIso8601String(),
        collectionId: collection.id,
        collectionName: collection.name,
      ).toModel();
      final result = await dao.createItem(recordModel);
      record = (await dao.get(
        result,
        collection: collection.id,
      ))
          ?.toModel();
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
      collectionId: collection.id,
      collectionName: collection.name,
    );
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
