---
title: "Deploy the OpenIRN applications"
subtitle: "Android, Windows, macOS, iOS, and the first device"
author: "OpenIRN Project"
---

# Read this before deployment

OpenIRN GitHub releases currently publish signed applications for **Android** and **Windows**. The release pipeline does not yet publish a macOS or iOS application.

| Platform | Artifact currently published | Deployment from a GitHub release |
|---|---|---|
| Android | `openirn-android.apk`, `openirn-android.aab` | yes |
| Windows x64 | `openirn-windows-x64.msix`, `openirn-windows-signed.zip`, or Microsoft Store | yes |
| macOS | no signed/notarized artifact | no |
| iOS/iPadOS | no IPA or TestFlight link | no |

> The current official clients use the fixed API `https://www.archoad.io/api`. A client for another server URL must be built after changing `SyncConfiguration.fixedApiBaseUrl`; generic release binaries do not allow users to enter a different URL.

# 1. Select and verify a release

Open the **Releases** page of the `archoad/OpenIRN` repository and select a published version.

Also download `SHA256SUMS.txt`. Check that the release tag matches the version required by your deployment plan.

## Verification on macOS or Linux

Place the files in the same directory:

```bash
cd ~/Downloads/OpenIRN-release
shasum -a 256 -c SHA256SUMS.txt
```

On Linux, `sha256sum -c SHA256SUMS.txt` performs the equivalent check.

Every downloaded artifact must be marked `OK`. If a check fails, delete the file and download it again from the official release.

## Verification in Windows PowerShell

```powershell
Set-Location "$HOME\Downloads\OpenIRN-release"
Get-Content .\SHA256SUMS.txt
Get-FileHash .\openirn-windows-x64.msix -Algorithm SHA256
Get-FileHash .\openirn-windows-signed.zip -Algorithm SHA256
```

Compare the checksums exactly. For the MSIX, also verify the signature:

```powershell
Get-AuthenticodeSignature .\openirn-windows-x64.msix |
  Format-List Status,StatusMessage,SignerCertificate,TimeStamperCertificate
```

The status must be `Valid`, and the expected publisher is Archoad.

# 2. Deploy on Android

Two formats are published:

- the APK is used for direct deployment or deployment through an MDM solution;
- the AAB is used for Google Play publishing and cannot be installed directly on a device.

## Manual APK installation

1. Download `openirn-android.apk` from the release.
2. Verify its SHA-256 checksum.
3. Transfer the file to the device through a controlled channel.
4. Temporarily allow installation of unknown applications for the application opening the APK.
5. Open the APK and confirm installation.
6. Remove the “unknown sources” permission after installation.

> Do not uninstall the previous version during a normal update. Uninstallation removes local configuration and the enrollment secret held in secure storage.

## Controlled installation with ADB

After temporarily enabling USB debugging:

```bash
adb devices
adb install -r openirn-android.apk
```

Expected result: `Success`. Disable USB debugging afterward if it is no longer required.

To identify the installed version:

```bash
adb shell dumpsys package io.github.archoad.openirn | grep -E 'versionName|versionCode'
```

## Deployment through MDM or EMM

Import the signed APK into the organization's private catalog, or publish the AAB to a managed Google Play track. Assign the application to a pilot group first. Keep the Android identifier `io.github.archoad.openirn` unchanged so that in-place updates remain possible.

# 3. Deploy on Windows x64

MSIX is the recommended format for a managed fleet. The portable ZIP is intended for a controlled test or for environments that do not yet deploy MSIX packages.

## Recommended option: signed MSIX

1. Download `openirn-windows-x64.msix`.
2. Verify the SHA-256 checksum and Authenticode signature.
3. Double-click the MSIX.
4. Check that Windows displays Archoad as the publisher.
5. Select **Install**.
6. Start OpenIRN from the Start menu.

An interactive installation can also be started in PowerShell:

```powershell
Add-AppxPackage -Path .\openirn-windows-x64.msix
```

Check the installed package:

```powershell
Get-AppxPackage -Name Archoad.OpenIRN |
  Select-Object Name,PackageFullName,Version,Publisher
```

