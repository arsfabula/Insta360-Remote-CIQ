# benchrun - etage E1 de la campagne Phase 5: construit le PRG de banc (trace de
# fil activee dans des copies), demarre le simulateur 9.1.0, l'appareil descendmk351mm,
# envoie le PRG, et surtout COPIE LA CONSOLE DE L'APP dans un fichier: le stdout de
# monkeydo est le journal ou se lisent les [scan]/[det]/[mdl]/[lvl]/[wire]/[auth].
#
#   interaction de l'utilisateur, apres le message "PRET:" :
#     1. dans la fenetre du simulateur, demarrer le widget (montre -> widgets)
#     2. allumer le X5 a portee du Bluetooth du poste; laisser la montre se connecter
#     3. faire le protocole voulu (changement de mode, reglages, photo, power off)
#     4. revenir ici et Ctrl+C: le log est imprime, et c'est ce fichier qu'on relit
#
# Ce script ne touche JAMAIS l'arbre versionne: le portillon du const (LOG_FRAMES)
# et l'appel runtime armWire() ne vivent que dans les copies faites par benchbuild.ps1.
# Le simulateur doit etre relance par ce script: la passerelle BLE du simulateur
# n'est garantie qu'apres un demarrage propre (regle vue en phase 5: monkeydo sans
# simulateur vivant repond "Unable to connect to simulator").
param(
  [string]$Sdk = "9.1.0",
  [string]$Device = "descentmk351mm",
  [switch]$NewAppId
)
$flat = $Sdk -replace '\.', ''
$sdks = "C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Sdks"
$sdkPath = if ($Sdk -eq "9.3.0") { "$sdks\connectiq-sdk-win-9.3.0-2026-10-20-95888f262" }
           else { "$sdks\connectiq-sdk-win-9.1.0-2026-03-09-6a872a80b" }
$prg = if ($NewAppId) { "C:\Users\greg\git\int-x5-build\oneremote-probe-$flat.prg" }
       else { "C:\Users\greg\git\int-x5-build\oneremote-bench-$flat.prg" }

# 1. le PRG de banc (benchbuild.ps1 fait les copies et leve les deux portillons;
# -NewAppId leve le troisieme: le manifest de copie recoit un autre id d'app,
# l'identite que la camera agree - c'est le tir qui rouvre le prompt, cf. la
# note "LE MECANISME DU PROMPT EST NOMME" au plan).
if ($NewAppId) {
  & "C:\Users\greg\git\int-x5-build\benchbuild.ps1" -Sdk $Sdk -Device $Device -NewAppId |
    Select-String -Pattern 'GATE|JUNGLE|APP_EXIT|ERROR|SUCCESSFUL|PRG' | ForEach-Object { $_.Line.Trim() }
} else {
  & "C:\Users\greg\git\int-x5-build\benchbuild.ps1" -Sdk $Sdk -Device $Device |
    Select-String -Pattern 'GATE|JUNGLE|APP_EXIT|ERROR|SUCCESSFUL|PRG' | ForEach-Object { $_.Line.Trim() }
}
$built = Get-Item $prg -ErrorAction SilentlyContinue
if (-not $built) { "ARRET: pas de PRG de banc ($prg)"; exit 1 }
"PRG: $($built.Length) o, $($_.LastWriteTime)"

# 2. un simulateur qui démarre proprement, l'appareil demande existe a l'etat
Get-Process -Name "simulator" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
Start-Process -FilePath "$sdkPath\bin\simulator.exe" -WorkingDirectory "$sdkPath\bin"
Start-Sleep -Seconds 35

# 3. envoi + console capturee. Pas de /t: c'est l'app livree qui tourne, pas la suite.
# monkeydo sans /t pousse l'app et reste attache a la session: la console de l'app
# defile dans ce terminal ET dans le log. Ctrl+C ici ferme la session de lecture du
# log; le simulateur reste ouvert pour continuer a observer la montre.
$log = "C:\Users\greg\git\int-x5-build\bench-run-$(if ($NewAppId) { 'probe-' })$flat-$(Get-Date -Format 'HHmmss').log"
"LOG: $log"
"PRET: fenetre du simulateur -> demarrer le widget, allumer le X5. Ctrl+C ici a la fin."
& "$sdkPath\bin\monkeydo.bat" $prg $Device *>&1 | ForEach-Object {
  $_.ToString() | Tee-Object -FilePath $log
}
