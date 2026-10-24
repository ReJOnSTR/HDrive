# Windows / macOS desktop parity

The following previously identified desktop differences are now covered on both systems:

| Capability | Windows | macOS |
| --- | --- | --- |
| Copy cloud files and complete recursive folders to other apps | Complete export batch | Complete export batch before clipboard publication |
| Drag a selection outside HDrive | Selected files/folders | One native file promise per selected file/folder |
| Search current folder or descendants | Extension, minimum size, modified-after date | Same filters; no four-level cutoff |
| Repeat folder synchronization | Optional every minute while the sync dialog is open | Optional every minute while the sync screen is open |
| Resume queued HTTP downloads after restarting HDrive | Saved partial data with Range / If-Range | Saved partial data with Range / If-Range |
| Check and download application updates | Settings; verified setup executable | Settings/menu; verified DMG |

Automatic folder sync skips conflicts and does not propagate deletions. Closing its screen stops the schedule. Neither desktop app implements a full OS cloud-file provider or a scheduler that keeps syncing after the app exits. Update installation keeps the native platform flow: a Windows setup wizard or replacing the macOS application from its DMG.

Resume requires a server supporting byte ranges and a usable ETag or Last-Modified validator. If the remote representation changes, the app downloads the complete new version. SMB and exports lacking suitable HTTP validators restart. Third-party drop targets must accept the platform's file-transfer formats; native file promises do not make every application's editor a file drop destination.

Regression coverage includes recursive clipboard exports, failure rollback, duplicate names, lazy multi-item file promises, Turkish filtering, deep traversal, cancellation, persistent partial downloads, changed representations and invalid Content-Range responses. Windows core storage/sync tests and CI native builds/startup checks complement these tests; external drop behavior still depends on the receiving application.
