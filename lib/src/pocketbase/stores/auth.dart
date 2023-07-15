import 'dart:convert';

import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class $AuthStore extends AuthStore {
  final SharedPreferences prefs;
  final String key;

  $AuthStore(this.prefs, {this.key = "pb_auth"}) {
    reload();
  }

  @override
  void save(
    String newToken,
    dynamic /* RecordModel|AdminModel|null */ newModel,
  ) {
    print('saving token: $newToken model: $newModel');
    super.save(newToken, newModel);

    final encoded = jsonEncode(<String, dynamic>{"token": newToken, "model": newModel});
    prefs.setString(key, encoded);
  }

  @override
  void clear() {
    super.clear();
    print('clearing token');
    prefs.remove(key);
  }

  Future<void> reload() async {
    final String? raw = prefs.getString(key);
    print('loading token: $raw');

    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      final token = (decoded as Map<String, dynamic>)["token"] as String? ?? "";
      final model = RecordModel.fromJson(decoded["model"] as Map<String, dynamic>? ?? {});

      save(token, model);
    }
  }
}
