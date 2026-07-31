import 'package:flutter_test/flutter_test.dart';
import 'package:ruoke/src/features/notes/models/library_location.dart';
import 'package:ruoke/src/features/notes/models/library_navigation_state.dart';
import 'package:ruoke/src/features/notes/models/subject.dart';
import 'package:ruoke/src/features/notes/models/subject_folder.dart';
import 'package:ruoke/src/features/notes/utils/library_creation_scope.dart';
import 'package:ruoke/src/features/notes/utils/library_selection_rules.dart';

void main() {
  test('从文件夹开始选择不能进入兄弟文件夹', () {
    final rules = LibrarySelectionRules(
      folders: [_folder('a'), _folder('a-child', 'a'), _folder('b')],
      subjects: const [],
    );

    expect(
      rules.isWithinScope(
        origin: const LibraryLocation.folder('a'),
        candidate: const LibraryLocation.folder('a-child'),
      ),
      isTrue,
    );
    expect(
      rules.isWithinScope(
        origin: const LibraryLocation.folder('a'),
        candidate: const LibraryLocation.folder('b'),
      ),
      isFalse,
    );
  });

  test('内容和笔记位置只接受对应的合法层级', () {
    final rules = LibrarySelectionRules(
      folders: [_folder('folder')],
      subjects: [_subject('book', 0, folderId: 'folder'), _subject('chapter', 1, parentId: 'book')],
    );
    final content = LibrarySelectionSession(
      kind: LibrarySelectionKind.contentLocation,
      origin: const LibraryLocation.folder('folder'),
      previousBrowseMode: LibraryBrowseMode.drillDown,
      contentDraft: const LibraryContentDraft(
        kind: LibraryContentKind.chapter,
        name: '第一章',
      ),
    );
    final note = LibrarySelectionSession(
      kind: LibrarySelectionKind.noteLocation,
      origin: const LibraryLocation.folder('folder'),
      previousBrowseMode: LibraryBrowseMode.drillDown,
    );

    expect(rules.canSelectCurrent(session: content, location: const LibraryLocation.subject('book')), isTrue);
    expect(rules.canSelectCurrent(session: content, location: const LibraryLocation.subject('chapter')), isFalse);
    expect(rules.canSelectCurrent(session: note, location: const LibraryLocation.folder('folder')), isFalse);
    expect(rules.canSelectCurrent(session: note, location: const LibraryLocation.subject('chapter')), isTrue);
  });
}

SubjectFolder _folder(String id, [String? parentId]) => SubjectFolder(
  id: id, parentId: parentId, name: id, sortOrder: 0, createdAt: 0, updatedAt: 0, isDeleted: false, deletedAt: null,
);

Subject _subject(String id, int level, {String? parentId, String? folderId}) => Subject(
  id: id, parentId: parentId, name: id, level: level, folderId: folderId, sortOrder: 0, createdAt: 0, updatedAt: 0, isDeleted: false, deletedAt: null,
);
