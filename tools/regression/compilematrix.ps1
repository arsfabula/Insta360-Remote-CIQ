# compilematrix.ps1 - build the shipped app for EVERY product of the shipped
# manifest, and report per product: compiled, or the first compiler error.
# This is the mechanical proof behind "does the code work on all the watches the
# manifest names": not one run per watch (impossible), but one compilation per
# watch (automatic), plus runs only on class representatives (see
# tools/device_matrix.py for the classes).
#
# usage: .\compilematrix.ps1 [-Sdk 9.3.0] [-Only fenix6,edge1040]
# Output: a table on stdout, a CSV next to this script. Exit 0 even when devices
# fail: the point is the table, not the verdict; read the FAIL lines.
param(
  [string]$Sdk = "9.3.0",
  [string[]]$Only = @()
)
$flat = $Sdk -replace '\.', ''
$sdks = "C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Sdks"
$sdk = if ($Sdk -eq "9.3.0") { "$sdks\connectiq-sdk-win-9.3.0-2026-10-20-95888f262" }
       else { "$sdks\connectiq-sdk-win-9.1.0-2026-03-09-6a872a80b" }
$repo = "C:\Users\greg\git\Insta360-Remote-CIQ V1.0.0"
$key = "C:\Users\greg\Documents\Default Project\Insta360 Remote\developer_key"
$manifestXml = Get-Content "$repo\OneR remote\manifest.xml" -Raw
$products = [regex]::Matches($manifestXml, '<iq:product id="([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value }
if ($Only.Count -gt 0) { $products = $Only }
$csv = Join-Path $PSScriptRoot "compilematrix-$flat.csv"
"device,sdk,exit,status,detail" | Set-Content $csv -Encoding UTF8
$tmp = Join-Path $env:TEMP "compilematrix.prg"
Push-Location "$repo\OneR remote"
$i = 0
foreach ($dev in $products) {
  $i++
  $err = & "$sdk\bin\monkeyc.bat" -f "monkey.jungle;barrels.jungle" -d $dev -y $key -o $tmp 2>&1 | Out-String
  $exit = $LASTEXITCODE
  $first = ($err -split "`r?`n" | Where-Object { $_ -match "ERROR" } | Select-Object -First 1) -replace '\s+', ' '
  $status = if ($exit -eq 0) { "OK" } else { "FAIL" }
  if ($exit -eq 0) { $first = "" }
  "$dev,$flat,$exit,$status,`"$($first -replace '"','""')`"" | Add-Content $csv -Encoding UTF8
  Write-Output ("[{0}/{1}] {2,-22} {3} {4}" -f $i, $products.Count, $dev, $status, $first)
}
Pop-Location
$fails = (Import-Csv $csv | Where-Object { $_.status -eq "FAIL" }).Count
Write-Output ("MATRIX: {0} produits, {1} OK, {2} FAIL -> {3}" -f $products.Count, ($products.Count - $fails), $fails, $csv)
