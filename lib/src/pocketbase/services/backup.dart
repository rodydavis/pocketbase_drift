import 'package:pocketbase/pocketbase.dart';

import '../pocketbase.dart';

class $BackupService extends BackupService {
  $BackupService(this.client) : super(client);

  @override
  final $PocketBase client;
}
