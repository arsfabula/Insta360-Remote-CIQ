// ============================================================================
// Insta360 Garmin App - Structural reconstruction (P-code level)
// Source: insta360-epixpro51.prg (CIQ 5.1.1, App type, epix Pro Gen 2)
// App ID: 18293a9e-d16f-42d7-ab90-73a47510f46e
// Version: 4.27.2
//
// WARNING: This is a STRUCTURAL SKELETON, not compilable Monkey C.
// - Method bodies are NOT reconstructed (P-code -> Monkey C requires Ghidra).
// - Method names are symbol IDs (no Symbols section in this build).
// - Class names come from the Data-section string pool.
// - Command byte arrays (cmd*) are in BLE Barrel/BLEBarrel.mc.
//
// Full decompilation requires:
//   1. Ghidra 12.2+ with the GhidraGarminApp extension (built from source).
//   2. Uncomment the language definition in data/languages/garminvm.ldefs.
//   3. Compile the SLEIGH spec (garminvm.sinc -> garminvm.sla).
//   4. Import the .prg and run the decompiler on each method.
//   5. Manually translate pseudocode to Monkey C.
//
// See HANDOFF.md for the full protocol extraction results.
// ============================================================================

import Toybox.Lang;
import Toybox.System;
import Toybox.BluetoothLowEnergy;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Timer;
import Toybox.Position;

// ============================================================================
// String constants (from Data section string pool, 521 entries)
// ============================================================================
// GATT service/characteristics:
//   0000BE80-0000-1000-8000-00805F9B34FB (service)
//   (write char BE81, notify char BE82, read char BE83)
//
// Protobuf message names (54):
//   BatteryStatus, ButtonFollowOptions, ButtonPressOptions, CameraCaptureStatus,
//   CaptureStatus, ChargeboxConnectedStatus, CheckAuthorization, CheckAuthorizationResp,
//   ExposureOptions, ExtraMetadata, GetActiveSensorDevice, GetActiveSensorDeviceResp,
//   GetCurrentCaptureStatusResp, GetOptions, GetOptionsResp, GetPhotographyOptions,
//   GetPhotographyOptionsResp, GyroFilterConfig, GyroInfo, IntervalRecInfo,
//   NotificationAuthorizationResult, NotificationBatteryUpdate, NotificationCaptureStopped,
//   NotificationCardUpdate, NotifyCameraSubMode, Options, Photo, PhotographyOptions,
//   Sensor, SetActiveSensorDevice, SetActiveSensorDeviceResp, SetKeyTimePoint,
//   SetKeyTimePointResp, SetOptions, SetOptionsResp, SetPhotographyOptions,
//   SetPhotographyOptionsResp, StartCapture, StartCaptureResp, StartTimelapse,
//   StartTimelapseResp, StopCapture, StopCaptureResp, StopTimelapse, StopTimelapseResp,
//   StorageState, TakePicture, TakePictureResponse, TempState, Video, WifiChannelList,
//   WifiInfo, WindowCropInfo
//
// Camera option keys (for Capacites Barrel):
//   assistive_grid_enable, dark_eis_enable, dark_eis_enable_global, double_click,
//   double_zoom_enable, enableInternalFlowstate, enableInternalSplicing,
//   flowstate_base_enable, flowstate_horizon_enable, freeframe_grid_enable,
//   long_battery_mode_enabled, mctf_enable, metering_enable, metering_enable_global,
//   preview_mctf_enable, preview_sport_mode_enable, quick_capture, sport_mode_enable,
//   video_flowstate_base_enable, cache_capture_enable, shutdown_double_click
//   box_bt_version, box_ota_pkg_version, box_version, bt_remote_version,
//   go3_version, ota_pkg_version, passwd_version, isInstaPanoEnabled
//
// App classes:
//   Insta360GarminApp, Insta360GarminAuthorizationDelegate,
//   Insta360GarminChronographSearchView, Insta360GarminConnectMenuDelegate,
//   Insta360GarminConnnectingDelegate, Insta360GarminSearchDelegate,
//   Insta360GarminSearchView
// ============================================================================

