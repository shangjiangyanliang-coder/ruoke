import 'package:flutter_test/flutter_test.dart';
import 'package:ruoke/src/features/notes/models/library_location.dart';
import 'package:ruoke/src/features/notes/models/subject.dart';
import 'package:ruoke/src/features/notes/models/subject_folder.dart';
import 'package:ruoke/src/features/notes/utils/library_creation_scope.dart';

void main() {
  test('文件夹内新建书只允许选择当前文件夹及其后代', () {
    final scope = LibraryCreationScope.build(
      location: const LibraryLocation.folder('folder-a'),
      folders: [_folder('folder-a'), _folder('folder-b', 'folder-a'), _folder('other')],
      subjects: const [],
    );

    expect(
      scope.targetsFor(LibraryContentKind.book).map((target) => target.id),
      ['folder-a', 'folder-b'],
    );
  });

  test('根目录新建章节只允许选择书，新建节只允许选择章', () {
    final scope = LibraryCreationScope.build(
      location: const LibraryLocation.root(),
      folders: const [],
      subjects: [_subject('book', 0), _subject('chapter', 1, 'book'), _subject('section', 2, 'chapter')],
    );

    expect(scope.targetsFor(LibraryContentKind.chapter).map((target) => target.id), ['book']);
    expect(scope.targetsFor(LibraryContentKind.section).map((target) => target.id), ['chapter']);
  });
}

SubjectFolder _folder(String id, [String? parentId]) => SubjectFolder(
  id: id, parentId: parentId, name: id, sortOrder: 0, createdAt: 0, updatedAt: 0, isDeleted: false, deletedAt: null,
);

Subject _subject(String id, int level, [String? parentId]) => Subject(
  id: id, parentId: parentId, name: id, level: level, folderId: null, sortOrder: 0, createdAt: 0, updatedAt: 0, isDeleted: false, deletedAt: null,
);
