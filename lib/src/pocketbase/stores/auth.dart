import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../database/database.dart';

class $AuthStore extends AuthStore {
  final DataBase db;

  $AuthStore(this.db) {
    debugPrint('initializing auth store');
    load();
  }

  Future<void> load() async {
    final result = await db.getAuthToken();
    debugPrint('auth token: $result');
    if (result != null) {
      final raw = result.token;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final token = decoded["token"] as String? ?? "";
      final model = decoded["model"] as Map<String, dynamic>? ?? {};
      final record = RecordModel.fromJson(model);
      save(token, record);
    }
  }

  @override
  void save(
    String newToken,
    dynamic /* RecordModel|AdminModel|null */ newModel,
  ) async {
    super.save(newToken, newModel);
    final encoded = jsonEncode(<String, dynamic>{
      "token": newToken,
      "model": newModel,
    });
    await db.setAuthToken(AuthTokensCompanion.insert(
      token: encoded,
      created: DateTime.now(),
    ));
    debugPrint('auth token saved: $encoded');
  }

  @override
  void clear() async {
    super.clear();
    await db.removeAuthToken();
  }
}