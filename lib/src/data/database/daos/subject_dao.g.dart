// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subject_dao.dart';

// ignore_for_file: type=lint
mixin _$SubjectDaoMixin on DatabaseAccessor<AppDatabase> {
  $SubjectsTable get subjects => attachedDatabase.subjects;
  SubjectDaoManager get managers => SubjectDaoManager(this);
}

class SubjectDaoManager {
  final _$SubjectDaoMixin _db;
  SubjectDaoManager(this._db);
  $$SubjectsTableTableManager get subjects =>
      $$SubjectsTableTableManager(_db.attachedDatabase, _db.subjects);
}
