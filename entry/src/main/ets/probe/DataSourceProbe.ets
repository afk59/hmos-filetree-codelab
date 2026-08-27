import { hilog } from '@kit.PerformanceAnalysisKit';
import { DefaultFileTreeDataSource, FileNode } from 'filetreeview';

const DOMAIN: number = 0x0000;
const TAG: string = 'FileTreeProbe';

export async function runDataSourceProbe(): Promise<void> {
  const ds = new DefaultFileTreeDataSource({ showHidden: false, sort: 'name-asc' });

  const roots: FileNode[] = await ds.getRoots();
  hilog.info(DOMAIN, TAG, '--- roots: %{public}d ---', roots.length);
  if (roots.length === 0) {
    hilog.warn(DOMAIN, TAG, 'No roots. On a non-2-in-1 device this is correct (error 801).');
    return;
  }
  for (const root of roots) {
    hilog.info(DOMAIN, TAG, 'root name=%{public}s path=%{public}s', root.name, root.path);
  }

  const first: FileNode = roots[0];
  try {
    const children: FileNode[] = await ds.listChildren(first);
    hilog.info(DOMAIN, TAG, '--- children of %{public}s: %{public}d ---', first.name, children.length);
    for (const child of children) {
      hilog.info(DOMAIN, TAG,
        '%{public}s name=%{public}s size=%{public}s mtime=%{public}s%{public}s',
        child.isDirectory ? '[DIR ]' : '[FILE]',
        child.name,
        child.size === undefined ? '-' : `${child.size}`,
        child.mtime === undefined ? '-' : new Date(child.mtime).toISOString(),
        child.error === undefined ? '' : ` ERROR(${child.error})`);
    }
  } catch (e) {
    const err = e as Error;
    hilog.error(DOMAIN, TAG, 'listChildren failed: %{public}s', err.message);
  }
}
