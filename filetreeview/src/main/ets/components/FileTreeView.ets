import { KeyCode } from '@kit.InputKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileNode, FileTreeConfig } from '../model/FileNode';
import { FileTreeDataSource } from '../datasource/FileTreeDataSource';
import { DefaultFileTreeDataSource } from '../datasource/DefaultFileTreeDataSource';
import { formatSize } from '../util/Format';

const DOMAIN: number = 0x0000;
const TAG: string = 'FileTreeView';

const INDENT_PER_LEVEL: number = 16;
const TWISTY_SIZE: number = 16;
const ICON_SIZE: number = 20;
const ROW_HEIGHT: number = 40;
const EXPANDED_ANGLE: number = 90;
const COLLAPSED_ANGLE: number = 0;
const SELECTED_BG: string = '#1A0A59F7';
const HOVERED_BG: string = '#0D000000';
const TRANSPARENT_BG: string = '#00000000';
const NO_INDEX: number = -1;
const NO_ID: number = 0;

let nextRowId: number = 1;

class TreeRow {
  readonly id: number;
  readonly node: FileNode;
  readonly depth: number;
  expanded: boolean = false;
  loading: boolean = false;
  children?: TreeRow[];

  constructor(node: FileNode, depth: number) {
    this.id = nextRowId;
    nextRowId++;
    this.node = node;
    this.depth = depth;
  }
}

@Component
export struct FileTreeView {
  dataSource: FileTreeDataSource = new DefaultFileTreeDataSource();
  config?: FileTreeConfig;
  onFileSelected?: (node: FileNode) => void;
  onDirExpanded?: (node: FileNode) => void;
  onError?: (err: Error) => void;
  @Prop @Watch('onRootsVersionChanged') rootsVersion: number = 0;

  @State private rows: TreeRow[] = [];
  @State private selectedPath: string = '';
  @State private loadingRoots: boolean = true;
  @State private focusedIndex: number = NO_INDEX;
  @State private hoveredId: number = NO_ID;

  private roots: TreeRow[] = [];
  private listScroller: Scroller = new Scroller();

  onRootsVersionChanged(): void {
    this.loadRoots();
  }

  aboutToAppear(): void {
    if (this.config !== undefined) {
      if (this.dataSource instanceof DefaultFileTreeDataSource) {
        (this.dataSource as DefaultFileTreeDataSource).setConfig(this.config);
      } else {
        hilog.warn(DOMAIN, TAG,
          'config was supplied but dataSource is not a DefaultFileTreeDataSource; ignoring it.');
      }
    }
    this.loadRoots();
  }

  private async loadRoots(): Promise<void> {
    try {
      const roots: FileNode[] = await this.dataSource.getRoots();
      if (roots.length === 0) {
        hilog.warn(DOMAIN, TAG,
          'No roots. Either the Environment capability is missing, or nothing has been added.');
      }
      const byPath: Map<string, TreeRow> = new Map<string, TreeRow>();
      for (const existing of this.roots) {
        byPath.set(existing.node.path, existing);
      }
      this.roots = roots.map((node: FileNode) => {
        const kept: TreeRow | undefined = byPath.get(node.path);
        return kept !== undefined ? kept : new TreeRow(node, 0);
      });
      hilog.info(DOMAIN, TAG, 'Roots: %{public}d.', roots.length);
    } catch (e) {
      this.reportError(e, 'loading roots');
    } finally {
      this.loadingRoots = false;
      this.refresh();
    }
  }

  private refresh(): void {
    const visible: TreeRow[] = [];
    FileTreeView.flatten(this.roots, visible);
    this.rows = visible;
    if (this.focusedIndex !== NO_INDEX) {
      this.focusedIndex = visible.findIndex((row: TreeRow) => row.node.path === this.selectedPath);
    }
  }

  private static flatten(rows: TreeRow[], out: TreeRow[]): void {
    for (const row of rows) {
      out.push(row);
      if (row.expanded && row.children !== undefined) {
        FileTreeView.flatten(row.children, out);
      }
    }
  }

