// 科目搜索路径模型：保存从书到匹配节点的完整层级。
import 'dart:collection';

import 'subject.dart';

/// 从顶层书到搜索命中节点的不可变路径。
class SubjectPath {
  final List<Subject> nodes;

  SubjectPath(Iterable<Subject> nodes)
    : nodes = UnmodifiableListView(List<Subject>.of(nodes)) {
    if (this.nodes.isEmpty) {
      throw ArgumentError.value(nodes, 'nodes', '路径不能为空');
    }
  }

  Subject get target => nodes.last;
}
