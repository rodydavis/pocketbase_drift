// Device performance harness for pocketbase_drift.
//
// Measures UI-isolate blocking, frame build times, image caching and
// connectivity probing on a real device/emulator against the backend in
// example/backend (it needs that backend's `posts`, `big`, `tasks`
// collections and its /api/lab/* control routes).
//
// Run:
//   1. Start the backend on the host:
//        cd example/backend && go build -o bin/server . \
//          && ./bin/server serve --http=127.0.0.1:8090
//      The sync-jank and expand-cost scenarios expect 5000 `big` rows; seed
//      them once with:
//        curl -X POST http://127.0.0.1:8090/api/lab/seed-big \
//          -H 'content-type: application/json' -d '{"count":5000}'
//   2. Forward the port to the device: adb reverse tcp:8090 tcp:8090
//   3. Build and install a profile APK with the scenarios to run, e.g.:
//        cd tool/device_lab
//        flutter build apk --profile --target-platform android-x64 \
//          --dart-define=AUTORUN=sync-jank-default,sync-jank-explicit
//        adb install -r build/app/outputs/flutter-apk/app-profile.apk
//      Scenario ids are the keys of [scenarios] below. Without AUTORUN the
//      app shows one button per scenario.
//   4. Launch the app and read the results:
//        adb logcat -s flutter | grep 'LAB '
//      Each scenario logs `LAB --- <id>`, one result line, and `LAB DONE`
//      after the last one.
//
// The `*-default` scenarios use the package's default database connection;
// the `*-explicit` ones pass `NativeDatabase.createInBackground` explicitly.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'lab_metrics.dart';

const baseUrl = 'http://127.0.0.1:8090';
const autorun = String.fromEnvironment('AUTORUN');

late String schemaJson;
final navKey = GlobalKey<NavigatorState>();
final logLines = ValueNotifier<List<String>>([]);

void log(String s) {
  labLog(s);
  logLines.value = [...logLines.value, s];
}

Future<dynamic> labPost(String path, Map<String, dynamic> body) async {
  final r = await http.post(Uri.parse('$baseUrl/api/lab$path'),
      headers: {'content-type': 'application/json'}, body: jsonEncode(body));
  return r.body.isEmpty ? null : jsonDecode(r.body);
}

Future<int> labRequests(String prefix) async {
  final r =
      jsonDecode((await http.get(Uri.parse('$baseUrl/api/lab/stats'))).body);
  var n = 0;
  for (final e in r['requests'] as List) {
    if ((e['route'] as String).startsWith(prefix)) n += e['count'] as int;
  }
  return n;
}

String connLabel(bool explicitBackground) =>
    explicitBackground ? 'explicit createInBackground' : 'default';

/// Fresh file-backed client. [explicitBackground] passes a drift connection
/// built with `NativeDatabase.createInBackground`; otherwise the package
/// default connection is used.
Future<$PocketBase> freshClient(String name,
    {bool explicitBackground = false}) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, '$name.db'));
  for (final f in [
    file,
    File('${file.path}-wal'),
    File('${file.path}-shm'),
    File('${file.path}-journal')
  ]) {
    if (f.existsSync()) f.deleteSync();
  }
  final client = $PocketBase.database(
    baseUrl,
    dbName: '$name.db',
    connection: explicitBackground
        ? DatabaseConnection(NativeDatabase.createInBackground(file))
        : null,
    authStore: $AuthStore(save: (_) async {}),
  );
  await client.setSchema(schemaJson);
  return client;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  schemaJson = await rootBundle.loadString('assets/pb_schema.json');
  runApp(const LabApp());
  if (autorun.isNotEmpty) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => runScenarios(autorun.split(',')));
  }
}

