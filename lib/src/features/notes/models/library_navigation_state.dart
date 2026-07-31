// 文件: lib/src/features/notes/models/library_navigation_state.dart
// 作用: 保存笔记主页的浏览模式及跨子路由的位置选择会话。
import 'library_location.dart';
import '../utils/library_creation_scope.dart';

enum LibraryBrowseMode { drillDown, expanded }

enum LibrarySelectionKind { contentLocation, noteLocation }

class LibraryContentDraft {
  final LibraryContentKind kind;
  final String name;

  const LibraryContentDraft({required this.kind, required this.name});
}

class LibrarySelectionSession {
  final LibrarySelectionKind kind;
  final LibraryLocation origin;
  final LibraryBrowseMode previousBrowseMode;
  final LibraryContentDraft? contentDraft;

  const LibrarySelectionSession({
    required this.kind,
    required this.origin,
    required this.previousBrowseMode,
    this.contentDraft,
  });
}

class LibraryNavigationState {
  final LibraryBrowseMode browseMode;
  final LibrarySelectionSession? selection;

  const LibraryNavigationState({
    this.browseMode = LibraryBrowseMode.drillDown,
    this.selection,
  });
}
