import 'package:flutter/material.dart';

import 'package:pocketbase_drift/pocketbase_drift.dart';

const username = 'test@admin.com';
const password = 'Password123';
const url = 'http://127.0.0.1:8090';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pocketbase Drift Example',
      theme: ThemeData.dark(),
      home: const Example(),
    );
  }
}

class Example extends StatefulWidget {
  const Example({Key? key}) : super(key: key);

  @override
  State<Example> createState() => _ExampleState();
}

class _ExampleState extends State<Example> {
  double? progress;
  bool loaded = false;
  final client = PocketBaseDrift(url, dbName: 'database.db');
  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    await client.pocketbase.admins.authViaEmail(
      username,
      password,
    );
    if (mounted) {
      setState(() {
        loaded = true;
      });
    }
  }

  Future<void> refresh(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await for (final item in client.updateCollection('todo')) {
      debugPrint('progress: $item');
      if (mounted) {
        setState(() {
          progress = item;
        });
      }
    }
    if (mounted) {
      setState(() {
        progress = null;
      });
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Collection updated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    const title = Text('Pocketbase Drift Example');
    if (!loaded) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: title,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => refresh(context),
          ),
        ],
      ),
      body: Column(
        children: [
          if (progress != null) LinearProgressIndicator(value: progress),
          Container(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Search',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (mounted) {
                  setState(() {});
                }
              },
            ),
          ),
          Expanded(
            child: controller.text.isNotEmpty
                ? FutureBuilder(
                    future: client.search(
                      controller.text.trim(),
                      collection: 'todo',
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        final records = snapshot.data!;
                        return buildList(context, records);
                      }
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    },
                  )
                : RefreshIndicator(
                    onRefresh: () => refresh(context),
                    child: StreamBuilder<List<RecordModel>>(
                      stream: client.watchRecords('todo'),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          final records = snapshot.data!;
                          return buildList(context, records);
                        }
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget buildList(BuildContext context, List<RecordModel> records) {
    if (records.isEmpty) {
      return const Center(
        child: Text('No records found'),
      );
    }
    return ListView.separated(
      separatorBuilder: (context, index) => const Divider(),
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        return ListTile(
          isThreeLine: true,
          title: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'ID: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: record.id),
                const TextSpan(text: '\n'),
                const TextSpan(
                  text: 'Collection: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: record.collectionName),
              ],
            ),
          ),
          subtitle: Text(record.data['name']),
          trailing: IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              await client.deleteRecord('todo', record.id);
              if (mounted) setState(() {});
            },
          ),
        );
      },
    );
  }
}
