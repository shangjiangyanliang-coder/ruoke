// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'folder_dao.dart';

// ignore_for_file: type=lint
mixin _$FolderDaoMixin on DatabaseAccessor<AppDatabase> {
  $SubjectFoldersTable get subjectFolders => attachedDatabase.subjectFolders;
  $SubjectsTable get subjects => attachedDatabase.subjects;
  FolderDaoManager get managers => FolderDaoManager(this);
}

class FolderDaoManager {
  final _$FolderDaoMixin _db;
  FolderDaoManager(this._db);
  $$SubjectFoldersTableTableManager get subjectFolders =>
      $$SubjectFoldersTableTableManager(
        _db.attachedDatabase,
        _db.subjectFolders,
      );
  $$SubjectsTableTableManager get subjects =>
      $$SubjectsTableTableManager(_db.attachedDatabase, _db.subjects);
}