  private handleRowClick(row: TreeRow, index: number): void {
    this.selectedPath = row.node.path;
    this.focusedIndex = index;
    if (!row.node.isDirectory) {
      this.refresh();
      this.emitFileSelected(row.node);
      return;
    }
    if (row.expanded) {
      row.expanded = false;
      this.refresh();
      return;
    }
    row.expanded = true;
    if (row.children !== undefined) {
      this.refresh();
      this.emitDirExpanded(row.node);
      return;
    }
    this.loadChildren(row);
  }

  private async loadChildren(row: TreeRow): Promise<void> {
    if (row.loading) {
      return;
    }
    row.loading = true;
    this.refresh();
    let expanded: boolean = false;
    try {
      const children: FileNode[] = await this.dataSource.listChildren(row.node);
      row.children = children.map((child: FileNode) => new TreeRow(child, row.depth + 1));
      row.node.loaded = true;
      hilog.info(DOMAIN, TAG, 'Listed %{public}s: %{public}d children.', row.node.name, children.length);
      expanded = true;
    } catch (e) {
      row.expanded = false;
      this.reportError(e, `expanding "${row.node.name}"`);
    } finally {
      row.loading = false;
      this.refresh();
    }
    if (expanded) {
      this.emitDirExpanded(row.node);
    }
  }

  private static trailingOf(row: TreeRow): string {
    if (row.loading) {
      return '…';
    }
    if (row.node.error !== undefined) {
      return row.node.error;
    }
    if (!row.node.isDirectory && row.node.size !== undefined) {
      return formatSize(row.node.size);
    }
    if (row.node.isDirectory && row.children !== undefined && row.children.length === 0) {
      return 'empty';
    }
    return '';
  }

  private static rowBackground(selected: boolean, hovered: boolean): string {
    if (selected) {
      return SELECTED_BG;
    }
    return hovered ? HOVERED_BG : TRANSPARENT_BG;
  }

  private static keyOf(row: TreeRow): string {
    const loaded: string = row.children === undefined ? 'u' : `${row.children.length}`;
    return `${row.id}|${row.expanded}|${row.loading}|${loaded}`;
  }

  private handleKey(event: KeyEvent): void {
    if (event.type !== KeyType.Down) {
      return;
    }
    const code: number = event.keyCode;
    if (code === KeyCode.KEYCODE_DPAD_DOWN) {
      this.moveFocus(1);
    } else if (code === KeyCode.KEYCODE_DPAD_UP) {
      this.moveFocus(-1);
    } else if (code === KeyCode.KEYCODE_DPAD_RIGHT) {
      this.openFocused();
    } else if (code === KeyCode.KEYCODE_DPAD_LEFT) {
      this.closeFocused();
    } else if (code === KeyCode.KEYCODE_ENTER || code === KeyCode.KEYCODE_NUMPAD_ENTER ||
      code === KeyCode.KEYCODE_SPACE) {
      const row: TreeRow | undefined = this.focusedRow();
      if (row !== undefined) {
        this.handleRowClick(row, this.focusedIndex);
      }
    }
  }

  private focusedRow(): TreeRow | undefined {
    if (this.focusedIndex < 0 || this.focusedIndex >= this.rows.length) {
      return undefined;
    }
    return this.rows[this.focusedIndex];
  }

  private moveFocus(delta: number): void {
    if (this.rows.length === 0) {
      return;
    }
    const from: number = this.focusedIndex < 0 ? (delta > 0 ? -1 : 0) : this.focusedIndex;
    let next: number = from + delta;
    if (next < 0) {
      next = 0;
    }
    if (next > this.rows.length - 1) {
      next = this.rows.length - 1;
    }
    this.setFocus(next);
  }

  private setFocus(index: number): void {
    this.focusedIndex = index;
    const row: TreeRow | undefined = this.focusedRow();
    if (row === undefined) {
      return;
    }
    this.selectedPath = row.node.path;
    this.listScroller.scrollToIndex(index);
    if (!row.node.isDirectory) {
      this.emitFileSelected(row.node);
    }
  }

