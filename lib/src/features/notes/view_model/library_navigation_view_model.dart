// 文件: lib/src/features/notes/view_model/library_navigation_view_model.dart
// 作用: 管理笔记主页浏览模式和位置选择会话，不直接读写数据库。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/library_location.dart';
import '../models/library_navigation_state.dart';

class LibraryNavigationVm extends AsyncNotifier<LibraryNavigationState> {
  @override
  FutureOr<LibraryNavigationState> build() => const LibraryNavigationState();

  void toggleBrowseMode() {
    final current = state.value;
    if (current == null || current.selection != null) return;
    state = AsyncData(
      LibraryNavigationState(
        browseMode: current.browseMode == LibraryBrowseMode.drillDown
            ? LibraryBrowseMode.expanded
            : LibraryBrowseMode.drillDown,
      ),
    );
  }

  void startContentSelection({
    required LibraryLocation origin,
    required LibraryContentDraft draft,
  }) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      LibraryNavigationState(
        browseMode: LibraryBrowseMode.drillDown,
        selection: LibrarySelectionSession(
          kind: LibrarySelectionKind.contentLocation,
          origin: origin,
          previousBrowseMode: current.browseMode,
          contentDraft: draft,
        ),
      ),
    );
  }

  void startNoteSelection({required LibraryLocation origin}) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      LibraryNavigationState(
        browseMode: LibraryBrowseMode.drillDown,
        selection: LibrarySelectionSession(
          kind: LibrarySelectionKind.noteLocation,
          origin: origin,
          previousBrowseMode: current.browseMode,
        ),
      ),
    );
  }

  void cancelSelection() {
    final current = state.value;
    final selection = current?.selection;
    if (current == null || selection == null) return;
    state = AsyncData(
      LibraryNavigationState(browseMode: selection.previousBrowseMode),
    );
  }

  void completeSelection() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(LibraryNavigationState(browseMode: current.browseMode));
  }
}
