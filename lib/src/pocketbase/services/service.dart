// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/foundation.dart';
import "package:http/http.dart" as http;

import '../../../pocketbase_drift.dart';

mixin ServiceMixin<M extends Jsonable> on BaseCrudService<M> {
  String get service;

  @override
  $PocketBase get client;

  @override
  Future<M> getOne(
    String id, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    DataPolicy dataPolicy = DataPolicy.cacheAndNetwork,
  }) async {
    return dataPolicy.fetch<M>(
      label: service,
      remote: () => super.getOne(
        id,
        fields: fields,
        query: query,
        expand: expand,
        headers: headers,
      ),
      getLocal: () async {
        final result = await client.db
            .$query(
              service,
              expand: expand,
              fields: fields,
              filter: "id = '$id'",
            )
            .getSingleOrNull();
        if (result == null) {
          throw Exception(
            'Record ($id) not found in collection $service [cache]',
          );
        }
        return itemFactoryFunc(result);
      },
      setLocal: (value) async {
        await client.db.$create(service, value.toJson());
      },
    );
  }

  @override
  Future<List<M>> getFullList({
    int batch = 200,
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    DataPolicy dataPolicy = DataPolicy.cacheAndNetwork,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final result = <M>[];

    Future<List<M>> request(int page) async {
      return getList(
        page: page,
        perPage: batch,
        filter: filter,
        sort: sort,
        fields: fields,
        expand: expand,
        query: query,
        headers: headers,
        dataPolicy: dataPolicy,
        timeout: timeout,
      ).then((list) {
        result.addAll(list.items);
        debugPrint(
            '$service page result: ${list.page}/${list.totalPages}=>${list.items.length}$batch');
        if (list.items.length < batch ||
            list.items.isEmpty ||
            list.page == list.totalPages) {
          return result;
        }
        return request(page + 1);
      });
    }

    return request(1);
  }

  @override
  Future<M> getFirstListItem(
    String filter, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    DataPolicy dataPolicy = DataPolicy.cacheAndNetwork,
  }) {
    return dataPolicy.fetch<M>(
      label: service,
      remote: () {
        return getList(
          perPage: 1,
          filter: filter,
          expand: expand,
          fields: fields,
          query: query,
          headers: headers,
          dataPolicy: dataPolicy,
        ).then((result) {
          if (result.items.isEmpty) {
            throw ClientException(
              statusCode: 404,
              response: <String, dynamic>{
                "code": 404,
                "message": "The requested resource wasn't found.",
                "data": <String, dynamic>{},
              },
            );
          }
          return result.items.first;
        });
      },
      getLocal: () async {
        final item = await client.db
            .$query(
              service,
              expand: expand,
              fields: fields,
              filter: filter,
            )
            .getSingleOrNull();
        return itemFactoryFunc(item!);
      },
      setLocal: (value) async {
        await client.db.$create(
          service,
          value.toJson(),
        );
      },
    );
  }

  Future<M?> getFirstListItemOrNull(
    String filter, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    DataPolicy dataPolicy = DataPolicy.cacheAndNetwork,
  }) async {
    try {
      return getFirstListItem(
        filter,
        expand: expand,
        fields: fields,
        query: query,
        headers: headers,
        dataPolicy: dataPolicy,
      );
    } catch (e) {
      debugPrint('error get $filter: $e');
      return null;
    }
  }

  @override
  Future<ResultList<M>> getList({
    int page = 1,
    int perPage = 30,
    bool skipTotal = false,
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    DataPolicy dataPolicy = DataPolicy.cacheAndNetwork,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return dataPolicy.fetch<ResultList<M>>(
      label: service,
      remote: () => super
          .getList(
            page: page,
            perPage: perPage,
            skipTotal: skipTotal,
            expand: expand,
            filter: filter,
            fields: fields,
            sort: sort,
            query: query,
            headers: headers,
          )
          .timeout(timeout),
      getLocal: () async {
        final limit = perPage;
        final offset = (page - 1) * perPage;
        final items = await client.db
            .$query(
              service,
              limit: limit,
              offset: offset,
              expand: expand,
              fields: fields,
              filter: filter,
              sort: sort,
            )
            .get();
        final results = items.map((e) => itemFactoryFunc(e)).toList();
        final count = await client.db.$count(service);
        final totalPages = (count / perPage).ceil();
        return ResultList(
          page: page,
          perPage: perPage,
          items: results,
          totalItems: count,
          totalPages: totalPages,
        );
      },
      setLocal: (value) async {
        // TODO: (filter == null || filter.isEmpty) && (fields == null || fields.isEmpty) ? merge
        await client.db.setLocal(
          service,
          value.items.map((e) => e.toJson()).toList(),
          removeAll: false,
        );
      },
    );
  }

  Future<M?> getOneOrNull(
    String id, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    DataPolicy dataPolicy = DataPolicy.cacheAndNetwork,
  }) async {
    try {
      final result = await getOne(
        id,
        dataPolicy: dataPolicy,
        expand: expand,
        fields: fields,
        query: query,
        headers: headers,
      );
      return result;
    } catch (e) {
      if (client.logging) {
        debugPrint('cannot find $id in $service $e');
      }
    }
    return null;
  }

  Future<void> setLocal(
    List<M> items, {
    bool removeAll = true,
  }) async {
    await client.db.setLocal(
      service,
      items.map((e) => e.toJson()).toList(),
      removeAll: removeAll,
    );
  }

  /// Set filenames of files to field+index
  @override
  Future<M> create({
    DataPolicy dataPolicy = DataPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    if (dataPolicy != DataPolicy.networkOnly && files.isNotEmpty) {
      throw Exception('Cannot upload files in offline mode');
    }

    M? result;
    bool saved = false;

    if (dataPolicy.isNetwork) {
      try {
        try {
          result = await super.create(
            body: body,
            query: query,
            headers: headers,
            expand: expand,
            files: files,
            fields: fields,
          );
        } on ClientException catch (e) {
          if (e.statusCode == 400 && body['id'] != null) {
            final id = body.remove('id');
            result = await super.update(
              id,
              body: body,
              query: query,
              files: files,
              headers: headers,
              expand: expand,
              fields: fields,
            );
          } else {
            rethrow;
          }
        }
        saved = true;
      } catch (e) {
        final msg = 'Failed to create record $body in $service: $e';
        if (dataPolicy == DataPolicy.networkOnly) {
          throw Exception(msg);
        } else {
          debugPrint(msg);
        }
      }
    }

    if (dataPolicy.isCache) {
      final data = await client.db.$create(
        service,
        {
          ...result?.toJson() ?? body,
          'deleted': false,
          'synced': saved,
          'isNew': !saved ? true : null,
        },
      );
      // TODO: Save files for offline
      // for (var i = 0; i < files.length; i++) {
      //   final item = await files[i].finalize().toBytes();
      //   await client.db.setFile(data['id'], '${files[i].filename}', item);
      // }

      result = itemFactoryFunc(data);
    }

    return result!;
  }

  @override
  Future<M> update(
    String id, {
    DataPolicy dataPolicy = DataPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    if (dataPolicy != DataPolicy.networkOnly && files.isNotEmpty) {
      throw Exception('Cannot upload files in offline mode');
    }
    // return create(
    //   body: {...body, 'id': id},
    //   dataPolicy: dataPolicy,
    //   query: query,
    //   files: files,
    //   headers: headers,
    //   expand: expand,
    //   fields: fields,
    // );
    M? result;
    bool saved = false;

    if (dataPolicy.isNetwork) {
      try {
        try {
          result = await super.update(
            id,
            body: body,
            query: query,
            headers: headers,
            expand: expand,
            files: files,
            fields: fields,
          );
        } on ClientException catch (e) {
          if (e.statusCode == 404 || e.statusCode == 400) {
            result = await super.create(
              body: {...body, 'id': id},
              query: query,
              files: files,
              headers: headers,
              expand: expand,
              fields: fields,
            );
          } else {
            rethrow;
          }
        }
        saved = true;
      } catch (e) {
        final msg = 'Failed to update record $body in $service: $e';
        if (dataPolicy == DataPolicy.networkOnly) {
          throw Exception(msg);
        } else {
          debugPrint(msg);
        }
      }
    }

    if (dataPolicy.isCache) {
      final data = await client.db.$update(
        service,
        id,
        {
          ...result?.toJson() ?? body,
          'deleted': false,
          'synced': saved,
          'isNew': false,
        },
      );
      // TODO: Save files for offline
      // ?
      result = itemFactoryFunc(data);
    }

    return result!;
  }

  @override
  Future<void> delete(
    String id, {
    DataPolicy dataPolicy = DataPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    bool saved = false;

    if (dataPolicy.isNetwork) {
      try {
        await super.delete(
          id,
          body: body,
          query: query,
          headers: headers,
        );
        saved = true;
      } catch (e) {
        final msg = 'Failed to delete record $id in $service: $e';
        if (dataPolicy == DataPolicy.networkOnly) {
          throw Exception(msg);
        } else {
          debugPrint(msg);
        }
      }
    }

    if (dataPolicy.isCache) {
      if (saved) {
        await client.db.$delete(service, id);
      } else {
        await update(
          id,
          body: {
            ...body,
            'deleted': true,
            'synced': false,
          },
          query: query,
          headers: headers,
        );
      }
    }
  }
}

class RetryProgressEvent {
  final int total;
  final int current;

  const RetryProgressEvent({
    required this.total,
    required this.current,
  });

  double get progress => current / total;
}

enum DataPolicy {
  cacheOnly,
  networkOnly,
  cacheAndNetwork,
}

extension DataPolicyUtils on DataPolicy {
  bool get isNetwork =>
      this == DataPolicy.networkOnly || this == DataPolicy.cacheAndNetwork;
  bool get isCache =>
      this == DataPolicy.cacheOnly || this == DataPolicy.cacheAndNetwork;

  Future<T> fetch<T>({
    required String label,
    required Future<T> Function() remote,
    required Future<T> Function() getLocal,
    required Future<void> Function(T) setLocal,
    // Duration timeout = const Duration(seconds: 3),
  }) async {
    debugPrint('data policy: $label, $name');
    T? result;

    if (isNetwork) {
      try {
        debugPrint('fetching remote...');
        result = await remote();
      } catch (e) {
        debugPrint('error remote... $e');
        if (this == DataPolicy.networkOnly) {
          throw Exception('Failed to get $e');
        }
      }
    }

    if (isCache) {
      if (result != null) {
        debugPrint('setting cache...');
        await setLocal(result);
      } else {
        debugPrint('fetching cache...');
        result = await getLocal();
      }
    }

    if (result == null) {
      throw Exception('Failed to get');
    }

    return result;
  }

  Stream<T> stream<T>({
    required String label,
    required Future<T> Function() remote,
    required Future<T> Function() getLocal,
    required Future<void> Function(T) setLocal,
    // Duration timeout = const Duration(seconds: 3),
  }) async* {
    debugPrint('data policy: $label, $name');
    T? result;

    if (isCache) result = await getLocal();

    if (isNetwork) {
      try {
        debugPrint('fetching remote...');
        result = await remote();
        if (isCache && result != null) {
          debugPrint('setting cache...');
          await setLocal(result);
        }
      } catch (e) {
        debugPrint('error remote... $e');
        if (this == DataPolicy.networkOnly) {
          throw Exception('Failed to get $e');
        }
      }
    }

    if (result == null) throw Exception('Failed to get');
    yield result;
  }
}
