import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruoke/src/features/notes/models/library_location.dart';
import 'package:ruoke/src/features/notes/models/library_navigation_state.dart';
import 'package:ruoke/src/features/notes/view_model/view_model_providers.dart';

void main() {
  test('浏览模式切换后由共享会话保存', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(libraryNavigationVmProvider.future);

    container.read(libraryNavigationVmProvider.notifier).toggleBrowseMode();

    expect(
      container.read(libraryNavigationVmProvider).value!.browseMode,
      LibraryBrowseMode.expanded,
    );
  });

  test('取消笔记位置选择会恢复启动前浏览模式和清空会话', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(libraryNavigationVmProvider.future);
    final vm = container.read(libraryNavigationVmProvider.notifier);
    vm.toggleBrowseMode();
    vm.startNoteSelection(origin: const LibraryLocation.folder('folder-a'));

    expect(
      container.read(libraryNavigationVmProvider).value!.selection!.origin,
      isA<LibraryFolderLocation>(),
    );
    expect(
      container.read(libraryNavigationVmProvider).value!.browseMode,
      LibraryBrowseMode.drillDown,
    );

    vm.cancelSelection();

    expect(
      container.read(libraryNavigationVmProvider).value!.selection,
      isNull,
    );
    expect(
      container.read(libraryNavigationVmProvider).value!.browseMode,
      LibraryBrowseMode.expanded,
    );
  });
}
