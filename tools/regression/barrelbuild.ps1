# Rebuilds the BLE Barrel .barrel artifact from a worktree's source.
# The route is the one PROTOCOL_APK.md (Finding 3) recorded: monkeyc cannot
# build a module (iq:barrel manifest), barrelbuild folds the compile in.
# The SDKs here do not know the product epix2pro47mmsystem7preview listed in
# the barrel manifest, so the build runs from a scratch copy of the manifest
# with that single product line removed. The committed manifest is never edited.
param(
  [Parameter(Mandatory=$true)][string]$Src,   # worktree root
  [Parameter(Mandatory=$false)][string]$Out   # artifact path (default: Src\BLE Barrel\BLE Barrel-1.0.0.barrel)
)
$sdk = "C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.3.0-2026-10-20-95888f262"
$barrelDir = Join-Path $Src "BLE Barrel"
if (-not $Out) { $Out = Join-Path $barrelDir "BLE Barrel-1.0.0.barrel" }
$scratch = Join-Path $env:TEMP ("bb-" + (Split-Path $Src -Leaf) + "-" + (Get-Random))
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
Copy-Item (Join-Path $barrelDir "BLEBarrel.mc") $scratch
Copy-Item (Join-Path $barrelDir "monkey.jungle") $scratch
(Get-Content (Join-Path $barrelDir "manifest.xml")) |
  Where-Object { $_ -notmatch 'epix2pro47mmsystem7preview' } |
  Set-Content (Join-Path $scratch "manifest.xml")
Push-Location $scratch
& "$sdk\bin\barrelbuild.bat" -w -o "out.barrel" -f monkey.jungle --override-devices-json "C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Devices" 2>&1 | Out-String | Write-Output
$code = $LASTEXITCODE
Pop-Location
"BARREL_EXIT=$code"
if ($code -eq 0 -and (Test-Path (Join-Path $scratch "out.barrel"))) {
  Copy-Item (Join-Path $scratch "out.barrel") $Out -Force
  if (Test-Path (Join-Path $scratch "out.barrel.debug.xml")) {
    Copy-Item (Join-Path $scratch "out.barrel.debug.xml") "$Out.debug.xml" -Force
  }
  $f = Get-Item $Out
  "ARTIFACT: $Out $($f.Length) octets"
} else {
  "NO ARTIFACT"
}
