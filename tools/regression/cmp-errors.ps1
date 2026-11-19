# Compares two monkeyc error logs after stripping the build-tree prefix.
param()
$d = "C:\Users\greg\git\Insta360-Remote-CIQ-Build"
function norm($p, $rp) {
  (Get-Content $p) | Where-Object { $_ -match "ERROR:" } |
    ForEach-Object { $_ -replace [regex]::Escape($rp), "@".PadRight(1) } |
    ForEach-Object { $_.TrimEnd() } | Sort-Object
}
$a = norm "$d\base-errors.txt" "C:\Users\greg\AppData\Local\Temp\opencode\int-base"
$b = norm "$d\int-errors.txt" "C:\Users\greg\git\Insta360-Remote-CIQ V1.0.0"
$diff = Compare-Object $a $b
if ($diff) { $diff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" } }
else { "IDENTICAL: $($a.Count) base errors, none introduced" }
"COUNT base=$($a.Count) int=$($b.Count)"
