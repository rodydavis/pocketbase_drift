import 'package:pocketbase/pocketbase.dart';

import '../pocketbase.dart';

class $LogService extends LogService {
  $LogService(this.client) : super(client);

  @override
  final $PocketBase client;
}
