import 'dart:async';

import 'package:flutter/material.dart';

import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:pocketbase_drift/src/database/connection/native.dart';
import 'package:simple_html_css/simple_html_css.dart';

import 'data_view.dart';

const username = 'test@admin.com';
const password = 'Password123';
const url = 'http://127.0.0.1:3000';

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
  final client = $PocketBase(
    url,
    connection: memoryDatabase(),
  );
  $RecordService? collection;
  CollectionModel? col;
  List<RecordModel> records = [];
  StreamSubscription? subscription;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    await client.admins.authWithPassword(
      username,
      password,
    );
    col = await client.collections.getOne('l1qxa33evkxxte0');
    collection = client.$collection(col!);
    subscription = collection!.watchRecords().stream.listen((event) {
      if (mounted) {
        setState(() {
          records = event;
        });
      }
    });
    if (mounted) {
      setState(() {
        loaded = true;
      });
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const title = Text('Pocketbase Drift Example');
    if (collection == null || col == null) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    final fields = col!.schema.toList();
    return Scaffold(
      appBar: AppBar(title: title),
      body: DataView<RecordModel>(
        columns: [
          const DataColumn(label: Text('ID')),
          ...fields.map((e) => DataColumn(label: Text(e.name))).toList(),
          const DataColumn(label: Text('Created')),
          const DataColumn(label: Text('Updated')),
        ],
        onTap: (item) {},
        match: (query, record) {
          if (query.trim().isEmpty) return true;
          final matches = <int>[];
          for (final field in fields) {
            final value = record.toJson()[field.name];
            if (value != null) {
              final match =
                  '$value'.toLowerCase().contains(query.toLowerCase());
              matches.add(match ? 1 : 0);
            }
          }
          return matches.any((e) => e == 1);
        },
        actions: (selection) => [],
        onSort: (items, colIndex, asc) {
          return items;
        },
        items: records,
        rowBuilder: (index, record) {
          return [
            DataCell(Text(record.id)),
            ...fields.map((e) {
              final value = record.toJson()[e.name];
              return DataCell(HTML.toRichText(
                context,
                '${value ?? ''}',
                defaultTextStyle:
                    Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
              ));
            }).toList(),
            DataCell(Text(record.created)),
            DataCell(Text(record.updated)),
          ];
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          await collection!.create(
            body: {
              'name': 'Record ${DateTime.now().millisecondsSinceEpoch}',
            },
          );
          if (mounted) setState(() {});
        },
      ),
    );
    // return Scaffold(
    //   appBar: AppBar(title: title),
    //   body: Column(
    //     children: [
    //       if (progress != null) LinearProgressIndicator(value: progress),
    //       Container(
    //         padding: const EdgeInsets.all(8),
    //         child: TextField(
    //           controller: controller,
    //           decoration: const InputDecoration(
    //             hintText: 'Search',
    //             border: OutlineInputBorder(),
    //           ),
    //           onChanged: (value) {
    //             if (mounted) {
    //               setState(() {});
    //             }
    //           },
    //         ),
    //       ),
    //       Expanded(
    //         child: controller.text.isNotEmpty
    //             ? FutureBuilder(
    //                 future: collection!.search(controller.text.trim()),
    //                 builder: (context, snapshot) {
    //                   if (snapshot.hasData) {
    //                     final records = snapshot.data!;
    //                     return buildList(context, records);
    //                   }
    //                   return const Center(
    //                     child: CircularProgressIndicator(),
    //                   );
    //                 },
    //               )
    //             : StreamBuilder<List<RecordModel>>(
    //                 stream: collection!.watchRecords().stream,
    //                 builder: (context, snapshot) {
    //                   if (snapshot.hasData) {
    //                     final records = snapshot.data!;
    //                     return buildList(context, records);
    //                   }
    //                   return const Center(
    //                     child: CircularProgressIndicator(),
    //                   );
    //                 },
    //               ),
    //       ),
    //     ],
    //   ),
    //   floatingActionButton: FloatingActionButton(
    //     child: const Icon(Icons.add),
    //     onPressed: () async {
    //       await collection!.create(
    //         body: {
    //           'name': 'Record ${DateTime.now().millisecondsSinceEpoch}',
    //         },
    //       );
    //       if (mounted) setState(() {});
    //     },
    //   ),
    // );
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
              await collection!.delete(record.id);
              if (mounted) setState(() {});
            },
          ),
        );
      },
    );
  }
}
