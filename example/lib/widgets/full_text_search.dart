import 'package:flutter/material.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

class FullTextSearch extends StatefulWidget {
  const FullTextSearch({
    super.key,
    required this.records,
  });

  final $RecordService records;

  @override
  State<FullTextSearch> createState() => _FullTextSearchState();
}

class _FullTextSearchState extends State<FullTextSearch> {
  double? progress;
  List<RecordModel> records = [];
  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Search',
            border: InputBorder.none,
          ),
          onChanged: (value) async {
            if (value.isEmpty) {
              records = [];
            } else {
              records = await widget.records.search(value);
            }
            if (mounted) {
              setState(() {});
            }
          },
        ),
      ),
      body: Builder(
        builder: (context) {
          if (records.isEmpty) {
            return const Center(child: Text('No records found'));
          }
          return ListView.builder(
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              final data = record.data;
              final values = data.values.toList().join(', ');
              final columns = data.keys.toList().join(', ');
              return ListTile(
                isThreeLine: true,
                title: Text(record.id),
                subtitle: Text('$columns\n$values'),
              );
            },
          );
        },
      ),
    );
  }
}
