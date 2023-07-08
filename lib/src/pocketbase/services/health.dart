import 'package:pocketbase/pocketbase.dart';

import '../pocketbase.dart';

class $HealthService extends HealthService {
  $HealthService(this.client) : super(client);

  @override
  final $PocketBase client;
}
