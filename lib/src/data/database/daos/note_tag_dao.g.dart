// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_tag_dao.dart';

// ignore_for_file: type=lint
mixin _$NoteTagDaoMixin on DatabaseAccessor<AppDatabase> {
  $NoteTagsTable get noteTags => attachedDatabase.noteTags;
  NoteTagDaoManager get managers => NoteTagDaoManager(this);
}

class NoteTagDaoManager {
  final _$NoteTagDaoMixin _db;
  NoteTagDaoManager(this._db);
  $$NoteTagsTableTableManager get noteTags =>
      $$NoteTagsTableTableManager(_db.attachedDatabase, _db.noteTags);
}
