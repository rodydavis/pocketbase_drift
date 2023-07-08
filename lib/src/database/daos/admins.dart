import 'package:drift/drift.dart';
import 'package:pocketbase/pocketbase.dart';

import '../database.dart';
import '../tables.dart';
import 'base.dart';

part 'admins.g.dart';

@DriftAccessor(tables: [Admins])
class AdminsDao extends ServiceRecordsDao<$AdminsTable, Admin>
    with _$AdminsDaoMixin {
  AdminsDao(DataBase db) : super(db);

  @override
  $AdminsTable get table => admins;

  @override
  Insertable<Admin> toCompanion(Admin data) {
    return data.toCompanion(true).copyWith(
          id: data.id.isEmpty ? const Value.absent() : Value(data.id),
        );
  }

  @override
  Future<void> updateItem(Admin data) async {
    final companion = toCompanion(data);
    final existing = await (select(table)
          ..where((tbl) => tbl.id.equals(data.id)))
        .getSingleOrNull();
    if (existing == null) {
      await into(table).insert(companion);
    } else {
      await update(table).replace(companion);
    }
  }
}

extension AdminUtils on Admin {
  AdminModel toModel() {
    return AdminModel(
      id: id,
      created: created.toIso8601String(),
      updated: updated.toIso8601String(),
      avatar: avatar,
      email: email,
    );
  }
}

@DataClassName('Admin', extending: ServiceRecord)
class Admins extends Table with ServiceRecords {
  TextColumn get email => text()();
  IntColumn get avatar => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

extension AdminModelUtils on AdminModel {
  Admin toModel({
    required bool? synced,
    required bool? deleted,
    bool? isNew,
    bool? local,
  }) {
    return Admin(
      id: id,
      metadata: {
        'synced': synced,
        'deleted': deleted,
        if (isNew != null) 'new': isNew,
        if (local != null) 'local': local,
      },
      created: DateTime.tryParse(created) ?? DateTime.now(),
      updated: DateTime.tryParse(updated) ?? DateTime.now(),
      avatar: avatar,
      email: email,
    );
  }
}
