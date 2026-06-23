# GitHub Actions CI

This patch adds the first CI layer for OpenIRN.

## Workflows

### Flutter CI

File:

```text
.github/workflows/flutter_ci.yml
```

The workflow runs on every push and pull request targeting `main` or `master`.

It executes:

```bash
cd flutter
flutter pub get
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
```

The workflow intentionally does not build platform artifacts yet. Build jobs for Android, iOS, macOS, and Windows will be added later, once packaging/signing choices are stable.

### Open source readiness

File:

```text
.github/workflows/open_source_readiness.yml
```

This workflow runs:

```bash
./tools/check_open_source_readiness.sh
```

Its role is to prevent accidental publication of generated referential files, private campaign exports, internal Excel files, or secrets.

## Dependabot

File:

```text
.github/dependabot.yml
```

Dependabot checks weekly for updates to:

- GitHub Actions;
- Flutter/Dart dependencies in `flutter/pubspec.yaml`.

## Notes

The official aDRI IRN referential files should not be committed to the public OpenIRN repository. CI assumes tests use fixtures and generated/public-safe assets only.

The first CI target is repository quality. Release builds and signed artifacts should be added in a later milestone.