final scenarios = <String, Future<void> Function()>{
  'sync-jank-default': () => syncJank(explicitBackground: false),
  'sync-jank-explicit': () => syncJank(explicitBackground: true),
  'realtime-burst-default': () => realtimeBurst(explicitBackground: false),
  'realtime-burst-explicit': () => realtimeBurst(explicitBackground: true),
  'expand-cost': expandCost,
  'startup-schema': startupSchema,
  'image-race': imageRace,
  'images': () => imagesScenario(sized: false),
  'images-sized': () => imagesScenario(sized: true),
  'probe-cadence': probeCadence,
};

Future<void> runScenarios(List<String> ids) async {
  for (final id in ids) {
    final fn = scenarios[id];
    if (fn == null) {
      log('unknown scenario $id');
      continue;
    }
    log('--- $id');
    try {
      await fn();
    } catch (e, st) {
      log('$id FAILED: $e\n$st');
    }
  }
  log('DONE');
}

/// A list of posts with expand=author is on screen (like a feed tab), then
/// a 5000-row collection syncs: how long is the UI isolate blocked?
Future<void> syncJank({required bool explicitBackground}) async {
  final c = await freshClient(
      'jank_${explicitBackground ? 'explicit' : 'default'}',
      explicitBackground: explicitBackground);
  await c.collection('posts').getFullList(expand: 'author');
  final feed = c
      .collection('posts')
      .watchRecords(expand: 'author', sort: '-created')
      .listen((_) {});
  await Future<void>.delayed(const Duration(seconds: 2));
  navKey.currentState!
      .push(MaterialPageRoute<void>(builder: (_) => const SpinnerPage()));
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final lag = LoopLag()..start();
  final frames = FrameStats()..start();
  final sw = Stopwatch()..start();
  final done = Completer<void>();
  // No `limit`: the whole 5000-row collection is fetched and synced while
  // the spinner page measures the UI isolate.
  final sub = c.collection('big').watchRecordsState().listen((s) {
    if (!s.isFetchingNetwork && !done.isCompleted) done.complete();
  });
  await done.future.timeout(const Duration(minutes: 3));
  final fetchMs = sw.elapsedMilliseconds;
  await Future<void>.delayed(
      const Duration(seconds: 3)); // let syncLocal finish
  lag.stop();
  frames.stop();
  await sub.cancel();
  await feed.cancel();
  navKey.currentState!.pop();
  log('sync-jank conn=${connLabel(explicitBackground)}: '
      'big rows=${await c.db.$count('big')} fetch=${fetchMs}ms | $lag | $frames');
  c.close();
}

/// Four screens watch `posts` (one with expand). The server changes 30 posts
/// in quick succession (another user editing).
Future<void> realtimeBurst({required bool explicitBackground}) async {
  final c = await freshClient(
      'rt_${explicitBackground ? 'explicit' : 'default'}',
      explicitBackground: explicitBackground);
  final posts = await c.collection('posts').getFullList(expand: 'author');
  var emissions = 0;
  final subs = [
    c
        .collection('posts')
        .watchRecords(expand: 'author', sort: '-created')
        .listen((_) => emissions++),
    c.collection('posts').watchRecords(sort: '-created').listen((_) {}),
    c.collection('posts').watchRecords(filter: 'likes > 3').listen((_) {}),
    c.collection('posts').watchRecords(limit: 10).listen((_) {}),
  ];
  await Future<void>.delayed(const Duration(seconds: 5));
  navKey.currentState!
      .push(MaterialPageRoute<void>(builder: (_) => const SpinnerPage()));
  await Future<void>.delayed(const Duration(milliseconds: 500));
  emissions = 0;
  final lag = LoopLag()..start();
  final frames = FrameStats()..start();
  for (var i = 0; i < 30; i++) {
    await labPost('/mutate', {
      'collection': 'posts',
      'id': posts[i].id,
      'data': {'likes': 100 + i},
    });
  }
  await Future<void>.delayed(const Duration(seconds: 5));
  lag.stop();
  frames.stop();
  for (final s in subs) {
    await s.cancel();
  }
  navKey.currentState!.pop();
  log('realtime-burst conn=${connLabel(explicitBackground)}: 30 server edits, '
      '4 watchers -> feed emissions=$emissions | $lag | $frames');
  c.close();
}

