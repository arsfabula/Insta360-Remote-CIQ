param([string]$prg, [string]$device, [int]$secs = 90)
# Chargement time-boxe d'un PRG sur un simulateur frais; capture stdout+stderr de monkeydo.
$sdkPath = "C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.3.0-2026-10-20-95888f262"
Get-Process -Name "simulator" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Name "java" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
Start-Process -FilePath "$sdkPath\bin\simulator.exe" -WorkingDirectory "$sdkPath\bin"
Start-Sleep -Seconds 35
$o = "$env:TEMP\opencode\load-out.txt"; $e = "$env:TEMP\opencode\load-err.txt"
Remove-Item $o, $e -ErrorAction SilentlyContinue
$p = Start-Process -FilePath "$sdkPath\bin\monkeydo.bat" -ArgumentList "`"$prg`"",$device `
    -RedirectStandardOutput $o -RedirectStandardError $e -PassThru -WindowStyle Hidden
Start-Sleep -Seconds $secs
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Get-Process -Name "simulator" -ErrorAction SilentlyContinue | Stop-Process -Force
"--- $device <- $(Split-Path $prg -Leaf), ${secs}s ---"
Get-Content $o -ErrorAction SilentlyContinue | Select-Object -First 30
Get-Content $e -ErrorAction SilentlyContinue | Select-Object -First 8
