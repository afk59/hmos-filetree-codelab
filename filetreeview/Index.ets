export { FileNode, FileTreeConfig, FileTreeSort } from './src/main/ets/model/FileNode';

export { FileTreeDataSource } from './src/main/ets/datasource/FileTreeDataSource';
export { DefaultFileTreeDataSource } from './src/main/ets/datasource/DefaultFileTreeDataSource';

export { FileTreeView } from './src/main/ets/components/FileTreeView';

export {
  USER_DIR_PERMISSIONS,
  ALL_USER_DIR_PERMISSIONS,
  DESKTOP_DIR_PERMISSION,
  UserDirPermissionResult,
  checkUserDirPermissions,
  requestUserDirPermissions
} from './src/main/ets/permission/UserDirPermissions';

export {
  FULL_DISK_PERMISSION,
  PickedRoot,
  isFolderAuthorizationSupported,
  isFolderSelectionSupported,
  hasFullDisk,
  canRequestFullDisk,
  openFullDiskSetting,
  fullDiskRoot,
  pickFolders,
  activatePersistedRoots
} from './src/main/ets/access/StorageAccess';
