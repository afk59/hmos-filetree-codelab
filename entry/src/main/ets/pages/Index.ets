import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  activatePersistedRoots,
  ALL_USER_DIR_PERMISSIONS,
  DefaultFileTreeDataSource,
  FileNode,
  FileTreeView,
  fullDiskRoot,
  canRequestFullDisk,
  hasFullDisk,
  isFolderSelectionSupported,
  openFullDiskSetting,
  PickedRoot,
  pickFolders,
  requestUserDirPermissions,
  UserDirPermissionResult
} from '@afk35/filetreeview';
import { runDataSourceProbe } from '../probe/DataSourceProbe';
import { PickedRootStore } from '../store/PickedRootStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'FileTreeDemo';

type AccessState = 'checking' | 'granted' | 'denied' | 'misconfigured';

@Entry
@Component
struct Index {
  private dataSource: DefaultFileTreeDataSource =
    new DefaultFileTreeDataSource({ showHidden: false, sort: 'name-asc' });
  private store?: PickedRootStore;
  private pickedUris: string[] = [];

  @State access: AccessState = 'checking';
  @State accessDetail: string = '';
  @State partialWarning: string = '';
  @State rootsVersion: number = 0;
  @State pickedCount: number = 0;
  @State fullDisk: boolean = false;
  @State picking: boolean = false;
  @State canPick: boolean = false;
  @State canOfferFullDisk: boolean = false;

  @State selectedName: string = 'No file selected';
  @State selectedPath: string = '';
  @State selectedSize: string = '';
  @State selectedMtime: string = '';
  @State lastError: string = '';

