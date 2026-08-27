# @afk35/filetreeview

A lazy-loading, file-system-backed tree panel for **HarmonyOS NEXT**.

It renders the device's real file system as an expandable tree: directories carry an expander
arrow from the moment they appear, and a directory's contents are read the first time it is
opened — never at startup, never recursively, and never twice.

The primary target is the **PC / 2-in-1** form factor, where a persistent file panel next to a
detail pane is the natural layout. It runs on tablets too, with the capability difference noted
under [Device capabilities](#device-capabilities).

## Install

```bash
ohpm i @afk35/filetreeview
```

## Quick start

At its simplest the component needs no arguments — it defaults to the device file system:

```ets
import { FileTreeView, FileNode } from '@afk35/filetreeview';

@Entry
@Component
struct Example {
  @State selected: string = '';

  build() {
    FileTreeView({
      onFileSelected: (node: FileNode) => { this.selected = node.path; }
    })
  }
}
```

With filtering, ordering and the full callback set:

```ets
FileTreeView({
  dataSource: new DefaultFileTreeDataSource({
    showHidden: false,
    sort: 'name-asc',
    extWhitelist: ['png', 'jpg', 'pdf']   // files only; directories are never filtered out
  }),
  rootsVersion: this.rootsVersion,        // bump to make the tree re-read its roots
  onFileSelected: (node: FileNode) => { /* ... */ },
  onDirExpanded: (node: FileNode) => { /* ... */ },
  onError: (err: Error) => { /* a listing failed; the tree stays usable */ }
})
```

## Permissions — read this first

**The consuming application must declare these permissions itself.** A HAR's `requestPermissions`
is not merged into the host, so nothing here can declare them on your behalf. Without them the
tree renders and every directory fails to open with `13900001`.

Add to your HAP's `module.json5`:

```json5
"requestPermissions": [
  {
    "name": "ohos.permission.FILE_ACCESS_PERSIST",
    "reason": "$string:reason_persist_access",
    "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
  },
  {
    "name": "ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY",
    "reason": "$string:reason_documents_dir",
    "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
  },
  {
    "name": "ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY",
    "reason": "$string:reason_download_dir",
    "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
  },
  {
    "name": "ohos.permission.READ_WRITE_DESKTOP_DIRECTORY",
    "reason": "$string:reason_desktop_dir",
    "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
  }
]
```

Two things about them are worth knowing before you spend time on either:

**"Pre-authorized" describes the path, not the read.** `Environment.getUserDocumentDir()` and its
siblings return a path with no permission at all. Listing that path is a separate matter:
`fileIo.listFile()` fails with `13900001 Operation not permitted` until the matching `user_grant`
permission is both declared and granted. The message says nothing about permissions.

**`READ_WRITE_DESKTOP_DIRECTORY` is `system_basic`, i.e. restricted.** It must appear in the
signing profile's `allowed-acls` or the *install* is rejected outright —
`code:9568289 install failed due to grant request permissions failed`. Declare it in
`module.json5` **first**, then re-generate the signature; DevEco requests it from AGC at signing
time and the approval is immediate. The other three are `normal` level and need nothing beyond
the declaration. If you do not want the ACL step, drop Desktop and use `USER_DIR_PERMISSIONS`
instead of `ALL_USER_DIR_PERMISSIONS`.

Request them at startup, and treat a partial grant as access rather than failure:

```ets
import { requestUserDirPermissions, ALL_USER_DIR_PERMISSIONS,
         UserDirPermissionResult } from '@afk35/filetreeview';

const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
const result: UserDirPermissionResult =
  await requestUserDirPermissions(context, ALL_USER_DIR_PERMISSIONS);

if (result.needsConfigFix) {
  // Something in result.unusable is undeclared, or restricted with no ACL.
  // No dialog can fix it - this is a build-configuration problem, not a user decision.
}
```

Mount `FileTreeView` only once access exists. It reads its roots in `aboutToAppear`, so a tree
constructed before the grant lists nothing and the only way back is a restart.

## Widening access beyond the three user directories

Access is **not** limited to Documents, Download and Desktop. Any folder the user selects through
the system picker becomes a browsable root, the grant persists across restarts, and grants
accumulate — at the cost of `FILE_ACCESS_PERSIST`, which is `normal` level and `system_grant`:
declaring it is the whole of the work. No ACL, no review, no runtime dialog. The user's selection
is the grant.

```ets
import { pickFolders, activatePersistedRoots, isFolderSelectionSupported,
         PickedRoot } from '@afk35/filetreeview';

// Offer the action only where it can work.
if (isFolderSelectionSupported()) {
  const picked: PickedRoot[] = await pickFolders(context);
  for (const root of picked) {
    this.dataSource.addRoot(root.node);
  }
  this.rootsVersion++;                         // makes a mounted tree re-read its roots
  await yourStore.save(picked.map((p: PickedRoot) => p.uri));
}

// On the next launch, hand the stored URIs back.
const restored: PickedRoot[] = await activatePersistedRoots(await yourStore.load());
```

**This package never persists anything.** `pickFolders()` hands back URIs and
`activatePersistedRoots()` takes them again; where they live in between is yours to decide — a
library that quietly creates a preferences file inside its host's data directory is a surprise.
Persist the **URI**, not the path: only a URI can be re-activated.

A URI that no longer activates — the folder was deleted, or the grant was revoked in Settings —
is dropped from the result rather than failing the batch. Treat "absent" as "stop storing this".

Reloading roots **reuses the row of any root whose path is unchanged**, so directories the user
has open stay open when a root is added or removed.

## Device capabilities

Three separate system capabilities sit behind what reads in the documentation like one picker
API, and the device manifest is the only place that says which of them a device has:

| Capability | Gates |
|---|---|
| `...File.Environment.FolderObtain` | the `Environment` user-directory getters |
| `...UserFileService.FolderSelection` | `DocumentSelectMode.FOLDER` — picking a **folder** |
| `...AppFileService.FolderAuthorization` | `persistPermission` / `activatePermission` |

`UserFileService.FolderSelection` varies the most. On a tablet at API 24 it is **absent** while
plain `UserFileService` is present: files can be picked there, folders cannot. Since a *file*
grant does not make its parent directory listable, there is no fallback — on such a device the
tree's reach really is the pre-authorized directories. On a 2-in-1 PC it is present and folder
picking works.

Call `isFolderSelectionSupported()` before offering the affordance. A button that can only ever
fail is worse than no button.

## Full-disk access (optional, PC/2-in-1 only)

`ohos.permission.ACCESS_USER_FULL_DISK` is supported but nothing here depends on it. It is
`system_basic` and therefore restricted, its authorization mode is `manual_settings` so there is
no runtime dialog at all, and it is PC/2-in-1 only — on a tablet its status is `INVALID`.

```ets
import { canRequestFullDisk, openFullDiskSetting, hasFullDisk,
         fullDiskRoot } from '@afk35/filetreeview';

if (canRequestFullDisk()) {                    // declared, and not already granted
  await openFullDiskSetting(context);          // the only route - no dialog can grant it
}
if (hasFullDisk()) {
  const root = fullDiskRoot();                 // parent of the user directories
  if (root !== undefined) { this.dataSource.addRoot(root); }
}
```

Declaring it without the ACL makes the application fail to install entirely, so add it only when
you are ready to re-sign and check.

## API

### `FileTreeView`

| Property | Type | Purpose |
|---|---|---|
| `dataSource` | `FileTreeDataSource` | Where nodes come from. Defaults to the device file system. |
| `config` | `FileTreeConfig` | Filtering and ordering. Only meaningful for `DefaultFileTreeDataSource`; a custom source owns its own filtering and this is ignored with a warning. |
| `rootsVersion` | `number` | Increment to make a mounted tree re-read `getRoots()`. Open directories survive it. |
| `onFileSelected` | `(node: FileNode) => void` | A non-directory row was clicked, or the keyboard cursor moved onto one. |
| `onDirExpanded` | `(node: FileNode) => void` | A directory has been expanded and its children are on screen. |
| `onError` | `(err: Error) => void` | A listing failed. The tree stays usable and the directory can be clicked again. |

A callback that throws is caught and logged; it never takes the tree down.

### `FileNode`

| Field | Type | Notes |
|---|---|---|
| `name` | `string` | Base name, never a path. |
| `path` | `string` | Absolute sandbox path. |
| `isDirectory` | `boolean` | Resolved with `Stat.isDirectory()`, never guessed from the name. |
| `size` | `number?` | Files only — `Stat.size` is valid only for regular files, so directories carry none. |
| `mtime` | `number?` | **Milliseconds** since the epoch, ready for `new Date(...)`. `Stat.mtime` is in seconds; the conversion happens in one place. |
| `uri` | `string?` | Set when access came from a picker grant rather than a pre-authorized directory. |
| `loaded` | `boolean?` | True once the children have been listed. |
| `error` | `string?` | Set when the entry could not be read. The node is still shown — a directory the user cannot open is information, not an error to swallow. |

### `FileTreeConfig`

| Field | Type | Default | Notes |
|---|---|---|---|
| `showHidden` | `boolean` | `false` | Applies to directories as well as files. |
| `extWhitelist` | `string[]` | — | Lower-case, without the dot. **Directories are never filtered by this** — that would hide the whole subtree behind them. |
| `extBlacklist` | `string[]` | — | Takes precedence over `extWhitelist`. |
| `sort` | `FileTreeSort` | `'name-asc'` | `name`/`size`/`date` × `asc`/`desc`. Directories always sort before files; that grouping is not configurable. |

### `FileTreeDataSource`

```ets
export interface FileTreeDataSource {
  getRoots(): Promise<FileNode[]>;
  listChildren(node: FileNode): Promise<FileNode[]>;
}
```

Two async calls, both returning **one level only**. That single-level contract is what makes the
tree lazy — an implementation that recurses defeats the design. `FileTreeView` never touches
`fileIo` itself, so a remote host, an archive or a test double drops in unchanged.

`getRoots()` must not reject just because one root is unavailable; return the ones that worked.
`listChildren()` rejects if the directory itself cannot be listed, but an individual unreadable
entry should come back as a node carrying `error` rather than failing the whole listing.

### `DefaultFileTreeDataSource`

| Method | Purpose |
|---|---|
| `setConfig(config)` | Replace the filtering/ordering config. The caller re-lists to see the effect. |
| `addRoot(node)` | Add a root beyond the pre-authorized three. Ignored if the path is already present. |
| `removeRoot(path)` | Drop a host-added root. Never touches the `Environment` roots. |
| `listExtraRoots()` | The host-added roots, as a copy. |

## Keyboard

The tree takes focus as a whole: ↑ ↓ move the cursor, → opens a folder or steps into an open one,
← closes it or steps out to the parent, Enter and Space activate. On a PC a tree that can only be
driven by pointer is half a component.

## Requirements

- HarmonyOS NEXT, API 24 (`6.1.1(24)`); `ACCESS_USER_FULL_DISK` needs API 22 or later.
- Device types `2in1` (primary) and `tablet`.
- No third-party runtime dependencies — only `@kit.ArkUI`, `@kit.CoreFileKit`, `@kit.AbilityKit`,
  `@kit.BasicServicesKit`, `@kit.InputKit` and `@kit.PerformanceAnalysisKit`.

## Known limitations

- Rows are built with `ForEach`, not `LazyForEach`, so a directory with thousands of entries
  builds every row up front.
- The row shows name and size; modified date is in the model but not in the row layout.
- The strings `Loading…`, `No folders available.` and `empty` are hardcoded English.
- Access is read-only: no rename, delete, move or create.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
