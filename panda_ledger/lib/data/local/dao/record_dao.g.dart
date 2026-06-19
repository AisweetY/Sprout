// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'record_dao.dart';

// ignore_for_file: type=lint
mixin _$RecordDaoMixin on DatabaseAccessor<AppDatabase> {
  $RecordsTable get records => attachedDatabase.records;
  RecordDaoManager get managers => RecordDaoManager(this);
}

class RecordDaoManager {
  final _$RecordDaoMixin _db;
  RecordDaoManager(this._db);
  $$RecordsTableTableManager get records =>
      $$RecordsTableTableManager(_db.attachedDatabase, _db.records);
}
