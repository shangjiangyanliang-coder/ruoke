// 文件: test/features/notes/note_version_list_view_test.dart
// 作用: 验证历史版本列表页的管理入口和恢复确认选项。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/note.dart';
import 'package:ruoke/src/features/notes/models/note_search_query.dart';
import 'package:ruoke/src/features/notes/models/note_version.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/note_repository.dart';
import 'package:ruoke/src/features/notes/view/note_version_list_view.dart';

void main() {
  testWidgets('显示自定义版本名并可进入管理模式', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('关键节点'), findsOneWidget);
    expect(find.text('管理'), findsOneWidget);

    await tester.tap(find.text('管理'));
    await tester.pump();

    expect(find.text('已选 0 项'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.text('删除所选（0）'), findsOneWidget);
  });

  testWidgets('恢复确认默认不保存当前内容', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isFalse);
    expect(find.text('恢复前将当前内容保存为新版本'), findsOneWidget);
  });
}

Widget _app() => ProviderScope(
  overrides: [noteRepositoryProvider.overrideWithValue(_FakeRepository())],
  child: const MaterialApp(home: NoteVersionListView(noteId: 'note-1')),
);

class _FakeRepository implements NoteRepository {
  final versions = [
    const NoteVersion(
      id: 'version-1',
      noteId: 'note-1',
      versionNo: 1,
      snapshotJson: '[]',
      createdAt: 1,
      name: '关键节点',
    ),
  ];

  @override
  Future<Result<List<NoteVersion>>> listVersions(String noteId) async =>
      Success(versions);

  @override
  Future<Result<void>> renameVersion({
    required String noteId,
    required String versionId,
    required String? name,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> deleteVersions({
    required String noteId,
    required Set<String> versionIds,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> restoreVersion({
    required String noteId,
    required int versionNo,
    bool saveCurrentBeforeRestore = false,
  }) async => const Success<void>(null);

  @override
  Future<Result<List<Note>>> listAll() => throw UnimplementedError();

  @override
  Future<Result<List<Note>>> search(NoteSearchQuery query) =>
      throw UnimplementedError();

  @override
  Future<Result<Note?>> getById(String id) => throw UnimplementedError();

  @override
  Future<Result<Note>> create({
    required String subjectId,
    String? title,
    String? contentJson,
    String? plainText,
    bool isDraft = false,
    Iterable<String> tagNames = const [],
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> update({
    required String id,
    String? title,
    String? contentJson,
    String? plainText,
    bool? isDraft,
    Iterable<String>? tagNames,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> softDelete(String id) => throw UnimplementedError();
}
