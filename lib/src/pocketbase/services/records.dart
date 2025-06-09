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
    // This query now correctly fetches only records that are unsynced
    // AND are NOT marked as local-only.
    return client.db
        .$query(service,
            filter: "synced = false AND (noSync IS NULL OR noSync = false)")
        .map(itemFactoryFunc);
  }

  Stream<RetryProgressEvent?> retryLocal({
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    int? batch,
  }) async* {
    final items = await pending().get();
    final total = items.length;

    client.logger
        .info('Starting retry for $total pending items in service: $service');
    yield RetryProgressEvent(current: 0, total: total);

    if (total == 0) {
      return;
    }

    for (var i = 0; i < total; i++) {
      final item = items[i];
      try {
        final tempId = item.id;
        client.logger.fine('Retrying item $tempId (${i + 1}/$total)');

        // The record was marked for deletion while offline.
        if (item.data['deleted'] == true) {
          await delete(
            tempId,
            requestPolicy: RequestPolicy.cacheAndNetwork,
            query: query,
            headers: headers,
          );
          client.logger.fine('Successfully synced deletion for item $tempId');

          // The record was newly created offline.
        } else if (item.data['isNew'] == true) {
          // Prepare body for creation by removing server-generated and local-only fields.
          final createBody = Map<String, dynamic>.from(item.toJson());
          createBody.remove('id');
          createBody.remove('created');
          createBody.remove('updated');
          createBody.remove('collectionId');
          createBody.remove('collectionName');
          createBody.remove('expand');
          createBody.remove('synced');
          createBody.remove('isNew');
          createBody.remove('deleted');

          // Create the record on the server. RequestPolicy.cacheAndNetwork will
          // automatically save the new server-authoritative record to the local DB.
          final newRecord = await create(
            body: createBody,
            requestPolicy: RequestPolicy.cacheAndNetwork,
            query: query,
            headers: headers,
          );

          // Clean up the old record that had the temporary ID.
          await client.db.$delete(service, tempId);
          client.logger.fine(
              'Successfully synced new item. Replaced temp ID $tempId with server ID ${newRecord.id}');

          // The record was an existing one that was updated offline.
        } else {
          await update(
            tempId,
            body: item.toJson(),
            requestPolicy: RequestPolicy.cacheAndNetwork,
            query: query,
            headers: headers,
          );
          client.logger.fine('Successfully synced update for item $tempId');
        }
      } catch (e) {
        client.logger
            .warning('Error retrying local change for item ${item.id}', e);
        // Continue with other items even if one fails
      }
      yield RetryProgressEvent(current: i + 1, total: total);
    }

    client.logger.info('Completed retry for service: $service');
  }

  @override
  Future<UnsubscribeFunc> subscribe(
    String topic,
    RecordSubscriptionFunc callback, {
    String? expand,
    String? filter,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return super.subscribe(
      topic,
      (e) {
        onEvent(e);
        callback(e);
      },
      expand: expand,
      filter: filter,
      fields: fields,
      query: query,
      headers: headers,
    );
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
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) {
    final controller = StreamController<RecordModel?>(
      onListen: () async {
        if (requestPolicy.isNetwork) {
          try {
            await subscribe(id, (e) {});
          } catch (e) {
            client.logger
                .warning('Error subscribing to record $service/$id', e);
          }
        }
        await getOneOrNull(id, requestPolicy: requestPolicy);
      },
      onCancel: () async {
        if (requestPolicy.isNetwork) {
          try {
            await unsubscribe(id);
          } catch (e) {
            client.logger.fine(
                'Error unsubscribing from record $service/$id (may be intentional)',
                e);
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
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) {
    final controller = StreamController<List<RecordModel>>(
      onListen: () async {
        if (requestPolicy.isNetwork) {
          try {
            await subscribe('*', (e) {});
          } catch (e) {
            client.logger
                .warning('Error subscribing to collection $service', e);
          }
        }
        final items = await getFullList(
          requestPolicy: requestPolicy,
          filter: filter,
          expand: expand,
          sort: sort,
          fields: fields,
        );
        client.logger.fine(
            'Realtime initial full list for "$service" [${requestPolicy.name}]: ${items.length} items');
      },
      onCancel: () async {
        if (requestPolicy.isNetwork) {
          try {
            await unsubscribe('*');
          } catch (e) {
            client.logger.fine(
                'Error unsubscribing from collection $service (may be intentional)',
                e);
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
