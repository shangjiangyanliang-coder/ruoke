// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_highlight_dao.dart';

// ignore_for_file: type=lint
mixin _$NoteHighlightDaoMixin on DatabaseAccessor<AppDatabase> {
  $NoteHighlightsTable get noteHighlights => attachedDatabase.noteHighlights;
  NoteHighlightDaoManager get managers => NoteHighlightDaoManager(this);
}

class NoteHighlightDaoManager {
  final _$NoteHighlightDaoMixin _db;
  NoteHighlightDaoManager(this._db);
  $$NoteHighlightsTableTableManager get noteHighlights =>
      $$NoteHighlightsTableTableManager(
        _db.attachedDatabase,
        _db.noteHighlights,
      );
}
