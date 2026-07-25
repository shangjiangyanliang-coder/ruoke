// 文件: lib/src/data/database/seed/subject_seed.dart
// 作用: App 首启 seed 示例科目树（书-章-节），让 B1 树视图跑起来能看效果。
//       幂等：仅 subject 表完全为空才 seed（用 totalCount 判），已有数据绝不重复插。
//       示例：物理(含3章2-3节) + 英语(含2章少量节) + 一条整本书笔记挂载位。
//       以后清样例即可（删表或迁移），不影响真实数据。
//       详见技术方案 B §二 表1 + 阶段5第3批计划。
// 注：Value 来自 drift；SubjectsCompanion 是生成类，由 app_database.dart 的 part 暴露。
import 'package:drift/drift.dart' show Value;

import '../app_database.dart';
import '../daos/subject_dao.dart';
import '../../../utils/id_generator.dart';
import '../../../utils/time_utils.dart';

/// 首启科目 seed。表空才插，幂等。await 它完成。
class SubjectSeed {
  final SubjectDao _dao;
  SubjectSeed(this._dao);

  /// 仅当 subject 表为空时 seed 示例科目。返回是否执行了 seed。
  Future<bool> runIfEmpty() async {
    final total = await _dao.totalCount();
    if (total > 0) return false; // 已有数据，绝不重复 seed
    await _seed();
    return true;
  }

  Future<void> _seed() async {
    final now = nowMs();
    int order = 0;

    // 物理（书 level0）
    final physicsId = await _insert(name: '物理', level: 0, sortOrder: order++, now: now);

    // 第1章 运动学（level1）
    final ch1Id = await _insert(
        name: '第1章 运动学', level: 1, parentId: physicsId, sortOrder: order++, now: now);
    await _insert(name: '匀速直线运动', level: 2, parentId: ch1Id, sortOrder: 0, now: now);
    await _insert(name: '自由落体', level: 2, parentId: ch1Id, sortOrder: 1, now: now);

    // 第2章 力学（level1）
    final ch2Id = await _insert(
        name: '第2章 力学', level: 1, parentId: physicsId, sortOrder: order++, now: now);
    await _insert(name: '牛顿第一定律', level: 2, parentId: ch2Id, sortOrder: 0, now: now);
    await _insert(name: '牛顿第二定律', level: 2, parentId: ch2Id, sortOrder: 1, now: now);
    await _insert(name: '牛顿第三定律', level: 2, parentId: ch2Id, sortOrder: 2, now: now);

    // 第3章 牛顿定律（level1，先建空章 demo 折叠态）
    await _insert(
        name: '第3章 牛顿定律', level: 1, parentId: physicsId, sortOrder: order++, now: now);

    // 英语（书 level0）
    final englishId = await _insert(name: '英语', level: 0, sortOrder: order++, now: now);
    final ech1Id = await _insert(
        name: '第1章 词汇', level: 1, parentId: englishId, sortOrder: 0, now: now);
    await _insert(name: '高频词', level: 2, parentId: ech1Id, sortOrder: 0, now: now);
    final ech2Id = await _insert(
        name: '第2章 语法', level: 1, parentId: englishId, sortOrder: 1, now: now);
    await _insert(name: '时态', level: 2, parentId: ech2Id, sortOrder: 0, now: now);
    await _insert(name: '从句', level: 2, parentId: ech2Id, sortOrder: 1, now: now);
  }

  /// 插一条节点，返回新 id（子节点用它当 parentId）。
  Future<String> _insert({
    required String name,
    required int level,
    String? parentId,
    required int sortOrder,
    required int now,
  }) async {
    final id = newId();
    await _dao.insertSubject(
      SubjectsCompanion(
        id: Value(id),
        parentId: Value(parentId),
        name: Value(name),
        level: Value(level),
        sortOrder: Value(sortOrder),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return id;
  }
}
