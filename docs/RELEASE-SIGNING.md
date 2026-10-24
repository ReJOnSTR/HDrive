# Release signing

Public `v*` tag-triggered builds require signed Windows packages and a Developer ID signed,
notarized macOS application. Pull requests and main-branch verification builds
can run without distribution secrets. The iOS simulator build never uses a
signing identity.

Configure these **repository Actions secrets**; do not commit certificates,
private keys, passwords, or token files to the repository.

| Secret | Purpose |
| --- | --- |
| `WINDOWS_SIGNING_CERTIFICATE_BASE64` | Base64 encoded Authenticode PFX containing the signing key |
| `WINDOWS_SIGNING_CERTIFICATE_PASSWORD` | PFX password |
| `MACOS_SIGNING_CERTIFICATE_BASE64` | Base64 encoded Developer ID Application PKCS#12 export |
| `MACOS_SIGNING_CERTIFICATE_PASSWORD` | PKCS#12 password |
| `APPLE_NOTARY_KEY_BASE64` | Base64 encoded App Store Connect notarization API private key (`.p8`) |
| `APPLE_NOTARY_KEY_ID` | App Store Connect key ID |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect issuer ID |

An **Apple Development** certificate does not replace a **Developer ID
Application** distribution certificate. Certificate formats backed by an HSM or
cloud signing service require adapting `windows/sign-release.ps1` to that
provider; its key must not be exported to a PFX if the provider prohibits it.

Windows signs the application executable, managed application DLL, and final
Inno Setup installer with SHA-256 and an RFC 3161 timestamp. macOS imports the
certificate into a temporary keychain, signs the Universal bundle using hardened
runtime, submits its DMG to Apple, and staples the accepted notarization ticket
to the application and disk image. Temporary keys are removed in `finally`/EXIT
handlers. macOS ZIP packaging occurs after stapling.

If required credentials are absent or signing/notarization fails, tag builds
stop before GitHub Release publication. Do not replace that failure with a
successful unsigned distribution step.

An explicitly authorized unsigned release can instead be started manually from
`main` using **Build and Release HDrive** with `publish_release=true`, a
`release_tag` matching all application versions, and
`allow_unsigned_release=true`. This exception is off by default and cannot
disable signing for tag-triggered builds. All tests and platform builds still
run. Release notes identify the unsigned/unnotarized packages. The workflow
uploads a draft, verifies every package size and SHA-256 digest, then publishes
it as the latest stable release. The v1.4.6 unsigned publication was explicitly
authorized by the repository owner.

# Verification

From the repository root:

```sh
dotnet run --project windows/tests/AccountSerialization/AccountSerialization.csproj
dotnet run --project windows/tests/CoreRegression/CoreRegression.csproj
bash macOS/test-regressions.sh
bash macOS/build-macos.sh
```

The tests use isolated profiles, a fake credential store and HTTP/URLProtocol
fixtures. They never authenticate to a real Google, Microsoft, S3, or WebDAV
account. Public cloud permissions, provider-specific tenant policies, and final
distribution signatures still require a configured release environment.

The macOS build compiles `arm64` and `x86_64` separately and verifies both slices.
Development bundle signing is done in a temporary folder so File Provider
metadata in a Documents workspace cannot invalidate the signing operation.

GitHub Actions also builds the iOS simulator application and opens the actual
Windows executable with a clean profile, a v1.2.7 legacy profile, a migrated
profile on restart, and an existing multi-account profile.
