# Bench build (stage E1 of the phase-5 campaign): this app, with the barrel's
# WIRE TRACE actually on, for a run against a real camera - the PC simulator
# bridged to the X5 over the desk Bluetooth, or a sideload to the watch.
#
# Two gates hold the trace shut, and both have to be lifted (this is the datum a
# first version of this script missed): the barrel's const LOG_FRAMES (BLEBarrel.mc
# "const LOG_FRAMES = false") prints the BYTES of an event, and the delegate's
# armWire() turns the events on at runtime ("[wire] <tag> #n ..."). No shipped
# source calls armWire - the trace is a bench instrument, not a feature - so this
# script works on copies and touches nothing that is versioned:
#
#   1. copy BLE Barrel to a scratch dir, flip LOG_FRAMES there; leave
#      LOG_KEEPALIVE at its shipped false - deliberately: the camera floods the
#      link with one 7-octet keepalive per second (docs/x5-protocol.md L42/L60)
#      and on the wrist that flood alone ate the whole ~90-line retention before
#      a scene could be pulled (E2 run 1, 13 nov., #347-#359: thirteen seconds).
#      A bench that wants those lines flips the constant in its own copy; the
#      watch build never will. The same copy also no longer carries the stray
#      unconditional [nf] print that predates ad993d5 - one content line per
#      notification, not two.
#   2. copy "OneR remote" (sources, manifest, resources - not bin, not test) to a
#      scratch app, and add the call bleDevice.armWire(); in Main.onStart, right
#      after bleDevice.open();
#   3. write a barrels.jungle inside the scratch app pointing at the copy of 1,
#      and build there.
#
#   usage: .\benchbuild.ps1                                  # 9.1.0, descentmk351mm (bench sim)
#          .\benchbuild.ps1 -Sdk 9.3.0 -Device epix2pro51mm  # sideload to the watch
#
# What the run answers: which frames were written and in what order, the answer of
# the authorization probe (the line tagged "auth probe": asked cmd=39, answer
# status=N), the ask/answer of the state and card asks, the write acks and the
# photo verdict - the things only the wire can say.
param(
  [string]$Src = "C:\Users\greg\git\Insta360-Remote-CIQ V1.0.0",
  [string]$Sdk = "9.1.0",
  [string]$Device = "descentmk351mm",
  [string]$Out = "",
  [switch]$NewAppId
)
$sdks = "C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Sdks"
$sdkPath = if ($Sdk -eq "9.3.0") { "$sdks\connectiq-sdk-win-9.3.0-2026-10-20-95888f262" }
           else { "$sdks\connectiq-sdk-win-9.1.0-2026-03-09-6a872a80b" }
$devkey = "C:\Users\greg\Documents\Default Project\Insta360 Remote\developer_key"
$app = Join-Path $Src "OneR remote"
$enc = New-Object System.Text.UTF8Encoding($false)
$flat = $Sdk -replace '\.', ''

