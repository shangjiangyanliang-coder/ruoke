// 作用：验证目录移动目标、层级约束与搜索祖先保留规则。
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/features/notes/models/library_organization.dart';
import 'package:ruoke/src/features/notes/models/subject.dart';
import 'package:ruoke/src/features/notes/models/subject_folder.dart';
import 'package:ruoke/src/features/notes/utils/library_organization_rules.dart';

void main() {
  final folders = [
    _folder('folder-a', '资料 A'),
    _folder('folder-child', '子目录', parentId: 'folder-a'),
    _folder('folder-grandchild', '孙目录', parentId: 'folder-child'),
    _folder('folder-b', '资料 B'),
  ];
  final subjects = [
    _subject('book-a', '数学', 0, folderId: 'folder-a'),
    _subject('book-b', '数学', 0, folderId: 'folder-b'),
    _subject('book-root', '语文', 0),
    _subject('chapter-a', '函数', 1, parentId: 'book-a'),
    _subject('chapter-b', '函数', 1, parentId: 'book-b'),
    _subject('section-a', '一次函数', 2, parentId: 'chapter-a'),
  ];

  test('文件夹目标包含根目录和其他文件夹并排除自身及后代', () {
    final targets = buildMoveTargets(
      request: const LibraryMoveRequest(
        kind: LibraryItemKind.folder,
        itemId: 'folder-a',
        itemName: '资料 A',
      ),
      folders: folders,
      subjects: subjects,
    );

    expect(
      targets.any((target) => target.id == null && target.canSelect),
      isTrue,
    );
    expect(targets.map((target) => target.id), contains('folder-b'));
    expect(
      targets.map((target) => target.id).toSet().intersection({
        'folder-a',
        'folder-child',
        'folder-grandchild',
      }),
      isEmpty,
    );
    expect(
      targets
          .where((target) => target.id != null)
          .every((target) => target.canSelect),
      isTrue,
    );
  });

  test('书目标包含根目录和全部文件夹', () {
    final targets = buildMoveTargets(
      request: const LibraryMoveRequest(
        kind: LibraryItemKind.book,
        itemId: 'book-a',
        itemName: '数学',
      ),
      folders: folders,
      subjects: subjects,
    );

    expect(targets.where((target) => target.canSelect), hasLength(5));
    expect(
      targets.where((target) => target.kind == LibraryItemKind.book),
      isEmpty,
    );
  });

  test('章只能选择书，文件夹只作为展开路径', () {
    final targets = buildMoveTargets(
      request: const LibraryMoveRequest(
        kind: LibraryItemKind.chapter,
        itemId: 'chapter-a',
        itemName: '函数',
      ),
      folders: folders,
      subjects: subjects,
    );

    expect(
      targets
          .where((target) => target.canSelect)
          .map((target) => target.kind)
          .toSet(),
      {LibraryItemKind.book},
    );
    expect(
      targets
          .where((target) => target.kind == LibraryItemKind.folder)
          .every((target) => !target.canSelect),
      isTrue,
    );
    expect(
      targets.any((target) => target.kind == LibraryItemKind.chapter),
      isFalse,
    );
  });

  test('节只能选择章，笔记只能选择书章节', () {
    final sectionTargets = buildMoveTargets(
      request: const LibraryMoveRequest(
        kind: LibraryItemKind.section,
        itemId: 'section-a',
        itemName: '一次函数',
      ),
      folders: folders,
      subjects: subjects,
    );
    final noteTargets = buildMoveTargets(
      request: const LibraryMoveRequest(
        kind: LibraryItemKind.note,
        itemId: 'note-a',
        itemName: '笔记',
      ),
      folders: folders,
      subjects: subjects,
    );

    expect(
      sectionTargets
          .where((target) => target.canSelect)
          .map((target) => target.kind)
          .toSet(),
      {LibraryItemKind.chapter},
    );
    expect(
      noteTargets
          .where((target) => target.canSelect)
          .map((target) => target.kind)
          .toSet(),
      {LibraryItemKind.book, LibraryItemKind.chapter, LibraryItemKind.section},
    );
  });

  test('搜索命中节点时保留祖先路径', () {
    final targets = buildMoveTargets(
      request: const LibraryMoveRequest(
        kind: LibraryItemKind.note,
        itemId: 'note-a',
        itemName: '笔记',
      ),
      folders: folders,
      subjects: subjects,
    );
    final visible = visibleTargetIds(keyword: '一次函数', targets: targets);

    expect(
      visible,
      containsAll([
        'folder:folder-a',
        'book:book-a',
        'chapter:chapter-a',
        'section:section-a',
      ]),
    );
    expect(visible, isNot(contains('folder:folder-b')));
  });

  test('同名节点通过完整路径区分', () {
    final targets = buildMoveTargets(
      request: const LibraryMoveRequest(
        kind: LibraryItemKind.section,
        itemId: 'section-a',
        itemName: '一次函数',
      ),
      folders: folders,
      subjects: subjects,
    );
    final chapters = targets.where((target) => target.label == '函数').toList();

    expect(chapters, hasLength(2));
    expect(chapters.map((target) => target.pathLabels.join(' / ')).toSet(), {
      '资料 A / 数学 / 函数',
      '资料 B / 数学 / 函数',
    });
  });
}

SubjectFolder _folder(String id, String name, {String? parentId}) =>
    SubjectFolder(
      id: id,
      parentId: parentId,
      name: name,
      sortOrder: 0,
      createdAt: 1,
      updatedAt: 1,
      isDeleted: false,
      deletedAt: null,
    );

Subject _subject(
  String id,
  String name,
  int level, {
  String? parentId,
  String? folderId,
}) => Subject(
  id: id,
  parentId: parentId,
  name: name,
  level: level,
  folderId: folderId,
  sortOrder: 0,
  createdAt: 1,
  updatedAt: 1,
  isDeleted: false,
  deletedAt: null,
);
