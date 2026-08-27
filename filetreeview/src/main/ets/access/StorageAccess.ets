import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { Environment, fileShare, fileUri, picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileNode } from '../model/FileNode';

const DOMAIN: number = 0x0000;
const TAG: string = 'FileTreeView';

const READ_ONLY_MODE: number = fileShare.OperationMode.READ_MODE;

const FOLDER_AUTH_SYSCAP: string = 'SystemCapability.FileManagement.AppFileService.FolderAuthorization';
const FOLDER_SELECT_SYSCAP: string = 'SystemCapability.FileManagement.UserFileService.FolderSelection';
const ENVIRONMENT_SYSCAP: string = 'SystemCapability.FileManagement.File.Environment.FolderObtain';

export const FULL_DISK_PERMISSION: Permissions = 'ohos.permission.ACCESS_USER_FULL_DISK';

export interface PickedRoot {
  uri: string;
  node: FileNode;
}

export function isFolderAuthorizationSupported(): boolean {
  return canIUse(FOLDER_AUTH_SYSCAP);
}

export function isFolderSelectionSupported(): boolean {
  return canIUse(FOLDER_SELECT_SYSCAP);
}

export function hasFullDisk(): boolean {
  try {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    return atManager.getSelfPermissionStatus(FULL_DISK_PERMISSION) ===
      abilityAccessCtrl.PermissionStatus.GRANTED;
  } catch (e) {
    const err = e as BusinessError;
    hilog.warn(DOMAIN, TAG, 'Full-disk status unavailable. Code: %{public}d, message: %{public}s',
      err.code, err.message);
    return false;
  }
}

export async function openFullDiskSetting(context: common.UIAbilityContext): Promise<boolean> {
  try {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const result: abilityAccessCtrl.SelectedResult =
      await atManager.openPermissionOnSetting(context, FULL_DISK_PERMISSION);
    return result === abilityAccessCtrl.SelectedResult.GRANTED ||
      result === abilityAccessCtrl.SelectedResult.OPENED;
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(DOMAIN, TAG,
      'openPermissionOnSetting failed. Code: %{public}d, message: %{public}s. 12100001 = not ' +
      'declared in module.json5; 12100014 = not a manual_settings permission.',
      err.code, err.message);
    return false;
  }
}

export function canRequestFullDisk(): boolean {
  try {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const status: abilityAccessCtrl.PermissionStatus =
      atManager.getSelfPermissionStatus(FULL_DISK_PERMISSION);
    return status !== abilityAccessCtrl.PermissionStatus.GRANTED &&
      status !== abilityAccessCtrl.PermissionStatus.INVALID;
  } catch (e) {
    return false;
  }
}

export function fullDiskRoot(label: string = 'All files'): FileNode | undefined {
  let documents: string = '';
  if (canIUse(ENVIRONMENT_SYSCAP)) {
    try {
      documents = Environment.getUserDocumentDir();
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'Cannot derive the full-disk root. Code: %{public}d', err.code);
    }
  }
  const cut: number = documents.lastIndexOf('/');
  if (cut <= 0) {
    return undefined;
  }
  return { name: label, path: documents.substring(0, cut), isDirectory: true };
}

export async function pickFolders(context: common.UIAbilityContext): Promise<PickedRoot[]> {
  let options: picker.DocumentSelectOptions | undefined = undefined;
  if (canIUse(FOLDER_SELECT_SYSCAP)) {
    options = { selectMode: picker.DocumentSelectMode.FOLDER };
  }
  if (options === undefined) {
    hilog.warn(DOMAIN, TAG,
      'Folder selection is unsupported on this device (no ...UserFileService.FolderSelection); ' +
      'a root cannot be added by picking.');
    return [];
  }

  let uris: string[] = [];
  try {
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    uris = await documentPicker.select(options);
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(DOMAIN, TAG, 'Folder picker failed. Code: %{public}d, message: %{public}s',
      err.code, err.message);
    return [];
  }
  if (uris.length === 0) {
    hilog.info(DOMAIN, TAG, 'Folder picker cancelled.');
    return [];
  }

  const persisted: string[] = await persistUris(uris);
  return persisted.map((uri: string) => toPickedRoot(uri));
}

export async function activatePersistedRoots(uris: string[]): Promise<PickedRoot[]> {
  if (uris.length === 0) {
    return [];
  }
  if (!isFolderAuthorizationSupported()) {
    hilog.warn(DOMAIN, TAG, 'Folder authorization unsupported here; persisted roots unavailable.');
    return [];
  }

  const policies: fileShare.PolicyInfo[] = uris.map((uri: string) => {
    const policy: fileShare.PolicyInfo = { uri: uri, operationMode: READ_ONLY_MODE };
    return policy;
  });

  const failed: Set<string> = new Set<string>();
  try {
    await fileShare.activatePermission(policies);
  } catch (e) {
    collectPolicyFailures(e, 'activatePermission', failed);
  }
  return uris.filter((uri: string) => !failed.has(uri)).map((uri: string) => toPickedRoot(uri));
}

async function persistUris(uris: string[]): Promise<string[]> {
  if (!isFolderAuthorizationSupported()) {
    hilog.warn(DOMAIN, TAG,
      'Folder authorization unsupported here; the grant will not survive a restart.');
    return uris;
  }

  const policies: fileShare.PolicyInfo[] = uris.map((uri: string) => {
    const policy: fileShare.PolicyInfo = { uri: uri, operationMode: READ_ONLY_MODE };
    return policy;
  });

  const failed: Set<string> = new Set<string>();
  try {
    await fileShare.persistPermission(policies);
  } catch (e) {
    collectPolicyFailures(e, 'persistPermission', failed);
  }
  for (const uri of failed) {
    hilog.warn(DOMAIN, TAG, 'Grant for %{public}s is session-only; it was not persisted.', uri);
  }
  return uris;
}

function collectPolicyFailures(e: Object, api: string, failed: Set<string>): void {
  const err = e as BusinessError<fileShare.PolicyErrorResult[]>;
  hilog.error(DOMAIN, TAG, '%{public}s failed. Code: %{public}d, message: %{public}s',
    api, err.code, err.message);
  const results: fileShare.PolicyErrorResult[] | undefined = err.data;
  if (results === undefined) {
    return;
  }
  for (const result of results) {
    hilog.error(DOMAIN, TAG, '  %{public}s: policy code %{public}d, %{public}s',
      result.uri, result.code, result.message);
    failed.add(result.uri);
  }
}

function toPickedRoot(uri: string): PickedRoot {
  const parsed: fileUri.FileUri = new fileUri.FileUri(uri);
  const node: FileNode = {
    name: parsed.name,
    path: parsed.path,
    isDirectory: true,
    uri: uri
  };
  return { uri: uri, node: node };
}
