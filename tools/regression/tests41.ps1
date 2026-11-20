# run41 - suite unitaire, suite 67 (la liste ci-dessous fait foi: StatusTest 30,
# X6MenuTest 16, Ucd2Test 5, UiTest 16). Le chiffre de l'entete (62 a la tache 4:
# holdingDue 60 + 2 vecteurs de seuil) avait vieilli par rapport a la liste, lecon
# du 20 nov. Pilotage durci (lecon des faux
# echecs run36/38: le simulateur rendu
# disponible est attendu par l'epreuve, pas par un sommeil aveugle; java est tue
# avec simulator, cause des trois faux echecs du 17 nov.). Attendu : 67/67.
$sdkPath = "C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.1.0-2026-03-09-6a872a80b"
$flat = "910"
$int = "C:\Users\greg\git\Insta360-Remote-CIQ V1.0.0\OneR remote"
$key = "C:\Users\greg\Documents\Default Project\Insta360 Remote\developer_key"
$device = "descentmk351mm"
$log = "C:\Users\greg\git\Insta360-Remote-CIQ-Build\oneremote-tests-run41-longpress.log"
"" | Set-Content $log

# 1. hote de test (test.jungle), pas l'application livree. Le -t exige un -o.
$testprg = "C:\Users\greg\git\Insta360-Remote-CIQ-Build\oneremote-test-$flat.prg"
Push-Location $int
& "$sdkPath\bin\monkeyc.bat" -t -f "test.jungle;barrels.jungle" -d $device -y $key -o $testprg 2>&1 |
  Out-File -Append -Encoding utf8 $log
"HOST_EXIT=$LASTEXITCODE" | Add-Content $log
Pop-Location

# 2. simulateur frais, puis epreuve de disposabilite : la sonde monkeydo est
# relancee jusqu'a ce qu'elle passe (max 180 s). Un "Unable to connect" ici se
# voit en dix secondes au lieu d'une heure de chunk accroche. Les trois faux
# echecs du 17 nov. ont nomme la cause : tuer simulator.exe laisse survivre son
# JVM java enfant, qui squatte le port monkeydo. On tue les deux.
Get-Process -Name "simulator" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Name "java" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
Start-Process -FilePath "$sdkPath\bin\simulator.exe" -WorkingDirectory "$sdkPath\bin"
$ready = $false
for ($t = 1; $t -le 18; $t++) {
  Start-Sleep -Seconds 10
  $r = & "$sdkPath\bin\monkeydo.bat" $testprg $device /t evStopsAtEnds 2>&1 | Out-String
  if ($r -match "PASSED") { "READY probe passed after ~$($t*10) s" | Add-Content $log; $ready = $true; break }
}
if (-not $ready) { "SIMULATOR NEVER BECAME READY - run aborted" | Add-Content $log; exit 1 }

