import 'dart:async';

import 'package:drift/drift.dart';

/// Per-collection stream invalidation for the shared `services` table.
///
/// Drift reports a write to `services` as `TableUpdate('services')`, so a
/// write to any collection would re-run every query that reads `services`.
/// The database tags its own writes with their collection ([tagged]); the
/// update rules then add a pseudo-table update `services/<collection>`.
/// Untagged writes (raw SQL through `client.db`, `markTablesUpdated`, TTL
/// cleanup) add `services/*`. Record watchers read from the pseudo tables of
/// their collection and of the collections they expand, and from
/// `services/*`. Queries that read `services` itself re-run on every write.
const _serviceTag = #pocketbaseDriftService;

/// Name of the pseudo table updated by writes to [service].
String serviceTableName(String service) => 'services/$service';

/// Pseudo table updated by writes whose collection is unknown.
const anyServiceTableName = 'services/*';

/// Runs [action] with its `services` writes attributed to [service].
///
/// Wrap only database statements: user code called inside the zone would
/// attribute its own writes to [service].
Future<T> tagged<T>(String service, Future<T> Function() action) =>
    runZoned(action, zoneValues: {_serviceTag: service});

/// Adds the pseudo-table updates for writes to `services`.
class ServiceUpdateRules extends StreamQueryUpdateRules {
  ServiceUpdateRules(this._inner, this._servicesTable) : super(_inner.rules);

  final StreamQueryUpdateRules _inner;
  final String _servicesTable;

  @override
  Set<TableUpdate> apply(Iterable<TableUpdate> input) {
    final out = _inner.apply(input);
    final writes = [
      for (final update in out)
        if (update.table == _servicesTable) update.kind,
    ];
    if (writes.isEmpty) return out;
    final service = Zone.current[_serviceTag] as String?;
    final table =
        service == null ? anyServiceTableName : serviceTableName(service);
    for (final kind in writes) {
      out.add(TableUpdate(table, kind: kind));
    }
    return out;
  }
}

/// A pseudo result set: only its name is used, as `readsFrom` of a stream
/// query, so the stream re-runs on updates of that name.
class ServiceTopic extends ResultSetImplementation<ServiceTopic, Never> {
  ServiceTopic(this.attachedDatabase, this.entityName);

  @override
  final DatabaseConnectionUser attachedDatabase;

  @override
  final String entityName;

  @override
  ServiceTopic get asDslTable => this;

  @override
  List<GeneratedColumn> get $columns => const [];

  @override
  Map<String, GeneratedColumn> get columnsByName => const {};

  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) =>
      throw UnsupportedError('ServiceTopic is not a table');
}
