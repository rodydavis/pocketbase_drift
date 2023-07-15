import '../../../pocketbase_drift.dart';

class $AdminsService extends AdminService with ServiceMixin<AdminModel> {
  $AdminsService(this.client) : super(client);

  @override
  final $PocketBase client;

  @override
  final String service = 'admin';
}
