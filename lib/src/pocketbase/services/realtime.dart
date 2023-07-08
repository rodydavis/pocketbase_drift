import 'package:pocketbase/pocketbase.dart';

import '../pocketbase.dart';

class $RealtimeService extends RealtimeService {
  $RealtimeService(this.client) : super(client);

  @override
  final $PocketBase client;
}
