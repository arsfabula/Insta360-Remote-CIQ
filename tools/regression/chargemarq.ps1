# chargemarq.ps1 - pousse le PRG 1.0.0 de marqexpedition sur un simulateur
# propre et laisse la console monter : OOM ou pas, c'est la réponse demandée.
$sdkPath = "C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.1.0-2026-03-09-6a872a80b"
$prg = "C:\Users\greg\git\Insta360-Remote-CIQ V1.0.0\int.prg"   # construit a l'instant par gate91int (epix2) : non, reproduit pour marq ci-dessous
Push-Location "C:\Users\greg\git\Insta360-Remote-CIQ V1.0.0\OneR remote"
& "$sdkPath\bin\monkeyc.bat" -f "monkey.jungle;barrels.jungle" -d marqexpedition -y "C:\Users\greg\Documents\Default Project\Insta360 Remote\developer_key" -o "C:\Users\greg\git\Insta360-Remote-CIQ-Build\oneremote-marq910.prg" 2>&1 | Select-String -Pattern "WARNING|ERROR|exceeds"
"BUILD_EXIT=$LASTEXITCODE"
Pop-Location
Get-Process -Name "simulator" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
Start-Process -FilePath "$sdkPath\bin\simulator.exe" -WorkingDirectory "$sdkPath\bin"
Start-Sleep -Seconds 35
& "$sdkPath\bin\monkeydo.bat" "C:\Users\greg\git\Insta360-Remote-CIQ-Build\oneremote-marq910.prg" marqexpedition *>&1 |
  Select-Object -First 40
