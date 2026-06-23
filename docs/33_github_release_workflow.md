# GitHub Release workflow

Patch 035 adds a release workflow for OpenIRN.

The workflow builds and publishes release artifacts when:

- a tag matching `v*` is pushed, for example `v0.1.0`;
- the workflow is launched manually from the GitHub Actions tab.

## Produced artifacts

- `openirn-android.apk`
- `openirn-macos.zip`
- `openirn-windows.zip`
- `openirn-ios-no-codesign.zip`
- `SHA256SUMS.txt`

## Current distribution status

These artifacts are useful for validation and early distribution, but they are not yet store-ready:

- Android APK is not configured for Play Store signing.
- macOS app is not signed or notarized.
- Windows artifact is a ZIP, not an MSIX installer.
- iOS build is generated with `--no-codesign`.

## Creating the first release

```bash
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actions will build the artifacts and attach them to a GitHub release.

## Manual release

In GitHub:

1. Go to **Actions**.
2. Open **Release**.
3. Click **Run workflow**.
4. Enter a tag such as `v0.1.0`.
5. Choose whether the release is a pre-release.

## Security / licensing note

The release workflow must not package:

- the official aDRI IRN spreadsheet;
- generated canonical referential JSON files;
- private campaign exports;
- internal enterprise data.

The validation job runs `tools/check_open_source_readiness.sh` before building artifacts.
