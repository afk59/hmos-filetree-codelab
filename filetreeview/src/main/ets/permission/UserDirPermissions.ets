import { abilityAccessCtrl, common, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'FileTreeView';

export const USER_DIR_PERMISSIONS: Permissions[] = [
  'ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY',
  'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY'
];

export const ALL_USER_DIR_PERMISSIONS: Permissions[] = [
  'ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY',
  'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY',
  'ohos.permission.READ_WRITE_DESKTOP_DIRECTORY'
];

export const DESKTOP_DIR_PERMISSION: Permissions = 'ohos.permission.READ_WRITE_DESKTOP_DIRECTORY';

export interface UserDirPermissionResult {
  granted: Permissions[];
  denied: Permissions[];
  allGranted: boolean;
  unusable: Permissions[];
  needsConfigFix: boolean;
}

const AUTH_RESULT_GRANTED: number = 0;

export function checkUserDirPermissions(
  permissions: Permissions[] = USER_DIR_PERMISSIONS): UserDirPermissionResult {
  const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
  const granted: Permissions[] = [];
  const denied: Permissions[] = [];
  const unusable: Permissions[] = [];

  for (const permission of permissions) {
    try {
      const status: abilityAccessCtrl.PermissionStatus = atManager.getSelfPermissionStatus(permission);
      if (status === abilityAccessCtrl.PermissionStatus.GRANTED) {
        granted.push(permission);
      } else {
        denied.push(permission);
        if (status === abilityAccessCtrl.PermissionStatus.INVALID ||
          status === abilityAccessCtrl.PermissionStatus.RESTRICTED) {
          unusable.push(permission);
          hilog.error(DOMAIN, TAG,
            'Permission %{public}s is unusable (status %{public}d). Check requestPermissions in ' +
            'module.json5, and the profile ACL for system_basic permissions.',
            permission, status);
        }
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG,
        'getSelfPermissionStatus failed for %{public}s. Code: %{public}d, message: %{public}s',
        permission, err.code, err.message);
      denied.push(permission);
    }
  }
  return {
    granted: granted,
    denied: denied,
    allGranted: denied.length === 0,
    unusable: unusable,
    needsConfigFix: unusable.length > 0
  };
}

export async function requestUserDirPermissions(
  context: common.UIAbilityContext,
  permissions: Permissions[] = USER_DIR_PERMISSIONS): Promise<UserDirPermissionResult> {
  const current: UserDirPermissionResult = checkUserDirPermissions(permissions);
  const askable: Permissions[] =
    current.denied.filter((p: Permissions) => !current.unusable.includes(p));
  if (askable.length === 0) {
    return current;
  }

  const granted: Permissions[] = current.granted.slice();
  const denied: Permissions[] = current.unusable.slice();
  const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();

  try {
    const data: PermissionRequestResult =
      await atManager.requestPermissionsFromUser(context, askable);
    for (let i: number = 0; i < data.permissions.length; i++) {
      const permission: Permissions = data.permissions[i] as Permissions;
      if (data.authResults[i] === AUTH_RESULT_GRANTED) {
        granted.push(permission);
      } else {
        denied.push(permission);
        hilog.warn(DOMAIN, TAG, 'Permission %{public}s not granted (authResult %{public}d).',
          permission, data.authResults[i]);
      }
    }
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(DOMAIN, TAG,
      'requestPermissionsFromUser failed. Code: %{public}d, message: %{public}s', err.code, err.message);
    for (const permission of askable) {
      denied.push(permission);
    }
  }

  return {
    granted: granted,
    denied: denied,
    allGranted: denied.length === 0,
    unusable: current.unusable,
    needsConfigFix: current.needsConfigFix
  };
}
