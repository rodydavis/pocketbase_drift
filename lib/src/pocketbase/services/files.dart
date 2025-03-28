import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import "package:http/http.dart" as http;
import 'package:pocketbase_drift/pocketbase_drift.dart';

class $FileService extends FileService {
  $FileService(this.client) : super(client);

  @override
  final $PocketBase client;

  Future<Uint8List> getFileBytes({
    ({
      String collectionIdOrName,
      String recordId,
      String filename,
    })? details,
    RecordModel? record,
    String? filename,
    String? thumb,
    String? token,
    bool? download,
    Map<String, dynamic> query = const {},
    DataPolicy dataPolicy = DataPolicy.cacheAndNetwork,
  }) async {
    if (details == null && record == null) {
      throw 'Add either file details or record, both parameters cannot be null';
    }

    final collectionId = details?.collectionIdOrName ?? record!.collectionName;
    final recordId = details?.recordId ?? record!.id;
    final name = details?.filename ?? filename!;

    final params = Map<String, dynamic>.of(query);
    params["thumb"] ??= thumb;
    params["token"] ??= token;
    if (download != null && download) {
      params["download"] = "";
    }

    final url = client.buildURL(
      "/api/files/${Uri.encodeComponent(collectionId)}/${Uri.encodeComponent(recordId)}/${Uri.encodeComponent(name)}",
      params,
    );

    Uint8List? result;

    if (dataPolicy.isNetwork) {
      try {
        final response = await http.get(
          url,
          headers: {'Authorization': 'Bearer ${client.authStore.token}'},
        );
        result = response.bodyBytes;
      } catch (e) {
        final msg = 'Failed to get network file: $e';
        if (dataPolicy == DataPolicy.networkOnly) {
          throw Exception(msg);
        } else {
          debugPrint(msg);
        }
      }
    }

    if (dataPolicy.isCache) {
      if (result != null) {
        debugPrint('setting cache...');
        await client.db.setFile(recordId, name, result);
      } else {
        debugPrint('fetching cache...');
        final blob = await client.db.getFile(recordId, name).getSingle();
        result = blob.data;
      }
    }

    if (result == null) {
      throw Exception('Failed to get file');
    }
    return result;
  }
}
