# Desktop application updates

Open **Settings → Updates** on Windows or **Ayarlar → Güncellemeler** on macOS. The macOS HDrive menu also has **Güncellemeleri kontrol et…**. Checks are manual; merely starting the application does not contact GitHub for updates.

The updater reads the public `ReJOnSTR/HDrive` repository's `/releases/latest` endpoint without account credentials. It shows the installed version, latest published stable version, release notes and last successful check. Network failures and unpublished releases have separate messages. Numeric major/minor/patch comparison prevents downgrades, including development installations newer than the published release.

A newer release offers **İndir ve kurulumu başlat** when its platform asset and SHA-256 digest are available. Downloads support progress and cancellation, and are verified before delivery. A missing or unsuitable package links the user to the release page instead. The updater preserves macOS quarantine and Windows Internet-zone metadata; it does not bypass Gatekeeper, SmartScreen or the OS installer.

- macOS expects `HDrive-macOS.dmg`. The DMG is opened after verification; the user closes HDrive and moves the new application into Applications.
- Windows expects `HDrive-Setup.exe`. The setup wizard is started after verification; the user completes the normal installation. Portable users can instead use the release page to download the portable ZIP.

Publishing a release with a stable `vMAJOR.MINOR.PATCH` tag and the existing asset names makes it visible automatically. Drafts and prereleases are not offered. Existing release signing/notarization requirements remain in force; see [RELEASE-SIGNING.md](RELEASE-SIGNING.md). GitHub's [release API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release) supplies asset sizes and SHA-256 digests.

Validation includes numeric version ordering, draft/prerelease rejection, same-version/downgrade rejection, trusted asset selection, hash/length failure, download cancellation and HTTP failure states. The Windows updater service runs in the cross-platform core regression suite; macOS update checks run in the Apple regression suite.