Future<void> expandCost() async {
  final c = await freshClient('expand');
  await c.collection('posts').getFullList(expand: 'author');
  await c.collection('big').getFullList(batch: 1000);
  Future<int> t(Future<void> Function() f) async {
    final sw = Stopwatch()..start();
    await f();
    return sw.elapsedMilliseconds;
  }

  final n = await c.db.$count('posts');
  final plain = await t(() => c.db.$query('posts').get());
  final expanded = await t(() => c.db.$query('posts', expand: 'author').get());
  final bigScan = await t(() => c.db.$query('posts', sort: '-created').get());
  final bigAll = await t(() =>
      c.collection('big').getFullList(requestPolicy: RequestPolicy.cacheOnly));
  await c.db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_services_service ON services(service)');
  final indexed = await t(() => c.db.$query('posts', sort: '-created').get());
  log('expand-cost: $n posts plain=${plain}ms expand=author=${expanded}ms; '
      'posts sorted with 5000 big rows present=${bigScan}ms, with index=${indexed}ms; '
      'cacheOnly getFullList(big 5000)=${bigAll}ms');
  c.close();
}

/// README pattern: `$PocketBase.database(url)..setSchema(schema)` without
/// awaiting, then the first screen loads a record.
Future<void> startupSchema() async {
  final dir = await getApplicationDocumentsDirectory();
  final f = File(p.join(dir.path, 'startup.db'));
  if (f.existsSync()) f.deleteSync();
  final posts = jsonDecode((await http
          .get(Uri.parse('$baseUrl/api/collections/posts/records?perPage=1')))
      .body);
  final id = posts['items'][0]['id'] as String;
  final c = $PocketBase.database(baseUrl,
      dbName: 'startup.db', authStore: $AuthStore(save: (_) async {}))
    ..setSchema(schemaJson);
  final r = await c.collection('posts').getOne(id);
  Object? writeErr;
  try {
    await c.collection('tasks').create(
        body: {'title': 'first'}, requestPolicy: RequestPolicy.cacheOnly);
  } catch (e) {
    writeErr = e;
  }
  await Future<void>.delayed(const Duration(seconds: 1));
  final cached = await c
      .collection('posts')
      .getOneOrNull(id, requestPolicy: RequestPolicy.cacheOnly);
  log('startup-schema: getOne from network ok=${r.id == id}; cached afterwards=${cached != null}; '
      'first cacheOnly write error=${writeErr?.toString().split('\n').first}');
  c.close();
}

/// Six widgets ask for the same uncached image at once (avatar in a list).
Future<void> imageRace() async {
  final c = await freshClient('imgrace');
  final post = (await c.collection('posts').getList(perPage: 1)).items.first;
  final fn = post.getListValue<String>('images').first;
  final expected = (await http.get(c.files.getURL(post, fn))).bodyBytes.length;
  final results = await Future.wait([
    for (var i = 0; i < 6; i++)
      c.files
          .getFileBytes(
              recordId: post.id, recordCollectionName: 'posts', filename: fn)
          .then((b) =>
              b.length == expected ? 'ok' : 'WRONG ${b.length}/$expected')
          .catchError((Object e) =>
              'ERR ${e.runtimeType}: ${e.toString().split('\n').first}'),
  ]);
  final blobs = await c.db.getFilesForRecord(post.id).get();
  log('image-race: 6 concurrent getFileBytes(same file) -> $results; blob rows=${blobs.length}');
  c.close();
}

late $PocketBase imageClient;

