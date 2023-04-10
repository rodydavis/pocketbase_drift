# Test instructions

1. Open local pocketbase instance: `$ ./pocketbase serve`
2. Create admin account with `username=test@admin.com` and `password=Password123`.
3. Import test-pb_schema.json in the admin UI (which contains a collection named "todo").
4. Run the test: `flutter test test/pocketbase_drift_store_test.dart`