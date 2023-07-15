// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

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
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) async {
    return fetchPolicy.fetch<M>(
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
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) {
    return fetchPolicy.fetch<List<M>>(
      label: service,
      remote: () {
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
            fetchPolicy: fetchPolicy,
          ).then((list) {
            result.addAll(list.items);
            print('$service page result: ${list.page}/${list.totalPages}=>${list.items.length}');
            if (list.items.isNotEmpty && list.totalItems > result.length) {
              return request(page + 1);
            }

            return result;
          });
        }

        return request(1);
      },
      getLocal: () async {
        final items = await client.db
            .$query(
              service,
              expand: expand,
              fields: fields,
              filter: filter,
              sort: sort,
            )
            .get();
        return items.map((e) => itemFactoryFunc(e)).toList();
      },
      setLocal: (value) async {
        // if ((filter == null || filter.isEmpty) && (fields == null || fields.isEmpty)) {
        //   await client.db.setLocal(
        //     service,
        //     value.map((e) => e.toJson()).toList(),
        //     removeAll: (filter == null || filter.isEmpty) && (fields == null || fields.isEmpty),
        //   );
        // }
      },
    );
  }

  @override
  Future<M> getFirstListItem(
    String filter, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) {
    return fetchPolicy.fetch<M>(
      label: service,
      remote: () {
        return getList(
          perPage: 1,
          filter: filter,
          expand: expand,
          fields: fields,
          query: query,
          headers: headers,
          fetchPolicy: fetchPolicy,
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
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) async {
    try {
      return getFirstListItem(
        filter,
        expand: expand,
        fields: fields,
        query: query,
        headers: headers,
        fetchPolicy: fetchPolicy,
      );
    } catch (e) {
      print('error get $filter: $e');
      return null;
    }
  }

  @override
  Future<ResultList<M>> getList({
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
    return fetchPolicy.fetch<ResultList<M>>(
      label: service,
      remote: () => super.getList(
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
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) async {
    try {
      final result = await getOne(
        id,
        fetchPolicy: fetchPolicy,
        expand: expand,
        fields: fields,
        query: query,
        headers: headers,
      );
      return result;
    } catch (e) {
      if (client.logging) {
        print('cannot find $id in $service $e');
      }
    }
    return null;
  }

  Future<void> setLocal(List<M> items) async {
    await client.db.setLocal(service, items.map((e) => e.toJson()).toList());
  }

  @override
  Future<M> create({
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    if (fetchPolicy != FetchPolicy.networkOnly && files.isNotEmpty) {
      throw Exception('Cannot upload files in offline mode');
    }

    M? result;
    bool saved = false;

    // TODO: Save files for offline

    if (fetchPolicy.isNetwork) {
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
        if (fetchPolicy == FetchPolicy.networkOnly) {
          throw Exception(msg);
        } else {
          print(msg);
        }
      }
    }

    if (fetchPolicy.isCache) {
      final data = await client.db.$create(
        service,
        {
          ...result?.toJson() ?? body,
          'deleted': false,
          'synced': saved,
          'isNew': !saved ? true : null,
        },
      );
      result = itemFactoryFunc(data);
    }

    return result!;
  }

  @override
  Future<M> update(
    String id, {
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    if (fetchPolicy != FetchPolicy.networkOnly && files.isNotEmpty) {
      throw Exception('Cannot upload files in offline mode');
    }
    // return create(
    //   body: {...body, 'id': id},
    //   fetchPolicy: fetchPolicy,
    //   query: query,
    //   files: files,
    //   headers: headers,
    //   expand: expand,
    //   fields: fields,
    // );
    M? result;
    bool saved = false;

    // TODO: Save files for offline

    if (fetchPolicy.isNetwork) {
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
        if (fetchPolicy == FetchPolicy.networkOnly) {
          throw Exception(msg);
        } else {
          print(msg);
        }
      }
    }

    if (fetchPolicy.isCache) {
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
      result = itemFactoryFunc(data);
    }

    return result!;
  }

  @override
  Future<void> delete(
    String id, {
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    bool saved = false;

    if (fetchPolicy.isNetwork) {
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
        if (fetchPolicy == FetchPolicy.networkOnly) {
          throw Exception(msg);
        } else {
          print(msg);
        }
      }
    }

    if (fetchPolicy.isCache) {
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

enum FetchPolicy {
  cacheOnly,
  networkOnly,
  cacheAndNetwork,
}

extension FetchPolicyUtils on FetchPolicy {
  bool get isNetwork => this == FetchPolicy.networkOnly || this == FetchPolicy.cacheAndNetwork;
  bool get isCache => this == FetchPolicy.cacheOnly || this == FetchPolicy.cacheAndNetwork;

  Future<T> fetch<T>({
    required String label,
    required Future<T> Function() remote,
    required Future<T> Function() getLocal,
    required Future<void> Function(T) setLocal,
    // Duration timeout = const Duration(seconds: 3),
  }) async {
    print('fetch policy: $label, $name');
    T? result;

    if (isNetwork) {
      try {
        print('fetching remote...');
        result = await remote();
      } catch (e) {
        print('error remote... $e');
        if (this == FetchPolicy.networkOnly) {
          throw Exception('Failed to get $e');
        }
      }
    }

    if (isCache) {
      if (result != null) {
        print('setting cache...');
        await setLocal(result);
      } else {
        print('fetching cache...');
        result = await getLocal();
      }
    }

    if (result == null) {
      throw Exception('Failed to get');
    }

    return result;
  }
}