# 3. les 62 vecteurs, noms explicites, chunks de 15. Lecon du run41 du 17 nov. :
# apres les vecteurs UiTest a pleine vue (startupUiSmoke), le simulateur rend son
# corps en silence quelques secondes apres un chunk - sans 5e connexion a faire, le
# run40 ne l'avait jamais vu. Le pilote nomme le mort au lieu de le subir : chunk
# non rendu = simulator tue (lui et son JVM), relance, epreuve de disposabilite,
# reprise du chunk, trois tentatives.
function Ensure-Ready($prg) {
  Get-Process -Name "simulator" -ErrorAction SilentlyContinue | Stop-Process -Force
  Get-Process -Name "java" -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Seconds 3
  Start-Process -FilePath "$sdkPath\bin\simulator.exe" -WorkingDirectory "$sdkPath\bin"
  for ($t = 1; $t -le 18; $t++) {
    Start-Sleep -Seconds 10
    $r = & "$sdkPath\bin\monkeydo.bat" $prg $device /t evStopsAtEnds 2>&1 | Out-String
    if ($r -match "PASSED") { return $true }
  }
  return $false
}
function Invoke-Chunk($chunkList) {
  for ($try = 1; $try -le 3; $try++) {
    $out = & "$sdkPath\bin\monkeydo.bat" $testprg $device /t $chunkList 2>&1 | Out-String
    if ($out -notmatch "Unable to connect") { $out | Out-File -Append -Encoding utf8 $log; return $true }
    "chunk retry $try (simulator gone)" | Add-Content $log
    if (-not (Ensure-Ready $testprg)) { "SIMULATOR NEVER BECAME READY - chunk lost" | Add-Content $log; return $false }
  }
  return $false
}
$all = @(
  # StatusTest (30)
  'connectSyncAdoptsRecording','connectSyncUnknownStateStaysUnknown','connectSyncIdleKeepsWatchMode',
  'firstLinkBeatsThenCode200Answers','hexWitnessPrintsHighOctets','cameraSideModeChangeFollowed',
  'modeEchoGateOpensOnOwnEchoOnly','holdEndOpensSettingsGateWithoutEcho','batteryPushCutGivesPowerOnly',
  'batteryPushWholeGivesLevel','batteryLowClearedByExternalPower','cardPushState',
  'storageReplyCutGivesCardState','captureStatusPushDoesNotRestartRecording','settingWaitsForModeChange',
  'settingsFramesMatchCamera','photoAckThreeWayVerdicts','writeAckOkRefusalMarksDegraded',
  'disconnectRearmsAsksKeepsOneScan','levelsChainTableFallbackAndConfirm','forceMenuOrdersNewestFirstThenOtherOff',
  'modeKeepLoadAndPoseForTheLevel','asksArmAtTheLinkNotTheProfile','statusAnswerStopTailDoesNotRestart',
  'recordingFoundFromRestIsMarkedJoined','pureVideoStateTwentyFourCountsLikeRecording',
  'stopConfirmedByCameraPushCancelsTheStopRetry','exhaustedStopRetryNeverOverwritesObservedRest',
  'exhaustedStopRetryWithNoFactsRestoresRecording','exhaustedStartRetryKeepsFactsAndUndoesOptimistic',
  # X6MenuTest (16)
  'x6TableIsL2MinusBurst','x6ResTableIsLiteralInheritance','ucd2LegNamesOnlyStartStop','keepsUcd2OnlyAtX6Level',
  'dLegWrapsEveryLegacyFrameUnderDetectedX6','dForcedLevel3WrapsTheWholeLegacyFamily',
  'dForcedLevel3OptionWriteIsNotDroppedByTheSender','dStatusAskChangesEnvelopeWithTheRun',
  'dAsk15FrameMatchesTheReferenceCodec','dAskOnTheUcd2LegIsNotOwnedByTheWriteRetry',
  'dOptionFramesMatchTheReferenceCodec','dStatusAskRefusedUnderNamedX6','dOptionAnswerClosesItsRetryAndMovesNothing',
  'eClearForcingEndsTheCeilingDatum','eOptionAnswerKeepsAnotherWritesRetryArmed','eForcedDownOnNamedX6StillRefusesTheAsk',
  # Ucd2Test (5)
  'ucd2TxFramesMatchTheReferenceCodec','ucd2AnswerReadAtTheFirstTwentyNotAtTheTrailer',
  'ucd2OpenFrameYieldsAndOversizedDeclaredNeverWedges','ucd2LegacyAnswerReadWhileUcd2Armed',
  'ucd2OpenFrameDoesNotSwallowALegacyAnswer',
  # UiTest (16) - seuil + lieu de la decision courte, puis les trois defauts de la
  # page poussee nommes par le banc du 18 nov. (id, ecriture, BACK), puis la roue
  # au niveau 0 nommee par le rapport ERA du magasin (19 nov.)
  'evStopsAtEnds','otherRowsStillWrap','tapIsNotStartButKeyIs','startupWithLinkAsksArmed',
  'linkScheduleKeepsNearestDate','authSurfaceNamesTheCameraEdges','titleTapAreaCoversAllLines',
  'startupUiSmoke','screenTruthNamesTheAbsentCamera',
  'holdAtThresholdFires','holdJustUnderThresholdDoesNotFire','startPressWaitsForTheRelease',
  'settingsPageSelectStepsTheRowItsIdNames','settingsPageWriteCrossesAtTheSelect',
  'settingsPageBackStaysPureAndRetriesTheHeldWrite','modeWheelAtLevelZeroStaysPut'
)
"TOTAL VECTEURS: $($all.Count)" | Add-Content $log
for ($i = 0; $i -lt $all.Count; $i += 15) {
  $chunk = $all[$i..([Math]::Min($i+14, $all.Count-1))]
  "==CHUNK $i==" | Add-Content $log
  Invoke-Chunk $chunk | Out-Null
  Start-Sleep -Seconds 8
}
"---- bilan ----" | Add-Content $log
Get-Content $log | Select-String -Pattern "Ran \d+ tests|PASSED|FAILED|ERROR|Unable to connect|Unable to resolve|HOST_EXIT|TOTAL VECTEURS|READY probe|NEVER" |
  ForEach-Object { $_.Line.Trim() }
