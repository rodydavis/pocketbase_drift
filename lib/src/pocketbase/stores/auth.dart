import 'package:pocketbase/pocketbase.dart';
import 'package:pocketbase_drift/src/database/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class $AuthStore extends AsyncAuthStore {
  $AuthStore({
    required super.save,
    super.initial,
    super.clear,
    this.clearOnLogout = true,
  });

  DataBase? db;

  /// Whether logging out deletes the cached data.
  ///
  /// Unsynced local changes are kept: they belong to the account that made
  /// them, stay hidden while another account is logged in, and sync when
  /// that account logs in again. Use [DataBase.clearAllData] to discard them.
  final bool clearOnLogout;

  @override
  void clear() {
    super.clear();
    if (clearOnLogout) {
      db?.clearCache(keepPending: true);
    }
  }

  factory $AuthStore.prefs(
    SharedPreferences prefs,
    String key, {
    bool clearOnLogout = true,
  }) {
    return $AuthStore(
      save: (data) async => await prefs.setString(key, data),
      initial: prefs.getString(key),
      clear: () async => await prefs.remove(key),
      clearOnLogout: clearOnLogout,
    );
  }
}