  aboutToAppear(): void {
    this.ensureAccess().catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'ensureAccess failed: %{public}s', e.message);
    });
  }

  private uiContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async ensureAccess(): Promise<void> {
    this.access = 'checking';
    this.canPick = isFolderSelectionSupported();
    this.canOfferFullDisk = canRequestFullDisk();
    const context: common.UIAbilityContext = this.uiContext();
    const result: UserDirPermissionResult =
      await requestUserDirPermissions(context, ALL_USER_DIR_PERMISSIONS);

    this.addFullDiskRootIfAvailable();
    await this.restorePickedRoots();

    if (result.granted.length > 0 || this.pickedCount > 0 || this.fullDisk) {
      this.access = 'granted';
      this.accessDetail = '';
      this.partialWarning = result.allGranted
        ? ''
        : `Not granted: ${FileTreeDemoUtil.shortNames(result.denied)}. Those folders will not open.`;
      runDataSourceProbe().catch((e: Error) => {
        hilog.error(DOMAIN, TAG, 'probe failed: %{public}s', e.message);
      });
      return;
    }

    this.accessDetail = result.denied.join('\n');
    this.access = result.needsConfigFix ? 'misconfigured' : 'denied';
    hilog.warn(DOMAIN, TAG, 'File access unavailable (%{public}s). Missing: %{public}s',
      this.access, this.accessDetail);
  }

  private async enableFullDisk(): Promise<void> {
    await openFullDiskSetting(this.uiContext());
    this.addFullDiskRootIfAvailable();
    this.canOfferFullDisk = canRequestFullDisk();
  }

  private addFullDiskRootIfAvailable(): void {
    this.fullDisk = hasFullDisk();
    if (!this.fullDisk) {
      return;
    }
    const root: FileNode | undefined = fullDiskRoot();
    if (root !== undefined) {
      this.dataSource.addRoot(root);
      this.rootsVersion++;
      hilog.info(DOMAIN, TAG, 'Full-disk root added at %{public}s', root.path);
    }
  }

  private async restorePickedRoots(): Promise<void> {
    const store: PickedRootStore = this.rootStore();
    const saved: string[] = await store.load();
    if (saved.length === 0) {
      return;
    }
    const restored: PickedRoot[] = await activatePersistedRoots(saved);
    for (const picked of restored) {
      this.dataSource.addRoot(picked.node);
    }
    this.pickedUris = restored.map((p: PickedRoot) => p.uri);
    this.pickedCount = this.pickedUris.length;
    this.rootsVersion++;
    if (this.pickedUris.length !== saved.length) {
      hilog.warn(DOMAIN, TAG, '%{public}d of %{public}d saved folders could not be restored.',
        saved.length - this.pickedUris.length, saved.length);
      await store.save(this.pickedUris);
    }
  }

  private async addFolder(): Promise<void> {
    if (this.picking) {
      return;
    }
    this.picking = true;
    try {
      const picked: PickedRoot[] = await pickFolders(this.uiContext());
      if (picked.length === 0) {
        return;
      }
      for (const root of picked) {
        this.dataSource.addRoot(root.node);
        if (!this.pickedUris.includes(root.uri)) {
          this.pickedUris.push(root.uri);
        }
      }
      this.pickedCount = this.pickedUris.length;
      await this.rootStore().save(this.pickedUris);
      this.rootsVersion++;
      if (this.access !== 'granted') {
        this.access = 'granted';
      }
      this.lastError = '';
    } finally {
      this.picking = false;
    }
  }

  private async forgetPickedRoots(): Promise<void> {
    for (const root of this.dataSource.listExtraRoots()) {
      if (root.uri !== undefined) {
        this.dataSource.removeRoot(root.path);
      }
    }
    this.pickedUris = [];
    this.pickedCount = 0;
    await this.rootStore().save(this.pickedUris);
    this.rootsVersion++;
  }

  private rootStore(): PickedRootStore {
    if (this.store === undefined) {
      this.store = new PickedRootStore(this.uiContext());
    }
    return this.store;
  }

  build() {
    Row() {
      Column() {
        Row() {
          Text('Files').fontSize(16).fontWeight(FontWeight.Bold).layoutWeight(1)
          if (this.fullDisk) {
            Text('full disk').fontSize(10).fontColor(Color.Green)
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 8 })

        if (this.partialWarning.length > 0) {
          Text(this.partialWarning)
            .fontSize(11)
            .fontColor(Color.Orange)
            .width('100%')
            .padding({ left: 12, right: 12, bottom: 8 })
        }

        Row({ space: 8 }) {
          if (this.canPick) {
            Button(this.picking ? 'Choosing…' : 'Add folder…')
              .fontSize(12)
              .enabled(!this.picking)
              .onClick(() => {
                this.addFolder().catch((e: Error) => {
                  this.lastError = e.message;
                });
              })
          } else {
            Text('Folder picking is unavailable on this device.')
              .fontSize(11)
              .fontColor(Color.Gray)
              .layoutWeight(1)
          }
          if (this.canOfferFullDisk) {
            Button('Full disk…')
              .fontSize(12)
              .onClick(() => {
                this.enableFullDisk().catch((e: Error) => {
                  this.lastError = e.message;
                });
              })
          }
          if (this.pickedCount > 0) {
            Button(`Forget ${this.pickedCount}`)
              .fontSize(12)
              .backgroundColor(Color.Gray)
              .onClick(() => {
                this.forgetPickedRoots().catch((e: Error) => {
                  this.lastError = e.message;
                });
              })
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 8 })

        if (this.access === 'granted') {
          FileTreeView({
            dataSource: this.dataSource,
            rootsVersion: this.rootsVersion,
            onFileSelected: (node: FileNode) => {
              this.selectedName = node.name;
              this.selectedPath = node.path;
              this.selectedSize = node.size === undefined ? '—' : `${node.size} bytes`;
              this.selectedMtime =
                node.mtime === undefined ? '—' : new Date(node.mtime).toLocaleString();
              this.lastError = '';
            },
            onDirExpanded: (node: FileNode) => {
              hilog.info(DOMAIN, TAG, 'expanded %{public}s', node.path);
            },
            onError: (err: Error) => {
              this.lastError = err.message;
            }
          })
        } else {
          this.AccessGate()
        }
      }
      .width(320)
      .height('100%')

      Divider().vertical(true).strokeWidth(1)

      Column({ space: 8 }) {
        Text(this.selectedName).fontSize(20).fontWeight(FontWeight.Bold)
        Text(this.selectedPath).fontSize(13).fontColor(Color.Gray)
        Text(`Size: ${this.selectedSize}`).fontSize(14)
        Text(`Modified: ${this.selectedMtime}`).fontSize(14)
        if (this.lastError.length > 0) {
          Text(this.lastError).fontSize(13).fontColor(Color.Red)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .height('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AccessGate() {
    Column({ space: 12 }) {
      if (this.access === 'checking') {
        Text('Requesting file access…').fontSize(14).fontColor(Color.Gray)
      } else if (this.access === 'misconfigured') {
        Text('File access cannot be requested.').fontSize(14).fontColor(Color.Red)
        Text('The permission is not declared, or the signing profile carries no ACL for it.')
          .fontSize(12)
          .fontColor(Color.Gray)
        Text(this.accessDetail).fontSize(11).fontColor(Color.Gray)
      } else {
        Text('File access was not granted.').fontSize(14)
        Text('Grant it here, or in Settings if the dialog no longer appears.')
          .fontSize(12)
          .fontColor(Color.Gray)
        Text(this.accessDetail).fontSize(11).fontColor(Color.Gray)
        Button('Grant access')
          .onClick(() => {
            this.ensureAccess().catch((e: Error) => {
              hilog.error(DOMAIN, TAG, 'ensureAccess failed: %{public}s', e.message);
            });
          })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .layoutWeight(1)
    .padding(12)
  }
}

class FileTreeDemoUtil {
  static shortNames(permissions: string[]): string {
    const names: string[] = permissions.map((p: string) => {
      const tail: string = p.substring(p.lastIndexOf('.') + 1);
      return tail.replace('READ_WRITE_', '').replace('_DIRECTORY', '');
    });
    return names.join(', ');
  }
}
