# UI and workspace changes

## Implemented

- Desktop Settings now includes Updates: installed/published versions, manual checks, release notes, download progress, cancellation and installer launch. macOS also exposes the update window from the HDrive menu. Only published stable GitHub releases are eligible; an equal or older release is never offered as an update.
- Update packages must match the repository's exact platform asset URL, expected size and GitHub SHA-256 digest. Failed/cancelled downloads are discarded and normal Internet-download security metadata is preserved. Windows starts the setup wizard; macOS opens the DMG and explains replacing the application in Applications. No account migration, automatic app replacement or unattended installation is performed by the updater.

- macOS external drag exports materialize files and recursive folders before providing either a file URL or a typed file representation. Each export uses an isolated, protected account directory; failed exports remove partial content. Filename collisions preserve both children.
- macOS directory responses are accepted only for the current request, account identity, tab and path. Disconnecting or leaving the view invalidates pending responses.
- Both Apple WebDAV clients preserve complete XML text (including Turkish names, whitespace and CDATA) and reject foreign-origin download hrefs before attaching credentials. The same storage regressions run against both client implementations in CI.
- macOS launch/restart scripts use the canonical Universal build output. Restart builds successfully before asking the running application to quit.

- iOS file import offers replace, keep both and skip. Replacement is staged before touching the destination. Existing directories are never merged or deleted by the replacement path.
- iOS local deletion uses a recoverable trash directory, with immediate undo and a restore list. Restore preserves a new file that appeared at the original path.
- Local iOS list and grid expose the same actions. Local multi-selection supports sharing, moving and trash; cloud multi-selection supports downloading, moving, deleting and sharing existing provider links.
- Windows search survives focus changes. Scope can include subfolders; extension, minimum size and modified-after filters are available. Search work is cancelled when navigating or changing the query.
- Directory failures, empty folders and empty search results have separate states. File operations surface individual failures instead of silently reporting success.
- Windows navigation/preview widths and the macOS preview adapt to smaller windows. Primary icon controls have accessible labels; mobile cloud rows expose an accessible activation action.
- App version displays read application metadata; iOS project metadata matches the current 1.4.4 source version. Core UI translations use shared Turkish/English JSON resources, with WinUI search/action captions also backed by RESW resources.
- Windows and Apple transfer journals contain account IDs and storage identity hashes, not credentials. Unfinished transfers restore paused and require a matching connected account to resume.
- Windows downloads resume from stable partial files using Range and If-Range validators, and restart when the server returns a new full representation. Apple WebDAV downloads retain URLSession resume data while the process remains alive. Provider-specific Apple transfers restart when resumed; opaque resume data is not written to plaintext journals.
- Offline copies are indexed independently from temporary caches and scoped to account identity and remote path. Apple native document exports keep the name registered in that index.
- Cache usage and size controls preserve externally opened working copies. Offline files are outside the cleanup roots. Working-copy protections persist across restarts; the limit cannot force deletion of protected copies.
- Folder synchronization scans both sides, hashes local files, saves a per-account/per-folder baseline, honors exclude patterns, and reports conflicts. Users can keep local, cloud or both copies. Deletions require a deliberate decision and are never propagated automatically. Apple can repeat non-conflicting work while its sync screen is open; Windows exposes explicit preview/apply operations.
- Google Drive files can be trashed and restored. Google/OneDrive sharing can retrieve an existing access link, explicitly grant public read access, or revoke public links while retaining private collaborators. Permission and version lists follow pagination and enforce the provider origin.
- Google revisions and OneDrive versions are listed; OneDrive versions can be restored after explicit confirmation. Google revision restoration is handed off to its provider interface.
- Windows Explorer and macOS Finder connection actions use the OS WebDAV/SMB connection workflow without embedding account credentials in the launched address.

## Boundaries that remain

- These OS connection actions are network mounts, not a complete Windows Cloud Files or Apple File Provider implementation. Native provider extensions, their installation/registration and their sharing/signing entitlements are not implemented in this change. They require a dedicated integration and platform validation.
- Provider trash/version/permission capabilities are not universal: the in-app trash list currently covers Google Drive; OneDrive recycle-bin browsing and Google revision restoration remain provider UI operations. WebDAV/S3/SMB do not gain unsupported provider APIs.
- Sync operates on files and required parent directories. Empty-directory mirroring, automatic deletion propagation, cross-process background scheduling, and server-enforced conditional writes are not provided. The engine rechecks local hashes and remote metadata before a transfer; it is not a distributed lock against a write occurring during the final request.
- Turkish/English resources cover core captions. Some legacy macOS/settings text and explanatory/error sentences still need full localization. Automated checks do not replace screen-reader and high-contrast usability testing on real devices.
- Offline files do not automatically sync edits by themselves; use folder sync for a managed local folder. Apple queue restoration persists operations but not credential-bearing URLSession resume blobs.

## Validation

Regression fixtures cover failed imports, trash restore collisions, protected cache cleanup, journal recovery, sharing permissions, native export names, byte-range resume, sync direction/conflicts, and actual bidirectional transfers. Cloud fixtures never authenticate to a real cloud account. CI builds and opens the Windows application, verifies v1.2.7 migration/restart, builds Universal macOS packages and compiles the iOS simulator app.
