import 'package:flutter/material.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

class PendingChanges extends StatefulWidget {
  const PendingChanges({
    super.key,
    required this.records,
  });

  final $RecordService records;

  @override
  State<PendingChanges> createState() => _PendingChangesState();
}

class _PendingChangesState extends State<PendingChanges> {
  double? progress;
  List<Record>? records;

  @override
  void initState() {
    super.initState();
    getPending();
  }

  Future<void> getPending() async {
    final items = await widget.records.getPending();
    if (mounted) {
      setState(() {
        records = items;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Changes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Retry offline items',
            onPressed: records == null || records!.isEmpty
                ? null
                : () async {
                    widget.records.retryLocal().listen((event) {
                      if (mounted) {
                        setState(() {
                          progress = event?.progress;
                        });
                      }
                    }).onDone(getPending);
                  },
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (records == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (records!.isEmpty) {
            return const Center(child: Text('No pending changes'));
          }
          return Column(
            children: [
              if (progress != null) LinearProgressIndicator(value: progress),
              Expanded(
                child: ListView(
                  children: [
                    for (final record in records!)
                      Builder(
                        builder: (context) {
                          final deleted = record.metadata['deleted'] == true;
                          return ListTile(
                            title: Text(record.id),
                            subtitle:
                                Text(deleted ? 'Deleted' : 'Updated/Created'),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
