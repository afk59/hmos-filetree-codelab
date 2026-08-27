import { Environment, fileIo, ListFileOptions } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileNode, FileTreeConfig, FileTreeSort } from '../model/FileNode';
import { FileTreeDataSource } from './FileTreeDataSource';

const DOMAIN: number = 0x0000;
const TAG: string = 'FileTreeView';

const SECONDS_TO_MILLIS: number = 1000;

const STAT_BATCH: number = 64;

const ERR_CAPABILITY_NOT_SUPPORTED: number = 801;

const ERR_OPERATION_NOT_PERMITTED: number = 13900001;

const ENVIRONMENT_SYSCAP: string = 'SystemCapability.FileManagement.File.Environment.FolderObtain';

export class DefaultFileTreeDataSource implements FileTreeDataSource {
  private config: FileTreeConfig;
  private extraRoots: FileNode[] = [];

  constructor(config?: FileTreeConfig) {
    this.config = config ?? {};
  }

  setConfig(config: FileTreeConfig): void {
    this.config = config;
  }

  addRoot(node: FileNode): void {
    for (const existing of this.extraRoots) {
      if (existing.path === node.path) {
        return;
      }
    }
    this.extraRoots.push(node);
  }

  removeRoot(path: string): boolean {
    const before: number = this.extraRoots.length;
    this.extraRoots = this.extraRoots.filter((n: FileNode) => n.path !== path);
    return this.extraRoots.length !== before;
  }

  listExtraRoots(): FileNode[] {
    return this.extraRoots.slice();
  }

  async getRoots(): Promise<FileNode[]> {
    const roots: FileNode[] = [];

    if (canIUse(ENVIRONMENT_SYSCAP)) {
      try {
        DefaultFileTreeDataSource.pushRoot(roots, 'Documents', Environment.getUserDocumentDir());
      } catch (e) {
        DefaultFileTreeDataSource.logRootFailure('Documents', e);
      }
      try {
        DefaultFileTreeDataSource.pushRoot(roots, 'Download', Environment.getUserDownloadDir());
      } catch (e) {
        DefaultFileTreeDataSource.logRootFailure('Download', e);
      }
      try {
        DefaultFileTreeDataSource.pushRoot(roots, 'Desktop', Environment.getUserDesktopDir());
      } catch (e) {
        DefaultFileTreeDataSource.logRootFailure('Desktop', e);
      }
    } else {
      hilog.warn(DOMAIN, TAG,
        'Environment capability absent; the pre-authorized user directories are unavailable.');
    }

    for (const extra of this.extraRoots) {
      roots.push(extra);
    }
    return roots;
  }

  private static pushRoot(roots: FileNode[], label: string, path: string): void {
    if (path.length === 0) {
      hilog.warn(DOMAIN, TAG, 'Root %{public}s resolved to an empty path; skipping.', label);
      return;
    }
    roots.push({ name: label, path: path, isDirectory: true, loaded: false });
  }

  private static logRootFailure(label: string, e: Object): void {
    const err = e as BusinessError;
    if (err.code === ERR_CAPABILITY_NOT_SUPPORTED) {
      hilog.warn(DOMAIN, TAG, 'Root %{public}s unavailable on this device (801).', label);
    } else {
      hilog.error(DOMAIN, TAG, 'Root %{public}s failed. Code: %{public}d, message: %{public}s',
        label, err.code, err.message);
    }
  }

  async listChildren(node: FileNode): Promise<FileNode[]> {
    if (!node.isDirectory) {
      return [];
    }

    const dirPath: string = node.path;
    const options: ListFileOptions = { recursion: false };

    let names: string[] = [];
    try {
      names = await fileIo.listFile(dirPath, options);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'listFile failed for %{public}s. Code: %{public}d, message: %{public}s',
        dirPath, err.code, err.message);
      if (err.code === ERR_OPERATION_NOT_PERMITTED) {
        throw new Error(
          `Cannot list "${node.name}": permission not granted (code ${err.code}). ` +
          'Request the user-directory permission first — see USER_DIR_PERMISSIONS.');
      }
      throw new Error(`Cannot list "${node.name}" (code ${err.code}): ${err.message}`);
    }