/// [sized] passes the tile size, so images decode at display size instead of
/// full resolution.
Future<void> imagesScenario({required bool sized}) async {
  imageClient = await freshClient('images');
  final posts =
      await imageClient.collection('posts').getFullList(sort: 'created');
  await labPost('/stats/reset', {});
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  final lag = LoopLag()..start();
  final page = GlobalKey<FeedPageState>();
  navKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => FeedPage(key: page, posts: posts, sized: sized)));
  await Future<void>.delayed(const Duration(seconds: 15));
  final cache = PaintingBinding.instance.imageCache;
  final firstCount = cache.currentSize;
  final firstBytes = cache.currentSizeBytes;
  final firstDownloads = await labRequests('GET /api/files');
  final label = sized ? 'images-sized' : 'images';
  log('$label: after first load -> imageCache entries=$firstCount bytes=${(firstBytes / 1e6).toStringAsFixed(1)}MB '
      'downloads=$firstDownloads | $lag');
  final lag2 = LoopLag()..start();
  for (var i = 0; i < 10; i++) {
    page.currentState!.bump();
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
  await Future<void>.delayed(const Duration(seconds: 3));
  lag2.stop();
  log('$label: after 10 parent rebuilds -> imageCache entries=${cache.currentSize} '
      'bytes=${(cache.currentSizeBytes / 1e6).toStringAsFixed(1)}MB loads=${page.currentState!.loads} '
      'downloads=${await labRequests('GET /api/files')} | $lag2');
  lag.stop();
  // Leave the feed so its images stop being live and the next scenario
  // starts from an empty cache.
  navKey.currentState!.pop();
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

Future<void> probeCadence() async {
  final c = await freshClient('probe');
  final ifaces = await Connectivity().checkConnectivity();
  await labPost('/stats/reset', {});
  await Future<void>.delayed(const Duration(seconds: 130));
  log('probe-cadence: connectivity_plus=$ifaces shouldAttemptNetwork=${c.connectivity.shouldAttemptNetwork} '
      'isConnected=${c.connectivity.isConnected}; /api/health probes in 130s=${await labRequests('GET /api/health')}');
  c.close();
}

class LabApp extends StatelessWidget {
  const LabApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navKey,
        title: 'pbd lab',
        home: Scaffold(
          appBar: AppBar(title: const Text('pocketbase_drift lab')),
          body: Column(children: [
            Wrap(spacing: 6, children: [
              for (final id in scenarios.keys)
                ElevatedButton(
                    onPressed: () => runScenarios([id]), child: Text(id)),
            ]),
            Expanded(
              child: ValueListenableBuilder<List<String>>(
                valueListenable: logLines,
                builder: (_, lines, __) => ListView(
                  children: [
                    for (final l in lines)
                      Text(l, style: const TextStyle(fontSize: 11))
                  ],
                ),
              ),
            ),
          ]),
        ),
      );
}

class SpinnerPage extends StatelessWidget {
  const SpinnerPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// Feed of posts with PocketBaseImageProvider thumbnails, rebuilt by its
/// parent the way a list reacts to watcher emissions.
class FeedPage extends StatefulWidget {
  const FeedPage({super.key, required this.posts, this.sized = false});
  final List<RecordModel> posts;
  final bool sized;
  @override
  State<FeedPage> createState() => FeedPageState();
}

class FeedPageState extends State<FeedPage> {
  int generation = 0;

  /// First frames shown after the image had none (initial loads and
  /// reloads); a rebuild that keeps the cached image does not count.
  int loads = 0;
  final _lastFrame = <int, int?>{};
  void bump() => setState(() => generation++);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('feed gen $generation')),
        body: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3),
          itemCount: widget.posts.length,
          itemBuilder: (_, i) {
            final post = widget.posts[i];
            final file = post.getListValue<String>('images').first;
            return Image(
              image: PocketBaseImageProvider(
                client: imageClient,
                recordId: post.id,
                recordCollectionName: 'posts',
                filename: file,
                size: widget.sized ? const Size(120, 120) : null,
              ),
              frameBuilder: (_, child, frame, __) {
                if (frame == 0 && _lastFrame[i] != 0) loads++;
                _lastFrame[i] = frame;
                return child;
              },
              width: 120,
              height: 120,
              fit: BoxFit.cover,
            );
          },
        ),
      );
}
