import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

class PocketBaseHttpClient extends http.BaseClient {
  final http.Client _inner;
  static bool offline = false;

  PocketBaseHttpClient(this._inner);

  factory PocketBaseHttpClient.retry({
    int retries = 3,
    http.Client? client,
  }) {
    final baseClient = client ?? http.Client();
    return PocketBaseHttpClient(RetryClient(baseClient, retries: retries));
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (offline) throw Exception('No internet connection');
    debugPrint('request: ${request.method} ${request.url}');
    return _inner.send(request);
  }
}