  private openFocused(): void {
    const row: TreeRow | undefined = this.focusedRow();
    if (row === undefined || !row.node.isDirectory) {
      return;
    }
    if (!row.expanded) {
      this.handleRowClick(row, this.focusedIndex);
      return;
    }
    if (row.children !== undefined && row.children.length > 0) {
      this.moveFocus(1);
    }
  }

  private closeFocused(): void {
    const row: TreeRow | undefined = this.focusedRow();
    if (row === undefined) {
      return;
    }
    if (row.node.isDirectory && row.expanded) {
      row.expanded = false;
      this.refresh();
      return;
    }
    for (let i: number = this.focusedIndex - 1; i >= 0; i--) {
      if (this.rows[i].depth < row.depth) {
        this.setFocus(i);
        return;
      }
    }
  }

  private reportError(e: Object, whileDoing: string): void {
    const err: Error = e instanceof Error ? e as Error : new Error(`${e}`);
    hilog.error(DOMAIN, TAG, 'Failed while %{public}s: %{public}s', whileDoing, err.message);
    this.emit('onError', () => {
      if (this.onError !== undefined) {
        this.onError(err);
      }
    });
  }

  private emitFileSelected(node: FileNode): void {
    this.emit('onFileSelected', () => {
      if (this.onFileSelected !== undefined) {
        this.onFileSelected(node);
      }
    });
  }

  private emitDirExpanded(node: FileNode): void {
    this.emit('onDirExpanded', () => {
      if (this.onDirExpanded !== undefined) {
        this.onDirExpanded(node);
      }
    });
  }

  private emit(name: string, call: () => void): void {
    try {
      call();
    } catch (e) {
      const err: Error = e instanceof Error ? e as Error : new Error(`${e}`);
      hilog.error(DOMAIN, TAG, 'Host %{public}s callback threw: %{public}s', name, err.message);
    }
  }

  build() {
    Column() {
      if (this.loadingRoots) {
        Text('Loading…').fontSize(13).fontColor(Color.Gray).padding(12)
      } else if (this.rows.length === 0) {
        Text('No folders available.').fontSize(13).fontColor(Color.Gray).padding(12)
      } else {
        List({ scroller: this.listScroller }) {
          ForEach(this.rows, (row: TreeRow, index: number) => {
            ListItem() {
              this.NodeRow(row, index)
            }
          }, (row: TreeRow) => FileTreeView.keyOf(row))
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .focusable(true)
        .defaultFocus(true)
        .onKeyEvent((event: KeyEvent) => {
          this.handleKey(event);
        })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  NodeRow(row: TreeRow, index: number) {
    Row({ space: 6 }) {
      if (row.node.isDirectory) {
        Image($r('sys.media.ohos_ic_public_arrow_right'))
          .width(TWISTY_SIZE)
          .height(TWISTY_SIZE)
          .opacity(row.loading ? 0.3 : 0.6)
          .rotate({ angle: row.expanded ? EXPANDED_ANGLE : COLLAPSED_ANGLE })
      } else {
        Row().width(TWISTY_SIZE).height(TWISTY_SIZE)
      }

      Image(row.node.isDirectory
        ? $r('sys.media.ohos_ic_normal_white_grid_folder')
        : $r('sys.media.ohos_ic_normal_white_grid_doc'))
        .width(ICON_SIZE)
        .height(ICON_SIZE)

      Text(row.node.name)
        .fontSize(14)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Text(FileTreeView.trailingOf(row))
        .fontSize(11)
        .fontColor(Color.Gray)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '45%' })
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: 8 + row.depth * INDENT_PER_LEVEL, right: 8 })
    .borderRadius(8)
    .backgroundColor(FileTreeView.rowBackground(
      this.selectedPath === row.node.path, this.hoveredId === row.id))
    .onHover((isHover: boolean) => {
      if (isHover) {
        this.hoveredId = row.id;
      } else if (this.hoveredId === row.id) {
        this.hoveredId = NO_ID;
      }
    })
    .onClick(() => {
      this.handleRowClick(row, index);
    })
  }
}
