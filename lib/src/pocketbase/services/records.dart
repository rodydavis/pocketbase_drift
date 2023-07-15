import 'dart:async';

import 'package:drift/drift.dart';

import '../../../pocketbase_drift.dart';

class $RecordService extends RecordService with ServiceMixin<RecordModel> {
  $RecordService(this.client, this.service) : super(client, service);

  @override
  final $PocketBase client;

  @override
  final String service;

  Selectable<RecordModel> search(String query) {
    return client.db.search(query, service: service).map(
          (p0) => itemFactoryFunc({
            ...p0.data,
            'created': p0.created,
            'updated': p0.updated,
            'id': p0.id,
          }),
        );
  }

  Selectable<RecordModel> pending() {
    return client.db.$query(service, filter: 'synced = false').map(itemFactoryFunc);
  }

  Stream<RetryProgressEvent?> retryLocal({
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    int? batch,
  }) async* {
    final items = await pending().get();
    final total = items.length;
    yield RetryProgressEvent(current: 0, total: total);
    for (var i = 0; i < total; i++) {
      final item = items[i];
      try {
        final id = item.id;
        if (item.data['deleted'] == true) {
          await delete(
            id,
            body: item.toJson(),
            query: query,
            headers: headers,
          );
        } else if (item.data['new'] == true) {
          await create(
            body: item.toJson(),
            query: query,
            headers: headers,
          );
        } else {
          await update(
            id,
            body: item.toJson(),
            query: query,
            headers: headers,
          );
        }
      } catch (e) {
        print('error retry $item: $e');
      }
      yield RetryProgressEvent(current: i + 1, total: total);
    }
    yield RetryProgressEvent(current: total, total: total);
  }

  @override
  Future<UnsubscribeFunc> subscribe(
    String topic,
    RecordSubscriptionFunc callback,
  ) {
    return super.subscribe(topic, (e) {
      onEvent(e);
      callback(e);
    });
  }

  Future<void> onEvent(RecordSubscriptionEvent e) async {
    if (e.record != null) {
      if (e.action == 'create') {
        await client.db.$create(
          service,
          {
            ...e.record!.toJson(),
            'deleted': false,
            'synced': true,
          },
        );
      } else if (e.action == 'update') {
        await client.db.$update(
          service,
          e.record!.id,
          {
            ...e.record!.toJson(),
            'deleted': false,
            'synced': true,
          },
        );
      } else if (e.action == 'delete') {
        await client.db.$delete(
          service,
          e.record!.id,
        );
      }
    }
  }

  Stream<RecordModel?> watchRecord(
    String id, {
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) {
    final controller = StreamController<RecordModel?>(
      onListen: () async {
        if (fetchPolicy.isNetwork) {
          try {
            await subscribe(id, (e) {});
          } catch (e) {
            print('error subscribe $service $id: $e');
          }
        }
        await getOneOrNull(id, fetchPolicy: fetchPolicy);
      },
      onCancel: () async {
        if (fetchPolicy.isNetwork) {
          try {
            await unsubscribe(id);
          } catch (e) {
            print('error unsubscribe $service $id: $e');
          }
        }
      },
    );
    final stream = client.db
        .$query(
          service,
          filter: "id = '$id'",
        )
        .map(itemFactoryFunc)
        .watchSingleOrNull();
    controller.addStream(stream);
    return controller.stream;
  }

  Stream<List<RecordModel>> watchRecords({
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) {
    final controller = StreamController<List<RecordModel>>(
      onListen: () async {
        if (fetchPolicy.isNetwork) {
          try {
            await subscribe('*', (e) {});
          } catch (e) {
            print('error subscribe $service: $e');
          }
        }
        final items = await getFullList(
          fetchPolicy: fetchPolicy,
          filter: filter,
          expand: expand,
          sort: sort,
          fields: fields,
        );
        print('$service realtime full list ${items.length}');
      },
      onCancel: () async {
        if (fetchPolicy.isNetwork) {
          try {
            await unsubscribe('*');
          } catch (e) {
            print('error unsubscribe $service: $e');
          }
        }
      },
    );
    final stream = client.db
        .$query(
          service,
          filter: filter,
          expand: expand,
          sort: sort,
          fields: fields,
        )
        .map(itemFactoryFunc)
        .watch();
    controller.addStream(stream);
    return controller.stream;
  }
}