# 1. the barrel, copied, LOG_FRAMES on. Read and written as text with an explicit
# UTF-8 (the file carries UTF-8 glyphs; the console's code page must not touch it).
$bblScratch = Join-Path $env:TEMP ("bench-barrel-" + $flat)
New-Item -ItemType Directory -Force -Path $bblScratch | Out-Null
foreach ($name in @("BLEBarrel.mc", "monkey.jungle", "manifest.xml")) {
  Copy-Item (Join-Path $Src ("BLE Barrel\" + $name)) (Join-Path $bblScratch $name) -Force
}
$bmcPath = Join-Path $bblScratch "BLEBarrel.mc"
$bmc = [System.IO.File]::ReadAllText($bmcPath, [System.Text.Encoding]::UTF8)
if (-not $bmc.Contains("const LOG_FRAMES = false;")) { "ARRET: la ligne LOG_FRAMES est introuvable - le barillet a change"; exit 2 }
$bmc = $bmc.Replace("const LOG_FRAMES = false;", "const LOG_FRAMES = true;")
[System.IO.File]::WriteAllText($bmcPath, $bmc, $enc)
"GATE 1: LOG_FRAMES = true (copie $bblScratch)"

# 2. the app, copied, calling armWire() at the site the link opens. The app copy
# carries no bin/ and no test/: this is the shipped app, not the unit-test host.
$appScratch = Join-Path $env:TEMP ("bench-app-" + $flat)
if (Test-Path $appScratch) { Remove-Item -Recurse -Force $appScratch }
New-Item -ItemType Directory -Force -Path $appScratch | Out-Null
foreach ($item in Get-ChildItem $app) {
  if ($item.Name -in @("bin", "test", ".vscode")) { continue }
  if ($item.Name -like "barrels*.jungle" -or $item.Name -like "manifest-test*") { continue }
  Copy-Item $item.FullName (Join-Path $appScratch $item.Name) -Recurse -Force
}
$mainPath = Join-Path $appScratch "source\Main.mc"
$main = [System.IO.File]::ReadAllText($mainPath, [System.Text.Encoding]::UTF8)
$anchor = "bleDevice.open();"
if (-not $main.Contains($anchor)) { "ARRET: le site d'ouverture du lien est introuvable dans Main.mc"; exit 2 }
$main = $main.Replace($anchor, $anchor + "`r`n`t`t// The bench's second gate (Insta360-Remote-CIQ-Build\benchbuild.ps1): without this"` +
                      "`r`n`t`t// call the events crossing the delegate are never printed.`r`n`t`tbleDevice.armWire();")
[System.IO.File]::WriteAllText($mainPath, $main, $enc)
if (-not ([System.IO.File]::ReadAllText($mainPath, [System.Text.Encoding]::UTF8)).Contains("armWire")) {
  "ARRET: armWire n'a pas ete insere"; exit 3
}
"GATE 2: bleDevice.armWire() insere dans Main.onStart (copie $appScratch)"

# 2b. GATE 3 (-NewAppId opt-in): the RENAMED copy. The SDK names uniqueIdentifier
# "unique for every app" and the camera keys its authorization on the identity the
# app emits in field 1 of frame 39 (E2 notes, 13 nov.) - so a different app id in
# the copied manifest is the one lever that GUARANTEES the prompt. The id lives in
# the copy's manifest only; the versioned tree is never touched. The display name
# is renamed too, so the simulator's widget list says which one is the probe.
if ($NewAppId) {
  $manPath = Join-Path $appScratch "manifest.xml"
  $man = [System.IO.File]::ReadAllText($manPath, [System.Text.Encoding]::UTF8)
  if (-not $man.Contains('id="38afa6370ef54b479430e96d2de3b323"')) { "ARRET: id d'app introuvable dans le manifest copie"; exit 2 }
  $man = $man.Replace('id="38afa6370ef54b479430e96d2de3b323"', 'id="9e7f3c2a1d5b4e6f8a0c7d9e2b4f6a1c"')
  [System.IO.File]::WriteAllText($manPath, $man, $enc)
  $strPath = Join-Path $appScratch "resources\strings.xml"
  $strs = [System.IO.File]::ReadAllText($strPath, [System.Text.Encoding]::UTF8)
  if (-not $strs.Contains('<string id="AppName">Insta360 Remote</string>')) { "ARRET: AppName introuvable dans la copie de strings.xml"; exit 2 }
  $strs = $strs.Replace('<string id="AppName">Insta360 Remote</string>', '<string id="AppName">Insta360 Probe</string>')
  [System.IO.File]::WriteAllText($strPath, $strs, $enc)
  "GATE 3: manifest de copie a nouvel id d'app + nom 'Insta360 Probe' ($appScratch)"
}

# 3. the jungle of the copy, then the build. Lines built as plain strings: an
# array literal holding a concatenation has been seen splitting one line into
# three, and the jungle parser then faults on the closing quote.
$jlines = @()
$jlines += '# Generated by Insta360-Remote-CIQ-Build\benchbuild.ps1 - scratch copy, not the tree.'
$blp = Join-Path $bblScratch "monkey.jungle"
$jlines += 'BLEBarrel = "' + $blp + '"'
$jlines += 'base.barrelPath = $(base.barrelPath);$(BLEBarrel)'
$jpath = Join-Path $appScratch "barrels.jungle"
[System.IO.File]::WriteAllLines($jpath, $jlines, $enc)
$back = [System.IO.File]::ReadAllLines($jpath)
if ($back.Count -ne 3 -or -not $back[1].Contains($blp)) { "ARRET: barrels.jungle mal ecrit"; $back | ForEach-Object { "  [" + $_ + "]" }; exit 4 }
"JUNGLE: $jpath -> $blp"
$prg = if ($Out -ne "") { $Out } elseif ($NewAppId) { "C:\Users\greg\git\Insta360-Remote-CIQ-Build\oneremote-probe-$flat.prg" } else { "C:\Users\greg\git\Insta360-Remote-CIQ-Build\oneremote-bench-$flat.prg" }
Push-Location $appScratch
$out = & "$sdkPath\bin\monkeyc.bat" -f "monkey.jungle;barrels.jungle" -d $Device -y $devkey -o $prg 2>&1
$code = $LASTEXITCODE
$out | Select-String -Pattern 'ERROR|SUCCESSFUL' | Select-Object -First 8
Pop-Location
"APP_EXIT=$code DEVICE=$Device SDK=$Sdk"
"PRG: $prg"
