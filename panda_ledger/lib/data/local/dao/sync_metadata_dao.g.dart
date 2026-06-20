// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_metadata_dao.dart';

// ignore_for_file: type=lint
mixin _$SyncMetadataDaoMixin on DatabaseAccessor<AppDatabase> {
  $SyncMetadataTable get syncMetadata => attachedDatabase.syncMetadata;
  SyncMetadataDaoManager get managers => SyncMetadataDaoManager(this);
}

class SyncMetadataDaoManager {
  final _$SyncMetadataDaoMixin _db;
  SyncMetadataDaoManager(this._db);
  $$SyncMetadataTableTableManager get syncMetadata =>
      $$SyncMetadataTableTableManager(_db.attachedDatabase, _db.syncMetadata);
}
