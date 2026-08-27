# FileTreeView

A lazy-loading, file-system-backed tree panel for **HarmonyOS NEXT**, packaged as a reusable
HAR library (`filetreeview`) with a demo app (`entry`).

It renders the device's real file system as an expandable tree: directories carry an expander
arrow from the moment they appear, and a directory's contents are read the first time it is
opened — never at startup, never recursively, and never twice.

The primary target is the **PC / 2-in-1** form factor, where a persistent file panel next to a
detail pane is the natural layout. It runs on tablets too, with the capability differences noted
under [Device capabilities](#device-capabilities).

## Demo

**▶ [screenshots/file-tree-sample.mp4](screenshots/file-tree-sample.mp4)** — a screen recording of
the demo app on a 2-in-1 PC at API 24. Open the file on GitHub to play it inline.

It shows the tree starting with the three pre-authorized user directories and no directory
listings at all, an expander arrow on every directory before anything has been read, one listing
per first expand with real sizes and directories ordered before files, a reopened directory that
does not touch the file system again, and a folder chosen through the system picker joining the
tree as a fourth root — with the directories that were already open staying open.

---

## Contents

- [Demo](#demo)
- [Why this exists](#why-this-exists)
- [Requirements](#requirements)
- [Repository layout](#repository-layout)
- [Building](#building)
- [Using the component](#using-the-component)
- [How an app reaches files](#how-an-app-reaches-files)
- [Permissions](#permissions)
- [Optional: full-disk access](#optional-full-disk-access)
- [Device capabilities](#device-capabilities)
- [Design notes](#design-notes)
- [Verified on device](#verified-on-device)
- [Known limitations](#known-limitations)
- [License](#license)

---

## Why this exists

The pieces of a file browser are all in the platform, but nothing joins them up: an expandable
tree UI, a data layer bound to the real file system, lazy loading on expand, a panel that stays
on screen, and the PC/2-in-1 storage-permission model. `FileTreeView` is those five things in
one component, with no third-party runtime dependencies — only system kits (`@kit.ArkUI`,
`@kit.CoreFileKit`, `@kit.AbilityKit`, `@kit.BasicServicesKit`).

## Requirements

| | |
|---|---|
| SDK | HarmonyOS NEXT, API 24 (`6.1.1(24)`) |
| IDE | DevEco Studio 6 |
| Language | ArkTS, Stage model |
| Device types | `2in1` (primary), `tablet` |
| Runtime dependencies | none |

`ohos.permission.ACCESS_USER_FULL_DISK` requires API 22 or later and is PC/2-in-1 only. It is
**not** enabled in this project by default — see [Optional: full-disk access](#optional-full-disk-access).

## Repository layout

```
.
├── filetreeview/                 the reusable HAR library
│   ├── Index.ets                 public API surface — everything else is internal
│   └── src/main/ets/
│       ├── model/FileNode.ets            data model, no UI and no file-system calls
│       ├── datasource/FileTreeDataSource.ets      the two-call source interface
│       ├── datasource/DefaultFileTreeDataSource.ets   the device file system
│       ├── components/FileTreeView.ets    the tree component
│       ├── permission/UserDirPermissions.ets   user-directory permissions
│       ├── access/StorageAccess.ets       folder picking, persistence, full disk
│       └── util/Format.ets
└── entry/                        demo app that consumes the library
    └── src/main/ets/
        ├── pages/Index.ets               tree panel + detail pane, permission gate
        ├── store/PickedRootStore.ets     one way to persist picked-folder URIs
        └── probe/DataSourceProbe.ets     log-only check of the data layer
```

## Building

No signing configuration is checked in. After cloning:

1. Open the project in DevEco Studio.
2. **File → Project Structure → Signing Configs → Automatically generate signature.**
   Run this *after* the permissions in `entry/src/main/module.json5` are in place, not before —
   see [Permissions](#permissions) for why the order matters.
3. Build and run.

From the command line:

```bash
ohpm install
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
hdc install <path-to-hap>
```

Building the library on its own produces `filetreeview/build/default/outputs/default/filetreeview.har`:

```bash
hvigorw assembleHar --mode module -p product=default --no-daemon
```

That build emits two ArkTS warnings about `ohos.permission.FILE_ACCESS_PERSIST`. They are
expected: a HAR cannot declare permissions on its own behalf, so the compiler is reminding you
that the **consuming app** must declare them. See [Permissions](#permissions).

## Using the component

At its simplest, the component needs no arguments — it defaults to the device file system:

```ets
import { FileTreeView, FileNode } from 'filetreeview';

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

### Public API

| Export | Purpose |
|---|---|
| `FileTreeView` | the component |
| `FileNode`, `FileTreeConfig`, `FileTreeSort` | data model and configuration |
| `FileTreeDataSource` | implement this to back the tree with something else |
| `DefaultFileTreeDataSource` | the device file system; `addRoot` / `removeRoot` / `listExtraRoots` |
| `checkUserDirPermissions`, `requestUserDirPermissions` | user-directory permissions |
| `USER_DIR_PERMISSIONS`, `ALL_USER_DIR_PERMISSIONS`, `DESKTOP_DIR_PERMISSION` | the permission sets |
| `pickFolders`, `activatePersistedRoots`, `PickedRoot` | user-granted folders |
| `hasFullDisk`, `canRequestFullDisk`, `openFullDiskSetting`, `fullDiskRoot`, `FULL_DISK_PERMISSION` | full-disk access |
| `isFolderSelectionSupported`, `isFolderAuthorizationSupported` | device capability checks |

### Keyboard

The tree takes focus as a whole and handles ↑ ↓ to move, → to open a folder or step into an open
one, ← to close it or step out to the parent, and Enter / Space to activate. On a PC a tree that
can only be driven by pointer is half a component.

### Custom data sources

`FileTreeDataSource` is two async calls, both returning **one level only**:

```ets
export interface FileTreeDataSource {
  getRoots(): Promise<FileNode[]>;
  listChildren(node: FileNode): Promise<FileNode[]>;
}
```

That single-level contract is what makes the tree lazy — an implementation that recurses defeats
the design. `FileTreeView` never touches `fileIo` itself, so a remote host, an archive or a test
double drops in unchanged.

## How an app reaches files

There are three routes, and they compose — an app can use all three at once.

| Route | Mechanism | Permission cost | Reach |
|---|---|---|---|
| **User directories** | `Environment` + `fileIo` | 2 × `normal`, 1 × `system_basic` (needs an ACL) | Documents, Download, Desktop |
| **User-picked folders** | `DocumentViewPicker` + `fileShare.persistPermission` | `FILE_ACCESS_PERSIST` — `normal`, `system_grant`, free | any folder the user picks, and it persists |
| **Full disk** | `ACCESS_USER_FULL_DISK` | restricted, `manual_settings`, PC/2-in-1 only | see [below](#optional-full-disk-access) |

The second route is the one most easily overlooked. It needs **no** restricted permission, **no**
ACL, **no** AGC review and shows **no** permission dialog — the user's pick *is* the grant — and
`persistPermission` keeps it across restarts. Grants accumulate, so a folder outside the three
pre-authorized directories becomes a browsable root of the tree like any other. The demo app's
"Add folder…" button is exactly this.

## Permissions

Three facts here cost real debugging time if they are met the hard way.

**1. "Pre-authorized" describes the path, not the read.** `Environment.getUserDocumentDir()` and
its siblings return a path with no permission at all. Listing that path is a different matter:
`fileIo.listFile()` fails with **13900001 `Operation not permitted`** until the matching
`user_grant` permission is declared *and* granted. The message says nothing about permissions,
which is what makes it expensive.

```
ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY   normal         → declare + request
ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY    normal         → declare + request
ohos.permission.READ_WRITE_DESKTOP_DIRECTORY     system_basic   → declare + request + ACL
```

**2. A restricted permission without an ACL costs you the whole install, not one feature.**
`system_basic` permissions must appear in the signing profile's `allowed-acls`, or installation
is rejected outright:

```
code:9568289 install failed due to grant request permissions failed.
PermissionName: ohos.permission.READ_WRITE_DESKTOP_DIRECTORY
```

The order is what matters: declare the permission in `module.json5` **first**, then re-generate
the signature. DevEco reads the declaration and requests the restricted permission from AGC at
signing time. For `READ_WRITE_DESKTOP_DIRECTORY` the approval is immediate.

**3. Adding any permission resets every already-granted permission.** After a change to
`requestPermissions`, the next install returns every permission to `-1` and all the dialogs come
back — not only for the new one. Re-signing has the same effect. This is not a bug in your code.

**A HAR cannot carry permissions for its host.** `requestPermissions` in a library module is not
merged into the consuming HAP, so an app using `filetreeview` declares them itself. Copy the
block from `entry/src/main/module.json5`.

## Optional: full-disk access

`ohos.permission.ACCESS_USER_FULL_DISK` is declared but **commented out** in
`entry/src/main/module.json5`. The supporting code is live and complete — `hasFullDisk()`,
`canRequestFullDisk()`, `openFullDiskSetting()` and `fullDiskRoot()` all work, and the demo shows
a "Full disk…" button whenever the permission is declared and not yet granted.

Before uncommenting it, know what you are taking on:

- It is **restricted** (`system_basic`), so the signing profile needs an ACL. Without one the app
  installs **nowhere** — `code:9568289` again. A failed ACL request costs the whole build, not
  one feature.
- Unlike `READ_WRITE_DESKTOP_DIRECTORY`, which is approved on submission, this one is documented
  as reviewed **within three working days**.
- Authorization is **`manual_settings`**: there is no runtime dialog, ever.
  `requestPermissionsFromUser` cannot grant it. The user turns it on in Settings, and
  `openFullDiskSetting()` is the button that takes them there.
- It is **PC/2-in-1 only**. On a tablet the status is `INVALID` and the demo's button correctly
  stays hidden.

To enable it, add this entry to `requestPermissions` in `entry/src/main/module.json5`:

```json5
{
  "name": "ohos.permission.ACCESS_USER_FULL_DISK",
  "reason": "$string:reason_full_disk",
  "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
}
```

The `reason_full_disk` string resource is already present. Then re-generate the signature
(**File → Project Structure → Signing Configs**, toggle *Automatically generate signature* off
and on), rebuild and install. If the install fails with `9568289`, the ACL was not granted —
remove the entry and you are where you started.

## Device capabilities

Three separate system capabilities sit behind what reads in the documentation like one picker
API, and the device manifest is the only place that says which of them you have. Before
debugging anything storage-related on a new device:

```bash
hdc shell cat /system/etc/syscap.json | grep -oE '"SystemCapability\.FileManagement[^"]*"' | sort -u
```

| Capability | Gates |
|---|---|
| `...File.Environment.FolderObtain` | the `Environment` user-directory getters |
| `...UserFileService.FolderSelection` | `DocumentSelectMode.FOLDER` — picking a **folder** |
| `...AppFileService.FolderAuthorization` | `persistPermission` / `activatePermission` |

`UserFileService.FolderSelection` is the one that varies most. On a tablet at API 24 it is
**absent** while plain `UserFileService` is present: files can be picked there, folders cannot.
Since a *file* grant does not make its parent directory listable, there is no fallback — on such
a device the tree's reach really is the pre-authorized directories and nothing more. On a
2-in-1 PC it is present and folder picking works.

The library exposes `isFolderSelectionSupported()` and `isFolderAuthorizationSupported()` for
exactly this. Check before offering the affordance: a button that can only ever fail is worse
than no button.

## Design notes

**This is not the official `@kit.ArkUI` TreeView.** That component was used first and abandoned
after three defects, all measured on device, all the same root cause — it expects a tree that is
fully known before it is built:

- its expander arrow tracks *children present* rather than "is a folder", so an unexplored
  directory is drawn exactly like a file;
- `TreeController.buildDone()` is a full rebuild, so publishing newly loaded children collapses
  every directory the user has opened and clears the selection;
- skipping `buildDone()` avoids the collapse, but the new nodes then render in TreeView's
  uncommitted *editing* state — highlighted rows with a text field around each name.

What replaced it is a flat adapter: a `List` over a flattened array of the currently visible
rows, each row a node plus its depth and expansion state. The expander is drawn by this
component, so every directory has one from the moment it appears.

Things worth knowing before editing `FileTreeView`:

- `refresh()` is the **only** writer of `this.rows`, and it assigns a **new** array. Mutating the
  old one does not redraw.
- The `ForEach` key includes mutable row state *and* a per-row id. A key of just the path is not
  enough: a picked folder can sit inside a pre-authorized one, which puts the same path in the
  tree twice.
- Reloading roots reuses the row of any root whose path is unchanged, so open directories survive
  an add or a remove. Rebuilding blindly reintroduces the collapse described above.
- Every host callback goes through `emit()`. A throwing host callback must never take the tree
  down.

**The library never persists anything.** `pickFolders()` hands back URIs and
`activatePersistedRoots()` takes them again on the next launch; where they live in between is the
host's business. A HAR that quietly creates a preferences file inside its host's data directory
is a surprise. `entry/src/main/ets/store/PickedRootStore.ets` is one small answer, not the only
one. Persist the **URI**, not the path — only a URI can be re-activated.

## Verified on device

The [demo recording](screenshots/file-tree-sample.mp4) is this session.

On a HarmonyOS NEXT **2-in-1 PC** at API 24:

- three user-directory roots, expander arrows on every directory, and **zero** directory listings
  at startup;
- one listing per first expand, never repeated when a directory is reopened;
- real metadata — directories before files, sizes up to `95.3 MB`, an empty directory reported as
  `empty` rather than looking unreadable;
- folder picking: a directory outside the pre-authorized three joined the tree as a fourth root,
  and `persistPermission` succeeded;
- changing the root set with a directory open left that directory open, with its children intact.

On a **tablet** at API 24: the same tree and metadata, plus keyboard navigation; folder picking
is unavailable there, as the capability table above predicts.

## Known limitations

- Rows are built with `ForEach`, not `LazyForEach`, so a directory with thousands of entries
  builds every row up front. This is a `build()`-only change if it matters to you.
- The row shows name and size; modified date is in the model (`FileNode.mtime`, milliseconds) but
  not in the row layout.
- Strings in the component (`Loading…`, `No folders available.`, `empty`) are hardcoded English
  rather than resource references.
- Access is read-only. There is no rename, delete, move or create.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
