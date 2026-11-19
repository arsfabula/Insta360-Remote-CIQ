# Chargement du variant intermediaire : epix2pro51mm (risque item 154) puis marqexpedition.
$sdkPath = "C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.3.0-2026-10-20-95888f262"
$T = "C:\Users\greg\AppData\Local\Temp\opencode"

function TimeBoxLoad($prg, $device, $label, $secs) {
    Get-Process -Name "simulator" -ErrorAction SilentlyContinue | Stop-Process -Force
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
    "--- $label ($device) ---"
    Get-Content $o -ErrorAction SilentlyContinue | Select-Object -First 20
    Get-Content $e -ErrorAction SilentlyContinue | Select-Object -First 6
}

TimeBoxLoad "$T\glance-mid\mid-epix2pro51mm.prg" "epix2pro51mm" "MID vue passive" 50
TimeBoxLoad "$T\glance-mid\mid-marqexpedition.prg" "marqexpedition" "MID vue passive" 50
