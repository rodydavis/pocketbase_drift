import 'package:flutter/material.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

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
            for (final field in widget.collection.fields)
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

  final CollectionField field;
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