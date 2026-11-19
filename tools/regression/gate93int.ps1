$int  = "C:\Users\greg\git\Insta360-Remote-CIQ V1.0.0\OneR remote"
$sdk  = "C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.3.0-2026-10-20-95888f262\bin\monkeyc.bat"
$key  = "C:\Users\greg\Documents\Default Project\Insta360 Remote\developer_key"
$d    = "C:\Users\greg\git\int-x5-build"
Push-Location $int
& $sdk -f "monkey.jungle;barrels.jungle" -d epix2pro51mm -y $key -o "$int\..\int93.prg" 2>&1 | Out-File -Encoding utf8 "$d\int-errors93.txt"
"INT93_EXIT=$LASTEXITCODE"
Pop-Location
function norm($p, $rp) {
  (Get-Content $p) | Where-Object { $_ -match "ERROR:" } |
    ForEach-Object { $_ -replace [regex]::Escape($rp), "@" } |
    ForEach-Object { $_.TrimEnd() } | Sort-Object
}
$a = norm "$d\base-errors93.txt" "C:\Users\greg\AppData\Local\Temp\opencode\int-base"
$b = norm "$d\int-errors93.txt" "C:\Users\greg\git\Insta360-Remote-CIQ V1.0.0"
$diff = Compare-Object $a $b
if ($diff) { $diff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" } }
else { "IDENTICAL93: $($a.Count) errors on both, none introduced" }
"COUNT base93=$($a.Count) int93=$($b.Count)"
