/// 搜索文字的匹配方式。
enum SearchMatchMode {
  /// 字段包含关键词。
  contains,

  /// 字段去除首尾空白后与关键词完全相等。
  exact,
}