    const children: FileNode[] = [];
    for (let i: number = 0; i < names.length; i += STAT_BATCH) {
      const slice: string[] = names.slice(i, i + STAT_BATCH);
      const batch: FileNode[] = await Promise.all(
        slice.map((name: string) => this.statChild(dirPath, name))
      );
      for (const child of batch) {
        children.push(child);
      }
    }
    return this.applyConfig(children);
  }

  private async statChild(dirPath: string, name: string): Promise<FileNode> {
    const childPath: string = DefaultFileTreeDataSource.joinPath(dirPath, name);
    try {
      const stat: fileIo.Stat = await fileIo.stat(childPath);
      const isDirectory: boolean = stat.isDirectory();
      return DefaultFileTreeDataSource.toFileNode(name, childPath, stat, isDirectory);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'stat failed for %{public}s. Code: %{public}d, message: %{public}s',
        childPath, err.code, err.message);
      return {
        name: name,
        path: childPath,
        isDirectory: false,
        error: `code ${err.code}: ${err.message}`
      };
    }
  }

  private static toFileNode(
    name: string, path: string, stat: fileIo.Stat, isDirectory: boolean): FileNode {
    return {
      name: name,
      path: path,
      isDirectory: isDirectory,
      size: isDirectory ? undefined : stat.size,
      mtime: stat.mtime * SECONDS_TO_MILLIS,
      loaded: false
    };
  }

  private static joinPath(dirPath: string, name: string): string {
    return dirPath.endsWith('/') ? `${dirPath}${name}` : `${dirPath}/${name}`;
  }

  private static extensionOf(name: string): string {
    const dot: number = name.lastIndexOf('.');
    if (dot <= 0 || dot === name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  private applyConfig(nodes: FileNode[]): FileNode[] {
    const showHidden: boolean = this.config.showHidden ?? false;
    const whitelist: string[] = this.config.extWhitelist ?? [];
    const blacklist: string[] = this.config.extBlacklist ?? [];

    const kept: FileNode[] = nodes.filter((n: FileNode) => {
      if (!showHidden && n.name.startsWith('.')) {
        return false;
      }
      if (n.isDirectory) {
        return true;
      }
      if (n.error !== undefined) {
        return true;
      }
      const ext: string = DefaultFileTreeDataSource.extensionOf(n.name);
      if (blacklist.length > 0 && blacklist.some((b: string) => b.toLowerCase() === ext)) {
        return false;
      }
      if (whitelist.length > 0 && !whitelist.some((w: string) => w.toLowerCase() === ext)) {
        return false;
      }
      return true;
    });

    const sort: FileTreeSort = this.config.sort ?? 'name-asc';
    kept.sort((a: FileNode, b: FileNode) => DefaultFileTreeDataSource.compare(a, b, sort));
    return kept;
  }

  private static compare(a: FileNode, b: FileNode, sort: FileTreeSort): number {
    if (a.isDirectory !== b.isDirectory) {
      return a.isDirectory ? -1 : 1;
    }
    const byName: number = a.name.localeCompare(b.name);
    switch (sort) {
      case 'name-asc':
        return byName;
      case 'name-desc':
        return -byName;
      case 'size-asc':
      case 'size-desc': {
        if (a.isDirectory) {
          return byName;
        }
        const diff: number = (a.size ?? 0) - (b.size ?? 0);
        if (diff === 0) {
          return byName;
        }
        return sort === 'size-asc' ? diff : -diff;
      }
      case 'date-asc':
      case 'date-desc': {
        const diff: number = (a.mtime ?? 0) - (b.mtime ?? 0);
        if (diff === 0) {
          return byName;
        }
        return sort === 'date-asc' ? diff : -diff;
      }
      default:
        return byName;
    }
  }
}
