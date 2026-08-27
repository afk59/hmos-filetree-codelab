# Changelog

All notable changes to this package are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.0.0

Initial release.

### Added

- `FileTreeView` - a lazy-loading tree panel over the device file system. Directories carry an
  expander from the moment they appear; a directory's contents are read the first time it is
  opened, never at startup, never recursively, and never twice.
- `FileTreeDataSource` - a two-call, single-level source interface, so the tree can be backed by
  something other than the local file system.
- `DefaultFileTreeDataSource` - the device file system, with `addRoot` / `removeRoot` /
  `listExtraRoots` for roots beyond the pre-authorized user directories.
- `FileTreeConfig` - hidden-file, extension filtering and ordering options. Directories are never
  removed by an extension rule, and always sort before files.
- Keyboard navigation: arrow keys move, open and close; Enter and Space activate.
- User-directory permission helpers: `checkUserDirPermissions`, `requestUserDirPermissions`,
  `USER_DIR_PERMISSIONS`, `ALL_USER_DIR_PERMISSIONS`, `DESKTOP_DIR_PERMISSION`. A permission that
  no dialog can fix is reported separately from one the user merely declined.
- User-granted folders: `pickFolders`, `activatePersistedRoots`, `PickedRoot`. Grants are
  persisted through `fileShare` and survive a restart.
- Full-disk access helpers for PC/2-in-1: `hasFullDisk`, `canRequestFullDisk`,
  `openFullDiskSetting`, `fullDiskRoot`, `FULL_DISK_PERMISSION`.
- Device capability checks: `isFolderSelectionSupported`, `isFolderAuthorizationSupported`.
