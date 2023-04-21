part of '../pocketbase_drift.dart';

const int _kDefaultPageSize = 250;

/// [PocketBase] client backed by drift store (sqlite)
class PocketBaseDrift {
  PocketBaseDrift(
    this.url, {
    this.connection,
    this.dbName = 'database.db',
  });

  /// [Url] of [PocketBase] server
  final String url;

  final DatabaseConnection? connection;
  final String dbName;

  /// [PocketBase] internal client
  late final pocketbase = createPocketBaseClient(url);

  /// [PocketBase] internal database
  late final database = PocketBaseDatabase(
    dbName: dbName,
    connection: connection,
  );

  Stream<double> _fetchList(
    String collection, {
    int perPage = _kDefaultPageSize,
    String? filter,
    String? sort,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async* {
    yield 0.0;
    final result = <RecordModel>[];

    Stream<double> request(int page) async* {
      try {
        final list = await pocketbase.collection(collection).getList(
              page: page,
              perPage: perPage,
              filter: filter,
              sort: sort,
              query: query,
              headers: headers,
            );
        debugPrint('fetched ${list.items.length} records for $collection');
        result.addAll(list.items);

        final progress = list.page / list.totalPages;
        if (!progress.isInfinite) {
          yield progress;
        }

        // Add to database
        await database.setRecords(list.items);

        if (list.items.isNotEmpty && list.totalItems > result.length) {
          yield* request(page + 1);
        }
      } catch (e) {
        debugPrint('error fetching records for $collection: $e');
      }
    }

    yield* request(1);

    yield 1.0;
  }

  Future<RecordModel?> getRecord(
    String collection,
    String id, {
    FetchPolicy policy = FetchPolicy.localAndRemote,
  }) async {
    if (policy == FetchPolicy.remoteOnly) {
      return pocketbase.collection(collection).getOne(id);
    } else if (policy == FetchPolicy.localOnly) {
      return database.getRecord(collection, id);
    }
    final local = await database.getRecord(collection, id);
    try {
      final remote = await pocketbase.collection(collection).getOne(id);
      // ignore: unnecessary_null_comparison
      if (remote != null) {
        await database.setRecord(remote);
      }
      return remote;
    } catch (e) {
      debugPrint('error getting remote record $collection/$id --> $e');
    }
    return local;
  }

  Future<List<RecordModel>> getRecords(
    String collection, {
    FetchPolicy policy = FetchPolicy.localAndRemote,
    String? filter,
  }) async {
    if (policy == FetchPolicy.remoteOnly) {
      await _fetchList(collection).last;
    } else if (policy == FetchPolicy.localAndRemote) {
      await updateCollection(collection, filter: filter).last;
    }
    final results = await database.getRecords(collection);
    debugPrint('$policy --> $collection --> ${results.length}');
    return results;
  }

  Future<void> deleteRecord(String collection, String id) async {
    try {
      await pocketbase.collection(collection).delete(id);
    } catch (e) {
      debugPrint('error deleting remote record $collection/$id --> $e');
    }
    await database.deleteRecord(collection, id);
  }

  Future<RecordModel> addRecord(
    String collection,
    Map<String, dynamic> data, {
    bool removeId = false,
  }) async {
    if (removeId) {
      data.remove('id');
    }
    final item = await pocketbase.collection(collection).create(
          body: data,
        );
    await database.setRecord(item);
    return item;
  }

  Future<RecordModel> updateRecord(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    final item = await pocketbase.collection(collection).update(
          id,
          body: data,
        );
    await database.setRecord(item);
    return item;
  }

  Stream<List<RecordModel>> watchRecords(
    String collection, {
    FetchPolicy policy = FetchPolicy.localAndRemote,
    String? filter,
  }) async* {
    yield await getRecords(
      collection,
      policy: FetchPolicy.localOnly,
      filter: filter,
    );
    if (policy == FetchPolicy.localAndRemote) {
      await updateCollection(collection, filter: filter).last;
    }
    // TODO: update local db when remote db change.
    // pocketbase.collection(collection).subscribe('*', (e) {});
    yield* database.watchRecords(collection);
  }

  Stream<RecordModel?> watchRecord(
    String collection,
    String id,
  ) async* {
    yield* database.watchRecord(collection, id);
  }

  /// Update collection from remote server and return progress
  Stream<double> updateCollection(String collection,
      {String? filter, bool forceRefreshAll = false}) async* {
    yield 0.0;
    final local = await database.getRecords(collection);
    final lastRecord = local.newest();

    if (!forceRefreshAll && lastRecord != null) {
      yield* _fetchList(
        collection,
        filter: [
          "updated > '${lastRecord.updated}'",
          if (filter != null) filter,
        ].join(' && '),
      );
    } else {
      // Missing last record, get all
      yield* _fetchList(collection);
    }

    yield 1.0;
  }

  Future<List<RecordModel>> search(
    String query, {
    String? collection,
  }) {
    if (collection != null) {
      return database.searchCollection(query, collection);
    } else {
      return database.searchAll(query);
    }
  }
}

extension on List<RecordModel> {
  RecordModel? newest() {
    if (isEmpty) return null;
    return reduce((value, element) {
      final a = DateTime.parse(element.updated);
      final b = DateTime.parse(value.updated);
      return a.isAfter(b) ? element : value;
    });
  }
}

enum FetchPolicy {
  /// Cache only
  localOnly,

  /// Server only
  remoteOnly,

  /// Cache and server
  localAndRemote,
}
