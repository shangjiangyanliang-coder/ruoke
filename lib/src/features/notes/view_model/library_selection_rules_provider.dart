// 文件: lib/src/features/notes/view_model/library_selection_rules_provider.dart
// 作用: 为位置选择会话加载完整文件夹和书章树，并构建纯范围规则。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/errors/result.dart';
import '../models/subject.dart';
import '../models/subject_folder.dart';
import '../providers.dart';
import '../utils/library_selection_rules.dart';

final librarySelectionRulesProvider =
    FutureProvider.autoDispose<LibrarySelectionRules>((ref) async {
      final foldersResult = await ref.read(folderRepositoryProvider).listAll();
      final subjectsResult = await ref
          .read(subjectRepositoryProvider)
          .listAll();

      List<T> value<T>(Result<List<T>> result) {
        if (result case Success<List<T>>(:final value)) return value;
        throw (result as Failure<List<T>>).exception;
      }

      return LibrarySelectionRules(
        folders: value<SubjectFolder>(foldersResult),
        subjects: value<Subject>(subjectsResult),
      );
    });