An MSIX update must use the same identity and a higher version number. Test the update first on an already enrolled pilot device.

## Installation from Microsoft Store

The release workflow builds two separate Windows packages:

- `openirn-windows-x64.msix`, signed by Azure Artifact Signing, remains available for direct download from the GitHub Release;
- `OpenIRN-Store.msix` uses the identity assigned by Partner Center. This submission file is not attached to the GitHub Release and must not be installed directly. Microsoft Store signs it after certification and distributes the final package.

Once the OpenIRN listing is live, search for **OpenIRN** in Microsoft Store, check that **archoad FR** is displayed as the publisher, then select **Install**. Further updates are delivered by the Store.

Check the installed package:

```powershell
Get-AppxPackage -Name archoadFR.OpenIRN |
  Select-Object Name,PackageFamilyName,PackageFullName,Version,Publisher
```

The Store identity differs from the direct-download MSIX identity. Windows therefore cannot update one with the other. Select one distribution channel for each device and uninstall the old package before switching channels, after checking that all required data has synchronized with the server.

## Automatic publication to Microsoft Store

This section is intended for the release maintainer. Partner Center assigned these values to OpenIRN:

| Property | Value |
|---|---|
| `Package/Identity/Name` | `archoadFR.OpenIRN` |
| `Package/Identity/Publisher` | `CN=0C16A5BC-1E9E-4174-A14C-FD52C54BD219` |
| `Package/Properties/PublisherDisplayName` | `archoad FR` |
| Package Family Name | `archoadFR.OpenIRN_40n6zg9mmw8te` |
| Package SID | `S-1-15-2-1093717781-299261422-2075608443-880705312-3180602753-3190663317-2185964278` |

Before enabling automation:

1. check that the product is free: Microsoft currently limits this GitHub Actions automation to free products;
2. complete the first submission manually in Partner Center and wait for the app to become available;
3. register a Microsoft Entra application and add it to the Partner Center users with the **Manager** role;
4. create a `microsoft-store` environment in the GitHub repository;
5. add `PARTNER_CENTER_TENANT_ID`, `PARTNER_CENTER_SELLER_ID`, `PARTNER_CENTER_CLIENT_ID`, and `PARTNER_CENTER_CLIENT_SECRET` as environment secrets;
6. add the `MICROSOFT_STORE_PRODUCT_ID` variable with the product ID shown by Partner Center. This ID is not `archoadFR.OpenIRN`;
7. leave `MICROSOFT_STORE_PUBLISH_ENABLED` unset or set to `false` during bootstrap;
8. run a release and download the `openirn-windows-store-submission` GitHub Actions artifact if the first submission package is needed;
9. after the first version is live, set `MICROSOFT_STORE_PUBLISH_ENABLED=true` in the `microsoft-store` environment.

For every `vX.Y.Z` tag, the workflow checks the Store MSIX identity and version, then runs the automatic submission when this variable is exactly `true`. Flutter version `X.Y.Z+build` produces direct MSIX version `X.Y.Z.build` and Store MSIX version `X.Y.Z.0`: the fourth component remains zero because Microsoft Store reserves it. A version that has already been submitted, or is lower than the Store version, will be rejected. A required reviewer rule on the GitHub environment will keep the job waiting; do not configure one if publication must be fully automatic.

## Portable option: signed ZIP

```powershell
New-Item -ItemType Directory -Force "$HOME\Applications\OpenIRN" | Out-Null
Expand-Archive -Path .\openirn-windows-signed.zip -DestinationPath "$HOME\Applications\OpenIRN" -Force
Get-AuthenticodeSignature "$HOME\Applications\OpenIRN\OpenIRN.exe" |
  Format-List Status,SignerCertificate,TimeStamperCertificate
& "$HOME\Applications\OpenIRN\OpenIRN.exe"
```

Do not move `OpenIRN.exe` on its own. The ZIP contains required libraries alongside the executable.

# 4. Deploy on macOS

## Current status

The GitHub release does not include a signed and notarized `.dmg`, `.pkg`, or `.app`. There is therefore currently no macOS deployment procedure **from a GitHub release**.

