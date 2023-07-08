// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:simple_html_css/simple_html_css.dart';

import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'data/collections.json.dart';
import 'data/todos.json.dart';
import 'widgets/collection_form.dart';
import 'widgets/data_view.dart';
import 'widgets/full_text_search.dart';
import 'widgets/pending_changes.dart';

const url = 'http://127.0.0.1:3000';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // PocketBaseHttpClient.offline = true;R
  final client = $PocketBase.database(
    url,
    inMemory: true,
    httpClientFactory: () => PocketBaseHttpClient(),
  )..logging = kDebugMode;
  runApp(MyApp(client: client));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.client});
  final $PocketBase client;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pocketbase Drift Example',
      theme: ThemeData.dark(),
      home: Example(client: client),
    );
  }
}

class Example extends StatefulWidget {
  const Example({super.key, required this.client});
  final $PocketBase client;

  @override
  State<Example> createState() => _ExampleState();
}

class _ExampleState extends State<Example> {
  bool loaded = false;

  List<CollectionModel> collections = [];
  $RecordService? collection;
  CollectionModel? col;
  List<RecordModel> records = [];
  StreamSubscription? subscription;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> select(String id) async {
    col = await widget.client.collections.getOne(
      id,
      fetchPolicy: FetchPolicy.cacheOnly,
    );
    collection = widget.client.$collection(col!);
    subscription?.cancel();
    final (stream, cancel) = await collection!.watchRecords();
    subscription = stream.listen(
      (event) {
        debugPrint('items: ${event.length}');
        if (mounted) {
          setState(() {
            records = event;
          });
        }
      },
      onDone: cancel,
    );
  }

  Future<void> init() async {
    // Could fetch from API, but for now just use the offline data
    final c = jsonDecode(jsonEncode(offlineCollections)) as List;
    collections = c.map((e) => CollectionModel.fromJson(e)).toList();
    await widget.client.collections.setLocal(collections);
    final users = collections.firstWhere((e) => e.name == 'users');
    final record = widget.client //
        .$collection(users)
        .authWithPassword('rodydavis', 'password');
    debugPrint('auth record: $record');
    if (collections.isNotEmpty) {
      await select(collections.first.id);
    }
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
    if (!loaded) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (col == null) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: ListView.builder(
          itemCount: collections.length,
          itemBuilder: (context, index) {
            final item = collections[index];
            return ListTile(
              title: Text(item.name),
              selected: col?.id == item.id,
              onTap: () async {
                await select(item.id);
                if (mounted) {
                  setState(() {});
                }
              },
            );
          },
        ),
      );
    }
    final fields = col!.schema.toList();
    return Scaffold(
      appBar: AppBar(
        title: title,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Full text search (local records)',
            onPressed: collection == null
                ? null
                : () async {
                    final nav = Navigator.of(context);
                    nav.push(
                      MaterialPageRoute(
                        builder: (context) => FullTextSearch(
                          records: collection!,
                        ),
                      ),
                    );
                  },
          ),
          if (collection != null && col!.name == 'todo')
            IconButton(
              icon: const Icon(Icons.add_box_outlined),
              tooltip: 'Add offline only records',
              onPressed: () async {
                final items = LOCAL_TODOS
                    .map((e) => RecordModel(
                          id: widget.client.db.generateId(),
                          created: DateTime.now().toIso8601String(),
                          updated: DateTime.now().toIso8601String(),
                          data: {
                            'name': e['title'],
                          },
                          collectionId: col!.id,
                          collectionName: col!.name,
                        ))
                    .toList();
                await collection!.setLocal(items);
              },
            ),
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Show pending changes',
            onPressed: collection == null
                ? null
                : () async {
                    final nav = Navigator.of(context);
                    nav.push(
                      MaterialPageRoute(
                        builder: (context) => PendingChanges(
                          records: collection!,
                        ),
                      ),
                    );
                  },
          ),
          const SizedBox(width: 8),
          DropdownButton(
            value: PocketBaseHttpClient.offline,
            items: const [
              DropdownMenuItem(
                value: true,
                child: Text('Offline'),
              ),
              DropdownMenuItem(
                value: false,
                child: Text('Online'),
              ),
            ],
            onChanged: (value) async {
              PocketBaseHttpClient.offline = value!;
              if (mounted) {
                setState(() {});
              }
            },
          ),
          const SizedBox(width: 8),
          DropdownButton(
            value: col?.id,
            items: collections
                .map(
                  (e) => DropdownMenuItem(
                    value: e.id,
                    child: Text(e.name),
                  ),
                )
                .toList(),
            onChanged: (value) async {
              await select(value!);
              if (mounted) {
                setState(() {});
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
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
        actions: (selection) => selection.isEmpty
            ? [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await collection!.getFullList();
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Refreshed'),
                      ),
                    );
                  },
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete ${selection.length} rows',
                  onPressed: () async {
                    for (final item in selection) {
                      await collection!.delete(item.id);
                    }
                  },
                ),
              ],
        onSort: (items, colIndex, asc) {
          final list = items.toList();
          list.sort((a, b) {
            final aData = a.toJson();
            final bData = b.toJson();
            final fieldKeys = [
              'id',
              ...fields.map((e) => e.name).toList(),
              'created',
              'updated',
            ];
            final aValue = aData[fieldKeys[colIndex]];
            final bValue = bData[fieldKeys[colIndex]];
            if (aValue is Comparable && bValue is Comparable) {
              if (asc) {
                return aValue.compareTo(bValue);
              } else {
                return bValue.compareTo(aValue);
              }
            } else {
              return 0;
            }
          });
          return list;
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
          final nav = Navigator.of(context);
          final result = await nav.push<Map<String, dynamic>?>(
            MaterialPageRoute(
              builder: (context) => CollectionForm(
                collection: col!,
              ),
              fullscreenDialog: true,
            ),
          );
          if (result != null) {
            await collection!.create(
              body: result,
              // fetchPolicy: FetchPolicy.cacheOnly,
            );
            if (mounted) setState(() {});
          }
        },
      ),
    );
  }
}
