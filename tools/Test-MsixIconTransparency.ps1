[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$PackageRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PackageRoot -PathType Container)) {
  throw "MSIX package root not found: $PackageRoot"
}

$manifestPath = Join-Path $PackageRoot 'AppxManifest.xml'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "MSIX manifest not found: $manifestPath"
}

[xml]$manifest = Get-Content -LiteralPath $manifestPath
$storeLogo = $manifest.SelectSingleNode(
  "/*[local-name()='Package']/*[local-name()='Properties']/*[local-name()='Logo']"
)
$visualElements = $manifest.SelectSingleNode(
  "/*[local-name()='Package']/*[local-name()='Applications']/*[local-name()='Application']/*[local-name()='VisualElements']"
)
if (-not $storeLogo -or -not $visualElements) {
  throw 'Expected MSIX logo declarations are missing from AppxManifest.xml'
}

$requiredIconPaths = @(
  [string]$storeLogo.InnerText,
  [string]$visualElements.GetAttribute('Square150x150Logo'),
  [string]$visualElements.GetAttribute('Square44x44Logo'),
  'Images\Square44x44Logo.targetsize-256.png'
)

Add-Type -AssemblyName System.Drawing

foreach ($iconPath in $requiredIconPaths) {
  if ([string]::IsNullOrWhiteSpace($iconPath)) {
    throw 'An expected MSIX icon path is missing from AppxManifest.xml'
  }

  $iconDirectory = Join-Path $PackageRoot (Split-Path $iconPath -Parent)
  $iconBaseName = [System.IO.Path]::GetFileNameWithoutExtension($iconPath)
  $iconExtension = [System.IO.Path]::GetExtension($iconPath)
  $qualifiedIconFiles = @(
    Get-ChildItem -LiteralPath $iconDirectory -File -ErrorAction SilentlyContinue |
      Where-Object {
        $_.Name -eq "${iconBaseName}${iconExtension}" -or
        $_.Name -like "${iconBaseName}.scale-*${iconExtension}"
      }
  )
  if ($qualifiedIconFiles.Count -eq 0) {
    throw "Expected MSIX icon is missing: $iconPath"
  }

  foreach ($iconInfo in $qualifiedIconFiles) {
    $bitmap = [System.Drawing.Bitmap]::new($iconInfo.FullName)
    try {
      $corners = @(
        $bitmap.GetPixel(0, 0),
        $bitmap.GetPixel($bitmap.Width - 1, 0),
        $bitmap.GetPixel(0, $bitmap.Height - 1),
        $bitmap.GetPixel($bitmap.Width - 1, $bitmap.Height - 1)
      )
      $opaqueCorners = @($corners | Where-Object { $_.A -ne 0 })
      if ($opaqueCorners.Count -ne 0) {
        throw "MSIX icon background is not transparent: $($iconInfo.FullName)"
      }
    }
    finally {
      $bitmap.Dispose()
    }

    $relativeIconPath = $iconInfo.FullName.Substring($PackageRoot.Length + 1)
    Write-Host "MSIX transparent icon: $relativeIconPath ($($iconInfo.Length) bytes)"
  }
}