The limitation is not functional. It concerns Apple signing and the Keychain entitlements used to store the device token securely.

# 5. Deploy on iOS or iPadOS

## Current status

The GitHub release provides neither a signed IPA nor a TestFlight link. An unmanaged iPhone or iPad therefore cannot receive OpenIRN from the current release.

# 6. Prepare the server before first launch

The server must already respond:

```bash
curl --fail --silent --show-error https://www.archoad.io/api/health
```

For a new instance, create the first solution administrator on the server:

```bash
cd /opt/openirn-api
(
	set -a
	. /etc/openirn-api.env
	set +a
	.venv/bin/python tools/create_superuser.py \
		--tenant "$OPENIRN_SOLUTION_ADMIN_TENANT_ID" \
		--tenant-name 'OpenIRN Administration' \
		--first-name 'First name' \
		--last-name 'Last name' \
		--email 'admin@example.org'
)
```

The temporary PIN is entered interactively and must be changed at first login.

Restart the API to reconcile the solution administrator profile with existing workspaces:

```bash
systemctl restart openirn-api
systemctl is-active openirn-api
```

Then create a code for the first device:

```bash
cd /opt/openirn-api
(
	set -a
	. /etc/openirn-api.env
	set +a
	.venv/bin/python tools/create_bootstrap_enrollment.py \
		--tenant "$OPENIRN_SOLUTION_ADMIN_TENANT_ID" \
		--label 'First OpenIRN device' \
		--expires 10
)
```

The code is secret, temporary, and single-use.

# 7. Initialize the first application

On the newly installed device:

1. Open OpenIRN.
2. Choose the administration workspace.
3. Select **Authorize this device**.
4. Enter the bootstrap code provided by the server administrator.
5. Check that the home screen shows the device as authorized.
6. Select **Unlock OpenIRN**.
7. Choose the solution administrator account.
8. Enter the temporary PIN.
9. When prompted, choose a new, non-trivial PIN.

The device token is stored in the platform's secure storage. The user session remains only in memory and disappears when the application closes or is locked.

# 8. Add subsequent devices

Two methods are available.

## Request from the new device

1. On the new device, choose the workspace.
2. Open **Authorize this device**.
3. Select **Request authorization**.
4. On an authorized administrator or IRN Pilot device, open **Administration → Authorized devices**.
5. Check the requested name, platform, and workspace.
6. Approve or reject the request.
7. Send the one-time code to the holder of the new device through a separate channel.
8. On the new device, enter the code and complete enrollment.

## Code created from Administration

From **Administration → Authorized devices**, create a code for the relevant workspace and have the new device consume it. Authorization remains limited to that workspace: the same device must be explicitly enrolled in every workspace it needs.

# 9. Post-deployment acceptance test

On every platform:

1. Check the version under **About / License**.
2. Check language and display.
3. Select the correct workspace.
4. Check the device authorization status.
5. Open and then lock a user session.
6. View the official referential.
7. Open a test campaign in read-only mode.
8. Check the return to the home screen after closing and restarting the application.

For an authorized role, add a non-destructive write test to an identified test campaign, then verify synchronization on a second device.

# 10. Update the applications

Before an update wave:

1. verify the release and its checksums;
2. confirm the stated compatibility with the API version;
3. back up the server;
4. deploy to a small pilot group;
5. check that device enrollment is preserved;
6. check login, reading, writing, and synchronization;
7. expand deployment gradually.

On Android, use `adb install -r` or an MDM update without uninstalling. On Windows, install a higher-version MSIX with the same identity. Revoking a device is not the same as uninstalling it: revocation cuts off that device's server access for the relevant workspace.

# 11. Remove a device

1. Under **Administration → Authorized devices**, select the workspace.
2. Identify the device by its name, platform, and last activity.
3. Revoke its authorization.
4. Check the security log to confirm that revocation was recorded.
5. Then uninstall the application or wipe the workstation according to fleet policy.

Server-side revocation takes priority: simply uninstalling the application does not automatically revoke the persistent authorization.
