// 文件: lib/src/features/notes/view_model/subject_manage_view_model.dart
// 作用: 学科管理页 ViewModel（手写 AsyncNotifier）。列出全量科目（不构造树，
//       扁平展示，含软删），提供新建子节点、改名、软删。用于"我的"tab 学科管理入口。
//       与 SubjectTreeVm 共享 subjectRepository，但不构造嵌套树——管理页是扁平列表。
//       详见技术方案 A §4.2 + 阶段5 第3批计划 §二。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/errors/result.dart';
import '../models/subject.dart';
import '../providers.dart';

/// 学科管理页状态。
class SubjectManageState {
  /// 全量未软删科目（含 level0/1/2），按 sortOrder 升序。
  final List<Subject> subjects;

  const SubjectManageState({this.subjects = const []});
}

/// 学科管理 ViewModel。
class SubjectManageVm extends AsyncNotifier<SubjectManageState> {
  @override
  Future<SubjectManageState> build() async => _load();

  Future<SubjectManageState> _load() async {
    final r = await ref.read(subjectRepositoryProvider).listAll();
    if (r is Success<List<Subject>>) {
      return SubjectManageState(subjects: r.value);
    }
    throw (r as Failure<List<Subject>>).exception;
  }

  /// 新建子节点。返新 id，失败抛异常。
  Future<String> create({
    required String name,
    required int level,
    String? parentId,
  }) async {
    final r = await ref
        .read(subjectRepositoryProvider)
        .create(name: name, level: level, parentId: parentId);
    if (r is Success<String>) {
      await _reload();
      return r.value;
    }
    throw (r as Failure<String>).exception;
  }

  /// 软删某节点。
  Future<void> delete(String id) async {
    final r = await ref.read(subjectRepositoryProvider).softDelete(id);
    if (r is! Success) throw (r as Failure).exception;
    await _reload();
  }

  /// 刷新列表（外部操作后调）。
  Future<void> refresh() async => _reload();

  Future<void> _reload() async {
    state = await AsyncValue.guard(_load);
  }
}
