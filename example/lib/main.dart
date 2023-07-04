// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:simple_html_css/simple_html_css.dart';

import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:pocketbase_drift/src/database/connection/native.dart';

import 'widgets/data_view.dart';

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
    col = await client.collections.getOne(id);
    collection = client.$collection(col!);
    subscription?.cancel();
    subscription = collection!.watchRecords().stream.listen((event) {
      if (mounted) {
        setState(() {
          records = event;
        });
      }
    });
  }

  Future<void> init() async {
    await client.admins.authWithPassword(
      username,
      password,
    );
    collections = await client.collections.getFullList();
    await client.db.collectionsDao
        .addAll(collections.map((e) => e.toModel()).toList());
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
                  icon: const Icon(Icons.list_alt),
                  tooltip: 'Add 100 items',
                  onPressed: () async {
                    const total = 100;
                    for (var i = 0; i < total; i++) {
                      await collection!.create(
                        body: {'name': 'Record $i'},
                      );
                    }
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
            await collection!.create(body: result);
            if (mounted) setState(() {});
          }
        },
      ),
    );
  }
}

class CollectionForm extends StatefulWidget {
  const CollectionForm({
    Key? key,
    required this.collection,
    this.record,
  }) : super(key: key);

  final CollectionModel collection;
  final RecordModel? record;

  @override
  State<CollectionForm> createState() => _CollectionFormState();
}

class _CollectionFormState extends State<CollectionForm> {
  final _formKey = GlobalKey<FormState>();
  late final _data = <String, dynamic>{...widget.record?.data ?? {}};

  void reset() {
    _formKey.currentState!.reset();
    _data.clear();
    _data.addAll(widget.record?.data ?? {});
    if (mounted) setState(() {});
  }

  void save(BuildContext context) {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      Navigator.of(context).pop(_data);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.record == null
            ? 'New ${widget.collection.name}'
            : 'Edit ${widget.collection.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: () => reset(),
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () => save(context),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.always,
        child: ListView(
          children: [
            for (final field in widget.collection.schema)
              SchemeFieldFormField(
                field: field,
                data: _data,
              ),
          ],
        ),
      ),
    );
  }
}

class SchemeFieldFormField extends StatefulWidget {
  const SchemeFieldFormField({
    super.key,
    required this.field,
    required this.data,
  });

  final SchemaField field;
  final Map<String, dynamic> data;

  @override
  State<SchemeFieldFormField> createState() => _SchemeFieldFormFieldState();
}

class _SchemeFieldFormFieldState extends State<SchemeFieldFormField> {
  static const List<String> strings = ['text', 'editor'];

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(widget.field.name),
      subtitle: Builder(
        builder: (context) {
          final type = widget.field.type;
          if (strings.contains(type)) {
            return TextFormField(
              initialValue: widget.data[widget.field.name],
              onChanged: (value) {
                if (mounted) {
                  setState(() {
                    widget.data[widget.field.name] = value;
                  });
                }
              },
              validator: (val) {
                if (widget.field.required) {
                  final valid = val != null && val.trim().isNotEmpty;
                  return valid ? null : 'Field cannot be empty';
                }
                return null;
              },
            );
          }
          return Text(type);
        },
      ),
    );
  }
}