// Notification codes handled by the official app (dispatch @0x3e07):
//   0x2003 (8195)  - X5_BATTERY_NOTIF (battery changed alert)
//   0x2006 (8198)  - X5_STORAGE_NOTIF (storage changed alert)
//   0x2009 (8201)  - UNKNOWN (new, not in barrel)
//   0x2010 (8208)  - X5_CAPTURE_STATUS_NOTIF (capture state + time)
//   0x2011 (8209)  - UNKNOWN (new, not in barrel)
//   0x2016 (8214)  - UNKNOWN (new, not in barrel)
//   0x2053 (8275)  - X5_SUB_MODE_NOTIF (sub-mode)
//   0x2063 (8291)  - UNKNOWN (new, not in barrel)
//   0x2065 (8293)  - UNKNOWN (new, not in barrel)
//   0x2017 (8215)  - capture status push (observed dynamically)
//   0x2040 (8256)  - X5_RECORD_STATE_NOTIF (record state)
//   0x2062 (8290)  - UNKNOWN (38 bytes, large protobuf body, observed dynamically)

// ============================================================================
// Class structure (236 classes, 1045 methods total)
// ============================================================================

// Class @0x2346 (main protocol class, 21 methods, module=insta360garminapp)
// Methods (symbol -> code offset):
//   242 -> 0xcd17
//   694 -> 0xd30c
//   698 -> 0xd040
//   699 -> 0xcb71
//   700 -> 0xd2af
//   701 -> 0xcbe5
//   702 -> 0xcf9a
//   703 -> 0xd4f4
//   704 -> 0xccfc
//   705 -> 0xcdc2
//   706 -> 0xd4a1
//   710 -> 0xd02a
//   713 -> 0xce1b
//   714 -> 0xd123  (data transform, 6 aputv, 32 ipush)
//   716 -> 0xcd5e
//   717 -> 0xcc2f
//   718 -> 0xd075
//   719 -> 0xd0c8
//   8388632 -> 0x1571  (init)
//   8391260 -> 0xd057
//   8391263 -> 0xce60
//
// Class @0x3835 (56 methods, likely UI/view layer)
// Class @0x0a7b (40 methods, notification handler @0x3e07)
// Class @0x1040 (22 methods)
// Class @0x1aec (22 methods)
// Class @0x14ef (21 methods)
// Class @0x41a1 (20 methods, module=24)
// Class @0x4bc1 (19 methods)
// Class @0x3196 (17 methods)
// Class @0x4a30 (16 methods, byte-array transforms @0x166a1, @0x16c85)
// Class @0x357f (14 methods)
// ... 226 more classes

// ============================================================================
// Command IDs (from BLE Barrel/BLEBarrel.mc, validated on real X5)
// ============================================================================
// 0x03 - photo capture / settings (cmdSetPhoto, cmdSetInterval, cmdSetNightShot)
// 0x04 - start recording (cmdStartRec)
// 0x05 - stop recording (cmdStopRec)
// 0x07 - photo sub-modes (burst, interval, etc.)
// 0x08 - get battery/storage (cmdGetBatStor) -> reply code 200
// 0x09 - video mode settings (cmdSet5k30, cmdSet4k30, etc.)
// 0x0f - apply settings (cmdApply)
// 0x16 - start timelapse (cmdStartStarlapse)
// 0x17 - stop timelapse (cmdStopTimelapse)
// 0x3c - highlight / track that (cmdHighlight, cmdTrackThat)

// ============================================================================
// State variables (from BLE Barrel/BLEBarrel.mc)
// ============================================================================
// x5BatteryLevel, x5BatteryScale, x5CardState, x5FreeSpace, x5TotalSpace
// x5CaptureState, x5CaptureTime, x5ReplyCode
// x5StateQuerySeq (sequence for cmdGetBatStor reply matching)
// x5StateQuerySent (flag: query armed once per session)

// ============================================================================
// Note: Full method body reconstruction requires Ghidra + GhidraGarminApp.
// The P-code disassembly is in tools/prg_disasm.py output (disasm.txt).
// The protocol analysis is in HANDOFF.md.
// ============================================================================
EOF
echo "written"