// 文件: lib/src/features/notes/models/library_location.dart
// 作用: 统一描述文件夹系统中的逐级浏览、管理和选择位置。

/// 文件夹系统中的位置；文件夹不是笔记的直接归属目标。
sealed class LibraryLocation {
  const LibraryLocation();

  const factory LibraryLocation.root() = LibraryRootLocation;
  const factory LibraryLocation.folder(String folderId) = LibraryFolderLocation;
  const factory LibraryLocation.ungroupedBooks() = LibraryUngroupedBooksLocation;
  const factory LibraryLocation.subject(String subjectId) = LibrarySubjectLocation;
}

/// 文件夹系统根目录。
final class LibraryRootLocation extends LibraryLocation {
  const LibraryRootLocation();
}

/// 指定文件夹位置。
final class LibraryFolderLocation extends LibraryLocation {
  final String folderId;
  const LibraryFolderLocation(this.folderId);
}

/// 仅显示未放入文件夹的书及其浏览入口。
final class LibraryUngroupedBooksLocation extends LibraryLocation {
  const LibraryUngroupedBooksLocation();
}

/// 书、章或节位置。
final class LibrarySubjectLocation extends LibraryLocation {
  final String subjectId;
  const LibrarySubjectLocation(this.subjectId);
}
