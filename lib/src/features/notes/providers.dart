// 文件: lib/src/features/notes/providers.dart
// 作用: 笔记模块的 Riverpod Provider 集合（全部手写，不走 generator 以避开 4.x 注解坑）。
//       - appDatabaseProvider: 数据库单例（全项目共享，未来抽到 data 层全局）
//       - noteRepositoryProvider: Repository 实例（注入 db）
//       - subjectRepositoryProvider: 科目树 Repository（注入 db）
//       两个带状态 ViewModel 的 Provider 见 view_model/view_model_providers.dart。
//       详见技术方案 A §四 Riverpod 划分原则。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import 'repository/folder_repository.dart';
import 'repository/local_folder_repository.dart';
import 'repository/local_note_repository.dart';
import 'repository/local_subject_repository.dart';
import 'repository/local_tag_repository.dart';
import 'repository/note_repository.dart';
import 'repository/subject_repository.dart';
import 'repository/tag_repository.dart';
import 'view_model/library_organization_controller.dart';

/// 数据库单例 Provider（全项目共享）。后续抽到 data/ 全局，暂放笔记模块。
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// NoteRepository Provider：注入 db，返回 LocalNoteRepository。
final Provider<NoteRepository> noteRepositoryProvider =
    Provider<NoteRepository>((ref) {
      return LocalNoteRepository(ref.watch(appDatabaseProvider));
    });

/// SubjectRepository Provider：注入 db，返回 LocalSubjectRepository。
final Provider<SubjectRepository> subjectRepositoryProvider =
    Provider<SubjectRepository>((ref) {
      return LocalSubjectRepository(ref.watch(appDatabaseProvider));
    });

/// FolderRepository Provider：提供文件夹创建、移动和安全解散能力。
final Provider<FolderRepository> folderRepositoryProvider =
    Provider<FolderRepository>((ref) {
      return LocalFolderRepository(ref.watch(appDatabaseProvider));
    });

/// TagRepository Provider：注入 db，管理标签及笔记标签关联。
final Provider<TagRepository> tagRepositoryProvider = Provider<TagRepository>((
  ref,
) {
  return LocalTagRepository(ref.watch(appDatabaseProvider));
});

/// 目录排序与移动控制器：只依赖仓储接口，供排序页和移动页复用。
final Provider<LibraryOrganizationController>
libraryOrganizationControllerProvider = Provider<LibraryOrganizationController>(
  (ref) {
    return LibraryOrganizationController(
      folders: ref.watch(folderRepositoryProvider),
      subjects: ref.watch(subjectRepositoryProvider),
      notes: ref.watch(noteRepositoryProvider),
    );
  },
);
