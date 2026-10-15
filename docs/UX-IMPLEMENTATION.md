# UX and workspace implementation

Active work follows the UI/UX findings and ten feature gaps from the review.

## Applied, validation in progress

- Safe iOS imports with replace / keep both / skip; existing destination is staged safely.
- Local iOS trash, undo, restore and multi-selection; equal list/grid actions.
- Windows persistent search, recursive scope and extension / size / date filters.
- Visible operation and directory errors; distinct empty/search/error states.
- Responsive Windows navigation / preview sizing and accessible control labels.
- Dynamic iOS app version and provider-neutral wording.
- Account-bound offline file destinations and mobile batch download/upload/delete.
- Durable Windows and Apple transfer journals without credentials; restored work is paused.
- Validator-protected Windows byte-range download resumption.
- Apple provider actions: rename, Google trash/restore, sharing and version history APIs (UI pending).

## Remaining work in this task

- Finish feature UI (offline library, cache management, provider trash/sharing/versions).
- Two-way folder synchronization and conflict handling.
- Native system integration: use the OS WebDAV connection workflow where available; a true iOS/File Provider or Windows Cloud Files provider requires separate signed extension/installation registration and must not be represented as complete without that registration.
- Localization resources and accessibility coverage.
- Regression tests, all platform builds, Windows CI and final commit/push.

## Verification boundary

HTTP fixtures validate provider request contracts. No real cloud account is modified by automated tests. Distribution certificates and File Provider entitlements are not present in this checkout.
