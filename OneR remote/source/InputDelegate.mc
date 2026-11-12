using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.Position;
using Toybox.Lang;
using BLEBarrel;
using Levels;

// What the application knows of the camera is what the camera reported
// (bleDevice.peek*, the accessors live in the class BleDevice), never what
// it supposes. Nothing is asked of the camera:
// reading a state costs a peek, not a GET.

// An entry of the capability model becomes a frame of the protocol barrel
// here, and only here. That is what keeps the two barrels apart: the protocol
// barrel knows no mask, no label, no model of camera, and this application
// never asks it for a value. null means this camera has no frame measured over
// BLE for that entry, so the entry is not offered and nothing is written
// (a setting whose effect is not verified stays out of the menu, EF-26).
function entryFrame(id as Lang.String) as Lang.ByteArray or Null {
    // Instrumentation of the single-axis protocol (CdC 11.4, axes S-2 and S-3
    // only). One print per call, for every call site: the menu build and the
    // selection both answer through here, so the log shows whether the resolver
    // is deterministic across the two sites, and how many bytes it handed.
    var f = null;
    switch (id) {
        // 360 video resolutions: the value of field record_resolution (option
        // 31) inside VIDEO_NORMAL. Each frame also writes FunctionMode 7, so
        // choosing one returns the camera to that family.
        case "r0": f = BLEBarrel.cmdSet4k30; break;
        case "r10": f = BLEBarrel.cmdSet5k30; break;
        case "r12": f = BLEBarrel.cmdSet4k50; break;
        case "r19": f = BLEBarrel.cmdSet5k25; break;
        case "r20": f = BLEBarrel.cmdSet5k24; break;
        case "r167": f = BLEBarrel.cmdSet8k30; break;
        // Video family modes: the value of field VIDEO_SUB_MODE (option 41) inside
        // SetOptions code 7. The eight entries are the mask of the capability model
        // (Starlapse cleared by the decision of CdC item 100);
        // each frame carries the MODE only, no resolution, because record_resolution
        // (option 31) is pilotable inside VIDEO_NORMAL only (rea/11 §5.3, measured on
        // the eight other modes: the field stays fixed on a dead value).
        case "v0": f = BLEBarrel.cmdSetVideoSubNormal; break;
        case "v1": f = BLEBarrel.cmdSetVideoSubBulletTime; break;
        case "v2": f = BLEBarrel.cmdSetVideoSubTimelapse; break;
        case "v4": f = BLEBarrel.cmdSetVideoSubTimeShift; break;
        case "v6": f = BLEBarrel.cmdSetVideoSubLoop; break;
        case "v11": f = BLEBarrel.cmdSetVideoSubPure; break;
        // No route for v12 (Starlapse): the entry is not offered (CdC item 100,
        // a decision of the app). `cmdSetVideoSubStarlapse` and `cmdStartStarlapse`
        // stay declared in the barrel as the datum of the rungs S-17 and S-23, never
        // chosen; the mode 12 itself stays a measured value in annexe B.1 of the CdC.
        case "v14": f = BLEBarrel.cmdSetVideoSubRoad; break;
        case "v15": f = BLEBarrel.cmdSetVideoSubInstaFrame; break;
        // Photo sub-modes: the value of field 1 of the same command. Interval
        // rides the Timelapse shape of the start and stop commands, patched
        // below where the entry is chosen.
        // Separation measured on the bench (CdC item 48, two runs of the same
        // session): a TAKE_PICTURE crosses and is refused while the camera is in
        // the video family (no 8208, no photo), and the same 16-o frame fires
        // when the camera already sits in the photo family. So a photo entry
        // writes the MODE (SET_OPTIONS PHOTO_SUB_MODE), and the capture belongs
        // to the start press, never to the menu selection.
        case "p0": f = BLEBarrel.cmdSetPhotoSubNormal; break; // CdC item 54: the p0 selection poses the MODE (photo sub-mode Normal), the capture belongs to the start press (the mixup of the item 48, half p0)
        case "p2": f = BLEBarrel.cmdSetPhotoSubInterval; break; // CdC item 60: the p2 selection poses the MODE (photo sub-mode Interval); the legacy cmdSetInterval, a 63-byte frame of command 3, was refused by the camera (no change on the screen). The capture of this entry belongs to the press, and the Timelapse patch of cmdStartRec and cmdStopRec stays with that press half, not with the mode write.
        case "p3": f = BLEBarrel.cmdSetPhotoSubBurst; break;
        // The keys of the level chain (Levels.mc): an entry of a level the
        // chain never measured over BLE is named by its key, never by a
        // protocol number (rea/11: the numbering of a cell is not a protocol
        // value, and the numbering is not a scale across models). This
        // function is the single site that turns an id or a key into a frame:
        // the ids of the X5 line and the keys of the levels below answer
        // here, never at two resolvers that could disagree (note 8 of the
        // CdC: one datum, one site).
        case "TimeLapse": f = BLEBarrel.cmdSetTL; break;
        case "BulletTime": f = BLEBarrel.cmdSetBullet; break;
        case "Photo": f = BLEBarrel.cmdSetPhoto; break;
        case "PhotoHDR": f = BLEBarrel.cmdSetPhotoHDR; break;
        case "PhotoInterval": f = BLEBarrel.cmdSetInterval; break;
        case "PhotoBurst": f = BLEBarrel.cmdSetPhotoBurst; break;
        case "NightShot": f = BLEBarrel.cmdSetNightShot; break;
        case "HDRVideo": f = BLEBarrel.cmdSetHDR; break;
        case "3k100": f = BLEBarrel.cmdSet3k100; break;
        case "8k30": f = BLEBarrel.cmdSet8k30; break;
        case "5k30": f = BLEBarrel.cmdSet5k30; break;
        case "5k25": f = BLEBarrel.cmdSet5k25; break;
        case "5k24": f = BLEBarrel.cmdSet5k24; break;
        case "4k30": f = BLEBarrel.cmdSet4k30; break;
        case "4k50": f = BLEBarrel.cmdSet4k50; break;
        default:
            // Timelapse and Bullet Time ride function_mode 2 and 4, TimeShift,
            // Loop, PureVideo, Starlapse, Road Mode and InstaFrame have no
            // frame of this barrel, HDR Video and 3K 100 are refused values.
            // No verified frame, so no offer and no phantom write.
            f = null;
            break;
    }
    if (f == null) {
        Sys.println("[res] " + id + " -> none");
    } else {
        Sys.println("[res] " + id + " -> " + f.size().toString() + " o");
    }

    // The value must leave the function. A function that declares a return type
    // and returns nothing compiles and answers null. The print of the axis S-3 lives
    // inside the resolver and says what the local variable holds, never what the
    // call site received. The tell of the axis S-2 is at the call site: the counters
    // of the build (addedRes, addedPhoto) and the line [frame] of the selection.
    return f;
}

// A value of the observer as text. The observer answer only through
// notifications, never through a read of the camera (EF-20), and null means
// the camera never reported that value: an unknown value seen on the camera
// stays visible and reusable, never replaced by a guess.
function obsText(v) as Lang.String {
    if (v == null) {
        return "none";
    }
    return v.toString();
}

// The notification codes the camera pushed during the run, and how many times
// each one crossed. An action of the camera is proved by a notification the
// camera pushed (EF-22), never by a reply, so this list is the tell of the
// action axis. Emptiness is asked by length, never by == on a String (note 9).
function codesText() as Lang.String {
    var codes = bleDevice.peekSeenCodes();
    if (codes == null) {
        return "none";
    }
    var out = "";
    var i = 0;
    while (i < codes.size()) {
        if (i > 0) {
            out += " ";
        }
        out += codes[i].toString();
        i += 1;
    }
    if (out.length() == 0) {
        return "none";
    }
    return out;
}

// The resolver entryFrame() above answers the ids of the X5 line and the keys
// of the level chain at one site. refFrame() used to be a second switch of
// frames for the keys of the capability tables; the chain of Levels.mc names a
// doc entry by its key and the same resolver answers it, so no second table of
// frames can disagree with the first (note 8 of the CdC). The keys are the
// semantic names the reference app speaks (TimeLapse, BulletTime, 5k30), never
// a protocol number (rea/11: the numbering is not a scale across models;
// provenance of the frames: salvaged/BLEBarrel-1004.mc, :1012, :1022).

function addLevelItems(menu, level) as Void {
    // The menu of the level in force: the rows of the chain of Levels.mc,
    // added in the order of the table. No mask, no model index, no measured
    // face: the chain is the menu of the level, and a doc row is added like a
    // measured row — its frame is answered, or refused, at the selection.
    // Nothing here filters on a state read on the camera (EF-23, EF-25): the
    // peek stays as the datum of the family at the build site, never as a gate.
    //
    // The arrangement is the decision of the table, "mode first, definition
    // under" (CdC item 74): the resolutions left the main menu for a Menu2 of
    // their own (CdC item 107), opened by the selection of the row whose sub
    // flag answers 1, and the write of the family lands before the submenu is
    // pushed. The measured rule behind the place: record_resolution is
    // pilotable inside VIDEO_NORMAL only (rea/11 §5.3, the eight other
    // sub-modes were read with the field fixed), so the submenu hangs under
    // that entry and only there.
    var fam = bleDevice.peekFuncMode();

    // Axis S-0 of the single-axis protocol (CdC 11.4): what the build of the menu
    // puts on the screen. One line per entry handed to the menu, and one line of
    // counters. Nothing here reads the screen: the counters answer the question
    // whether an entry that is offered is an entry that can be selected.
    var addedRes = 0;
    var addedPhoto = 0;
    var addedVideo = 0;
    Sys.println("[fam] level=" + obsText(level) + " mode=" + obsText(fam));
    // Axis S-6, arrival window at the build site. The build of the menu runs at
    // every opening of the menu, and not only after a completed selection, so the
    // opening that follows a write gives that write its arrival window without
    // asking the user for a second selection. Same counters, read at a later
    // moment of the same boundary, notification -> observer.
    Sys.println("[obs3] n2065=" + bleDevice.peekCodeCount(0x2065).toString()
        + " n2053=" + bleDevice.peekCodeCount(0x2053).toString()
        + " notif=" + bleDevice.peekNotifCount().toString()
        + " declared=" + bleDevice.peekNotifDeclared().toString()
        + " arrived=" + bleDevice.peekNotifArrived().toString()
        + " cut=" + bleDevice.peekNotifTruncated().toString()
        + " hexLen=" + bleDevice.peekNotifHex().length().toString());
    // Axis S-6 of an action: the codes the camera pushed during the run. A photo
    // mode is proved by a capture notification (8208 = 0x2010), a video mode by
    // a record state (8256 = 0x2040). 8215 = 0x2017 is the periodic notification
    // with an empty body that arrives at the cold start. A reply never stands here.
    Sys.println("[obs4] codes=" + codesText()
        + " n8208=" + bleDevice.peekCodeCount(0x2010).toString()
        + " n8256=" + bleDevice.peekCodeCount(0x2040).toString());
// Axis S-6, the frames the camera sent during the run, replies included.
// The observer keeps only the LAST frame that crossed (declared/arrived),
// so a run which writes two frames cannot say which reply is which. This
// counter answers how many frames crossed at all: it is the datum which
// separates one reply per write from one reply for the whole burst.
Sys.println("[obs5] x5seen=" + bleDevice.peekX5Seen().toString());

    var rows = Levels.rowsMain(level);
    var row = null;
    var id = "";
    var label = "";
    var i = 0;
    while (i < rows.size()) {
        row = rows[i];
        id = row[Levels.RID];
        label = row[Levels.RLB];
        if (row[Levels.RFAM].equals("v")) {
            Sys.println("[add] video " + id + " " + label);
            addedVideo += 1;
        } else if (row[Levels.RFAM].equals("p")) {
            Sys.println("[add] photo " + id + " " + label);
            addedPhoto += 1;
        } else {
            // The UCD2 sentinel row of the replacing level: the write is not a
            // frame of the chain, the switch of ids arms the envelope.
            Sys.println("[add] ucd2 " + id + " " + label);
        }
        menu.addItem(new Ui.MenuItem(label, "", id, {}));
        i += 1;
    }
    Sys.println("[menu] video=" + obsText(addedVideo) + " res=" + obsText(addedRes) + " photo=" + obsText(addedPhoto));
}

function addLevelResItems(menu, level) as Void {
    // The resolution submenu of the level: the rows of the res chain, in the
    // order of the table — the order is a decision of the app (the protocol
    // numbers of the res rows carry no order: 0 is 4K 30, 167 is 8K 30), and
    // the table is where that decision lives now. The tag of the adds stays
    // [add2], so the adds of the sub-menu and the adds of the main menu
    // answer apart at the same boundary.
    var rows = Levels.rowsRes(level);
    var row = null;
    var i = 0;
    var addedRes = 0;
    while (i < rows.size()) {
        row = rows[i];
        Sys.println("[add2] res " + row[Levels.RID] + " " + row[Levels.RLB]);
        addedRes += 1;
        menu.addItem(new Ui.MenuItem(row[Levels.RLB], "", row[Levels.RID], {}));
        i += 1;
    }

    // The shape tell of the sub-menu, one line per entry, in the order the entries
    // are handed to it. A Menu2 answers no item count and documents no limit, so
    // the walk stops at the first Null and 40 is the bound of the walk alone
    // (note 14 of the CdC: a reference is not a datum).
    var walk = 0;
    var entry = null;
    while (walk < 40) {
        entry = menu.getItem(walk);
        if (entry == null) {
            break;
        }
        Sys.println("[sub] " + walk + " id=" + obsText(entry.getId()) + " label=" + obsText(entry.getLabel()));
        walk += 1;
    }
    Sys.println("[sub] n=" + obsText(walk) + " res=" + obsText(addedRes));
}

function addMenuLevelItems(menu) as Void {
    // Axis model, the choices of the submenu of MenuLevel: one choice per model
    // of the level chain, plus the off choice that gives the detected model back.
    // The choice carries a model name, never a frame and never a level number:
    // the forcing is applied at the selection of the choice, which is where the
    // datum of the run changes, and the level of a model answers the table of
    // the chain at the index of its name, one datum.
    var n = 0;
    while (n < Levels.models.size()) {
        menu.addItem(new Ui.MenuItem(Levels.models[n], "", "force" + Levels.models[n], {}));
        n += 1;
    }
    menu.addItem(new Ui.MenuItem("off", "", "forceoff", {}));
}




class InputDelegate extends Ui.BehaviorDelegate {
//	hidden var bleDevice;
	var photoHeader = new [0]b;
	var photoFiller = new [0]b;

    function initialize(device) {
        BehaviorDelegate.initialize();
        bleDevice = device;
    }

	// Capture Start / Stop button event
    function onSelect() {
 //   	var key = Ui.KeyEvent.getKey();
		var actionMenu = new Ui.Menu2({:title=>"Action"});
        actionMenu.addItem(new Ui.MenuItem("Stop","","Stop",{}));
        actionMenu.addItem(new Ui.MenuItem("Highlight","","Highlight",{}));
        actionMenu.addItem(new Ui.MenuItem("Track","","Track",{}));
//        actionMenu.addItem(new Ui.ToggleMenuItem("Lock","","Lock",locked,{}));

//  System.println("[input] Key "+key);
//        if (key == KEY_ENTER) {
            if (BLEBarrel.recState == BLEBarrel.stateStopRec) {
            	BLEBarrel.recState = BLEBarrel.stateStarting;
            	BLEBarrel.mMessage = "Starting...";
            	WatchUi.requestUpdate();
            	if (BLEBarrel.videoMode && !BLEBarrel.starlapseStartMode) { // CdC item 95: the datum of the rung S-24 (the echoes of a Starlapse write carry the option ids 30 and 40 of the photo family) moves the leg of the press, not the leg of the mode write (that one keeps its green reading at `[vw]` and at the tell of S-17).
            		// The camera drops a start that immediately follows a mode+apply
            		// whose mode did not actually change (no 0x65 confirmation), which
            		// is always the case here since currentMode is the persisted mode.
            		// A bare start records in the camera's current (already applied)
            		// mode - same as the working DF "Default Video" path.
            		// CdC item 91, axis S-23: the frame of the start of the video family has never
            		// been printed at the site that sends it, so the tell of this rung adds the pair
            		// the resolver and the stop already use, the shape (declared length at 0..3, the
            		// command at byte 7, the body length) and the content (the bytes). Printed BEFORE
            		// the send, so a negative names the frame that leaves and never an absence of a
            		// line (criterion 14). Instrumentation only: the array stays as declared at
            		// barrel:164 until a measured datum moves it. The watchdog of the barrel re-sends
            		// this same array RETRY_MAX times, so a count of [scan] press lines counts
            		// emissions and not presses (note 23).
            		var startFrame = BLEBarrel.cmdStartRec;
            		// CdC item 93, axis S-23: the frame is chosen before the tell prints it, so
            		// [start] and [start2] name what leaves and not what was available. The flag
            		// is a barrel field, so the re-assignments of the arrays at :474-:475 cannot
            		// wipe it, the datum that settled the same shape for the stop at item 68.
            		// CdC items 93 and 94, axis S-23: the start of the video function (command 4, body `08 01`)
            		// and the start of the Timelapse command (command 22, body `08 02` and body `08 05`) each
            		// crossed once and the window answered n8208=0 n8256=0 beside them. The three shapes the
            		// words of the reference give are refused, so no start frame of a video leg is chosen for
            		// this entry any more; `cmdStartStarlapse` stays declared at barrel:199 as the datum of
            		// item 94 and the flag keeps its name, but it now names the leg of the press (item 95),
            		// and the leg prints what leaves at `[cap]` (:324).
            		var sdDeclared = (startFrame[0] & 0xff) | ((startFrame[1] & 0xff) << 8)
            				| ((startFrame[2] & 0xff) << 16) | ((startFrame[3] & 0xff) << 24);
            		Sys.println("[start] " + BLEBarrel.currentLabel + " cmd=" + (startFrame[7] & 0xff).toString()
            				+ " declared=" + sdDeclared.toString() + " body=" + (sdDeclared - 16).toString());
            		Sys.println("[start2] " + BLEBarrel.currentLabel + " bytes=" + BLEBarrel.bytesToHex(startFrame));
            		bleDevice.sendCMD(startFrame);
             	} else {
             	// CdC item 57, axis S-12: the capture belongs to the press for the
             	// whole photo family of the generated entries, not only for the p3
             	// entry (the third half of the mixup of the item 48: a p0 selection
             	// reached the mode, never the press). The family of the camera is
             	// already decided above by the write of the axis S-7 (BLEBarrel.videoMode,
             	// green at [vw]); what this site decides is the arming of the capture.
             	// photoBurstMode only picks the frame of the entry: p3 takes the burst
             	// TAKE_PICTURE, a p0 or p2 selection takes cmdSetPhoto, the 16-byte
             	// empty-body TAKE_PICTURE of the item 44 that the GPS axis alone rewrites
             	// with a header (site :409). The tell prints the datum that picks the
             	// frame and the size of the frame that leaves, both read at this site
             	// (note 8 of section 15). The tell prints before the branch so that a
             	// negative reads the flag that was not armed, not only an absence.
             	var captureFrame = BLEBarrel.cmdSetPhoto;
             	if (BLEBarrel.photoBurstMode) {
             		captureFrame = BLEBarrel.cmdSetPhotoBurst;
             	}
             	Sys.println("[cap] photo=" + BLEBarrel.photoCaptureMode.toString() + " burst=" + BLEBarrel.photoBurstMode.toString() + " slp=" + BLEBarrel.starlapseStartMode.toString() + " frame=" + captureFrame.size().toString());
             	if (BLEBarrel.photoCaptureMode || BLEBarrel.starlapseStartMode) {
             		bleDevice.sendCMD(BLEBarrel.cmdApply);
             		bleDevice.sendCMD(captureFrame);
             	} else {
             		// The legacy path keeps its old behavior: it sends the persisted
             		// mode, which is neither the mode frame nor the capture (the suspect
             		// the stop rule of the rung S-10 names). A legacy id never arms the
             		// flag, so this branch is not a neighbor of this axis (note 13 of
             		// section 15: those sites stay out of reach).
             		bleDevice.sendCMD(BLEBarrel.cmdApply);
             		bleDevice.sendCMD(BLEBarrel.currentMode);
             	}
             	}
            } else if (BLEBarrel.recState == BLEBarrel.stateStartRec) {
        		Ui.pushView(actionMenu, new actionDelegate(), Ui.SLIDE_IMMEDIATE);
        	} else {
        		// Starting or Stopping a recording might take time. 
        		// Do nothing until recording has started or stopped. 
				// to debug allow a second time the menu to appear...
       			Ui.pushView(actionMenu, new actionDelegate(), Ui.SLIDE_IMMEDIATE);
       			BLEBarrel.recState = BLEBarrel.stateStopRec;
        	}
//		}
        return false;
    }
    
    function onMenu() {
        var menu = new Ui.Menu2({:title=>"Settings"});

		// Build menu according to device
// Axis S-9, the gate that decides which menu is offered. The datum is the level the scan set. The print lives before the switch, so a level that matches no case prints nothing, and the absence of a line is never a verdict (criterion 14).
		// CdC item 158, the datum of the axis model at the gate of the menu: the
		// line names the model of the matrix the menu is built for beside the
		// level, so the entries and the envelope of a run are never read from the
		// model the camera is. The datum of the detection (detectedModel) stays
		// apart from the datum of the forcing (capModel), and both print here, so
		// a forced run answers which model was detected and which one is in force
		// (note 8 of the CdC: the tell and the decision answer one datum, printed
		// before the branch reads it). An index the tables do not know answers -1,
		// and every view of such a model answers an empty Array: the menu stays
		// empty and the walk below says so, because an absence of a line is never
		// a verdict (criterion 14 of 11.3).
		Sys.println("[lvl] menuLevel=" + obsText(BLEBarrel.menuLevel) + " model=" + BLEBarrel.capModel + " detectedModel=" + BLEBarrel.detectedModel + " detectedLevel=" + obsText(BLEBarrel.detectedLevel));
// The gate of the menu answers for any level, and prints the state of the
		// run before any branch reads it (note 8 of the CdC). The mi/measured pair
		// of the capability module is gone: the chain of Levels.mc answers rows by
		// level, never by a model index, and the rows handed to the menu are
		// printed and counted by the [add] and [menu] lines of the build. A forced
		// run names the choice in force beside the detection, so the two datums of
		// the persistence axis stay apart on one line (note 8).
		Sys.println("[gate] model=" + BLEBarrel.capModel + " level=" + obsText(BLEBarrel.menuLevel)
			+ " forcedModel=" + BLEBarrel.testModel + " forcedLevel=" + obsText(BLEBarrel.testLevel));
		// The menu gate is where the app reads the family in force, so it is the
		// site where the position axis re-syncs to it (Main.gpsSync, item 8 of the
		// integration): a bond that completed while the main view sat untouched
		// finds its verdict here, before any entry this build offers is reachable.
		// The decision is edge-guarded, so opening the menu is never a poll.
		mainApp.gpsSync();
// The chain of levels answers the menu in one builder: the Level 0 base
		// names no mode row (a camera the chain does not name gets the app of
		// start, stop and state), every level adds its delta, and the UCD2 level
		// replaces the chain with its own rows — the legacy envelope is
		// unreachable there because its rows are not in that chain, and the GPS
		// toggle and the Default Video entry below stay gated off it (the
		// measured decision of the X6 run: no legacy frame reaches that camera).
		addLevelItems(menu, BLEBarrel.menuLevel);

		// CdC item 158, the entry MenuLevel: the entry that forces the menu and
		// the family of another model, so the widget stays testable on the one
		// camera the user owns. The entry belongs to the axis of the model, not
		// to the envelope of a camera, so it is offered whatever the level the
		// scan named. The choice of that submenu carries a model name and a
		// level, never a frame and never a protocol number: the frame arrives at
		// the selection of a choice, where entryFrame() is the single site that
		// turns a key into a frame (rea/11). A forced family writes frames of
		// another protocol on the camera the user owns, so the ceiling of the
		// barrel bounds what crosses and answers [hook] refused (CdC note 52).
		menu.addItem(new Ui.MenuItem("MenuLevel", "", "MenuLevel", {}));

		// The GPS toggle and "Default Video" belong to the legacy envelope.
		if (BLEBarrel.menuLevel != 3) {
			if (BLEBarrel.GPSon) {
				menu.addItem(new Ui.MenuItem("GPS OFF","","GPSon",{}));
			} else {
				menu.addItem(new Ui.MenuItem("GPS ON","","GPSon",{}));
			}
			menu.addItem(new Ui.MenuItem("Default Video","","DefaultV",{}));
		}

        // Axis S-0: the menu the watch receives, item by item, before it is
        // pushed. A Menu2 answers no item count and documents no limit, so the
        // walk stops at the first Null, and 40 is only the bound of the walk:
        // the X5 menu can hold at most the 8 generated entries of item 107 plus
        // the 2 legacy ones, the 6 resolutions being in the sub-menu now and not
        // here (they answer at [sub]). MAX_SIZE stays out of the print: it belongs to another class, and
        // the walk below answers the count of this menu (note 14: a reference
        // is not a datum). One line per entry: the id the selection must
        // bring back, and the label the screen must show.
        var walk = 0;
        var entry = null;
        while (walk < 40) {
            entry = menu.getItem(walk);
            if (entry == null) {
                break;
            }
            Sys.println("[menu] " + walk + " id=" + obsText(entry.getId()) + " label=" + obsText(entry.getLabel()));
            walk += 1;
        }
        Sys.println("[menu] n=" + obsText(walk));

        Ui.pushView(menu, new Menu2Delegate(), Ui.SLIDE_IMMEDIATE);
        
        return true;
    }

}

class Menu2Delegate extends Ui.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

function onSelect(item) as Void {
  	  	var info = null; 
    	var location = null;
		var itemID = "";
		var chglbl = true; 
		// Axis S-6 of the PREVIOUS selection: the state the observer holds, read at
		// the top of this interaction and not at the end of the last one, so a
		// notification had the time to reach. Nothing here polls the camera (EF-20).
		Sys.println("[obs] resNow=" + obsText(bleDevice.peekResNow())
			+ " family=" + obsText(bleDevice.peekFuncMode())
			+ " subPhoto=" + obsText(bleDevice.peekSubPhoto())
			+ " subVideo=" + obsText(bleDevice.peekSubVideo()));
		// Axis S-6 split: did the notification reach the delegate at all, or did
		// it reach it cut. Counts are per frame start (BLEBarrel:786), so a frame
		// the delegate cut at 20 bytes still counts; the declared/arrived pair
		// describes the LAST frame the observer reassembled, not only 0x2065.
		Sys.println("[obs2] n2065=" + bleDevice.peekCodeCount(0x2065).toString()
			+ " n2053=" + bleDevice.peekCodeCount(0x2053).toString()
			+ " notif=" + bleDevice.peekNotifCount().toString()
			+ " declared=" + bleDevice.peekNotifDeclared().toString()
			+ " arrived=" + bleDevice.peekNotifArrived().toString()
			+ " cut=" + bleDevice.peekNotifTruncated().toString()
			+ " hexLen=" + bleDevice.peekNotifHex().length().toString());
    
   		if (BLEBarrel.GPSon) {
       		info = Position.getInfo();
       		// With GPS on but no fix, getInfo() still succeeds and .position is
       		// Null; toDegrees() on that Null raised "Unexpected Type Error".
       		if ((info != null) && (info.position != null)) {
        		location = info.position.toDegrees();
        		if ((location == null) || (location.size() < 2)) {
        			location = null;
        		}
        	} else {
        		location = null;
        		}
   		}
		
    	BLEBarrel.cmdStartRec = [0x12, 0, 0, 0, 0x4, 0, 0, 0x4, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x1]b;  // Start video Recording commmand
	 	BLEBarrel.cmdStopRec =  [0x12, 0, 0, 0, 0x4, 0, 0, 0x5, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x10, 0x1]b; // Stop recording command
    	BLEBarrel.recState = BLEBarrel.stateStopRec;
    	BLEBarrel.videoMode = true;
    	// CdC item 57, axis S-12: the arming of the capture is re-set on every
    	// selection, like the family write just above. Only a generated photo
    	// entry arms it again in the same selection block below, so a legacy
    	// branch of the press it had before.
    	// CdC item 68, axis S-15 (persistence): the arming of the Timelapse stop is
    	// re-set on every selection, like the family write and photoCaptureMode just
    	// above. The arrays cmdStartRec/cmdStopRec re-assigned at :474-:475 on every
    	// entry cannot carry the p2 stop (measured negative, item 65: the patch was
    	// wiped at the press); a barrel boolean set at the selection survives.
    	// Only the p2 branch of the generated route below re-arms it in the same
    	// selection, with a content test (.equals(), the trap of note 9).
    	BLEBarrel.photoCaptureMode = false;
    	BLEBarrel.timelapseStopMode = false;
     	// CdC item 93, axis S-23: the arming of the Starlapse start is re-set on every
     	// selection, like the Timelapse stop just below and the flags above. Only a
     	// branch of the generated route re-arms it in the same selection.
     	BLEBarrel.starlapseStartMode = false;
		// Only the X6Video entry below re-arms UCD2; any other menu selection
		// returns the widget to the legacy envelope.
		BLEBarrel.ucd2Armed = false;
		
		itemID = item.getId() as Lang.String;
		// Axis S-1: the id of the item the user selected, and the character that
		// routes it. One print, one question, before any decision. It also proves
		// the build on the watch carries the ids of the generated menu.
		Sys.println("[gen] id=" + itemID + " first=" + itemID.substring(0, 1));
		// CdC item 158, the forcing of the axis model at the selection of a choice of
		// the submenu of MenuLevel. The choice answers a model of the matrix and the
		// level of its envelope; the datum of the forcing (testModel, testLevel) stays
		// apart from the datum of the detection (detectedModel, detectedLevel), so a
		// forced run answers both, and the gate of the menu reads the pair of the run
		// (capModel, menuLevel). The arming of the envelopes follows the forcing the
		// way the connection of a real camera of that model arms it, so no envelope of
		// another model stays reachable while a family is forced; the bound of that
		// reaching the camera the user owns is the ceiling of the barrel, which answers
		// [hook] refused past HOOK_WRITE_CEILING writes (CdC note 52). The forcing is
		// applied here, by the application, and never by a call of the protocol barrel:
		// a function of the barrel that creates the device is reached as a method of the
		// device, not by module name (note 47 of the CdC).
		// The id of a choice is force + the name of a model of the module verbatim
		// (addMenuLevelItems above), and forceoff, the choice that gives the detected
		// model back. One scan of the two tables of the module answers the model and the
		// level of a choice, so the choice of a model and the envelope of that model
		// answer one datum (note 8 of the CdC): no hand-written pair, no ternary (trap
		// of the repo notes), the content test of a String is .equals() (note 9).
		var forcedLevel = -1;
		var forcedModel = "";
		var ch = 0;
		while (ch < Levels.models.size()) {
			if (itemID.equals("force" + Levels.models[ch])) {
				// The level of a model answers the table of the chain at the same
				// index as its name, the same datum.
				forcedModel = Levels.models[ch];
				forcedLevel = Levels.modelLevels[ch];
			}
			ch += 1;
		}
		if (itemID.equals("forceoff")) {
			// The choice of off gives the detected model back: the model in force
			// goes to the model the bond named, and the level answers the table of
			// the chain at the index of that name, so off cannot disagree with a
			// detection.
			forcedModel = BLEBarrel.detectedModel;
			forcedLevel = Levels.levelOfName(forcedModel);
		}
		if (forcedLevel != -1) {
			// The forcing, applied at the selection of the choice: the datum of the
			// run changes here, not at the transport, and never at the next build of a
			// menu. The gate reads the pair of the run, so the next build offers the menu
			// of the model forced. The clearing at the next connection takes these fields
			// back, which is where a fresh bond re-derives the datum of the detection
			// (axis of the persistence, note 8 of the CdC).
			BLEBarrel.testLevel = forcedLevel;
			BLEBarrel.testModel = forcedModel;
			BLEBarrel.menuLevel = forcedLevel;
			BLEBarrel.capModel = forcedModel;
			if (forcedLevel == 3) {
				// The UCD2 envelope, the state a real X6 connection arms at the bond.
				BLEBarrel.ucd2Armed = true;
				BLEBarrel.x5Armed = false;
			} else {
				BLEBarrel.ucd2Armed = false;
				// The arming of the X5 follows the model of the matrix in force, not its
				// level: the prefix chain of the barrel arms the X5 protocol for the X5
				// only (BLEBarrel.mc:2040), and leaves it disarmed for the models of the
				// older envelope and of the X4 line, so the arming follows the model the
				// way a connection does, and never the level of a gate.
				BLEBarrel.x5Armed = forcedModel.equals("X5");
			}
			// The position axis re-asks its decision at the site that changes the
			// family in force (Main.gpsSync, item 8 of the integration): a forcing
			// onto the X5 line takes the radio off even when the user's flag is on,
			// a forcing off or onto the older envelope gives the flag its radio back.
			mainApp.gpsSync();
			// The user's confirmation of a model and level is kept by the name
			// on air, beside the chain's answer (item 7 of the integration,
			// the confirmed-level axis of the barrel): a future bond whose name
			// the chain does not know resumes at this level. A name the chain
			// does know keeps answering the table first - the kept level is the
			// fallback of the resolution, never its override.
			bleDevice.noteConfirmedLevel(BLEBarrel.deviceName, forcedLevel);
			// A choice applies nothing of itself: the datum of the family goes to the
			// value that names no frame, so the apply below writes no frame for a choice
			// of the submenu, and the next selection writes inside the family forced.
			// currentMode stays a Lang.String, which the apply reads as no frame (CdC
			// item 55, the datum of the apply).
			BLEBarrel.currentMode = "DefaultV";
			if (forcedModel.equals(BLEBarrel.detectedModel)) {
				// The model forced is the model the bond named (the choice off, or a
				// choice that names the camera the user owns): no frame of another
				// protocol reaches this camera, so the ceiling of the axis never
				// applies and the forcing answers disarmed, which is the state a run
				// of the X5 lives in. The menu still answers the pair of the model,
				// which the gate reads apart from the forcing (note 8 of the CdC).
				BLEBarrel.testModel = "";
				BLEBarrel.testLevel = -1;
			}
		}
		// CdC item 159, the ceiling of a visit of the axis: a fresh visit of the
		// submenu of MenuLevel is a fresh ceiling, the way a fresh bond is a fresh
		// ceiling (axis of the persistence). The selection of the entry that opens
		// that submenu ends one visit and takes the counter of the forcing back, so
		// the bound answers at the transport for the family the next visit arms. The
		// reset prints at the site that decides it (criterion 14 of 11.3), never by
		// the absence of a count, and the line below names the state in force for the
		// rest of this selection.
		if (itemID.equals("MenuLevel")) {
		    BLEBarrel.hookSent = 0;
		    Sys.println("[hook] reset sent=0");
		}
		// CdC item 158, the answer of the axis of the model, printed once per
		// selection and after any forcing this selection applied, so the line names
		// the state in force for the rest of the selection and never the state a
		// previous selection left. The datum of the forcing (testModel, testLevel)
		// and the datum of the detection (detectedModel, detectedLevel) print apart,
		// so a forced run answers both the model of the matrix in force and the model
		// the bond named (note 8 of the CdC: the tell and the decision answer one
		// datum), and never by an absence of a line (criterion 14 of 11.3).
		Sys.println("[hook] forced=" + (!BLEBarrel.testModel.equals("")).toString()
			    + " model=" + BLEBarrel.testModel + " level=" + BLEBarrel.testLevel.toString()
			    + " sent=" + BLEBarrel.hookSent.toString()
			    + " detectedModel=" + BLEBarrel.detectedModel
			    + " detectedLevel=" + obsText(BLEBarrel.detectedLevel));
		// An id of the generated menu (r<value>, p<value>) resolves through the
		// resolver above. The legacy ids below belong to the cameras of the
		// older envelope and keep their own switch: the capability model covers
		// the X5 line only, so those menus stay as they are.
		// Axis S-2 part one: the route that decides between the generated ids and the
		// legacy ids. The print names the decision, which answers whether the resolver
		// is called at the site of the selection, not whether the resolver holds a frame.
		// One boolean, printed before it is branched on, so the tell of the axis and
		// the decision answer the same datum and cannot disagree (note 8 of the CdC).
		// The route of the run of the 2026-10-26 read gen=false under [gen] r167
		// first=r: the test of a String was ==, and == on a String compares object
		// identity, never content, so substring(0, 1) == "r" is false whatever the
		// id is. The content test of Lang.String is .equals() (measured at the
		// barrel boundary too, item 14 of the CdC). The fix to apply is this test
		// and only this test: the resolver, the frame, the boundary and the apply stay
		// as they are until their own axis is green.
		// CdC item 74, axis S-17 (the letter of the family): a generated entry is one
		// letter and a value, and there are now THREE families: r = resolution, p =
		// photo sub-mode, v = video sub-mode. Without v in this content test, a `v11`
		// selection walks the legacy branch and applies nothing, so the first video
		// run would grade the resolver instead of the delivery. The test stays on the
		// content (.equals(), note 9): identity on a String is never true.
		// The fix the tell names is this test only; the resolver, the frame, the
		// boundary and the apply keep their own rungs.
		// Axis model, the letter that routes the entry selected. r, p and v are the
		// ids of the generated menu of the X5, the datum of the rungs of the single-
		// axis protocol, and the resolver above reads them as values of the protocol
		// of this camera. The letter o routes an entry of the generated menu of
		// another model: an unmeasured model gets label-keyed ids (o + the index of
		// the model + the letter of the family + the index of the entry), never X5-
		// numbered ones, because the numbering of the protocol exists over BLE on
		// the X5 only and the numbering is not a scale across models (rea/11). Such
		// an entry answers its frame through its key, at entryFrame() only.
		// The tier of the entry answers the authority of the cell of the matrix, so
		// the answer prints at the site that decides and never through the label of
		// the item, which is a String the screen shows. The row of the chain in
		// the level in force (Levels.mc) answers id, label, key and family at one
		// position of one chain, so the print, the refusal and the frame cannot
		// disagree about that entry (note 8 of the CdC). An id the level does not
		// answer is plumbing (DefaultV, GPSon, MenuLevel, the force choices) or
		// nothing, and no id ever reads through the rows of another level: ids are
		// scoped by the level, as the numbering of the X5 protocol was never a
		// scale across models (rea/11). An entry of the chain that names a label
		// only (a doc row) answers a Null key, and the selection answers by a
		// refusal printed at the site that withholds the frame (criterion 14 of
		// 11.3); the refusal is not a frame the camera refused (EF-22). No
		// ternary: the trap of the repo notes. The content test of a String is
		// .equals(), never == (note 9 of the CdC).
		var selRow = Levels.rowOfId(BLEBarrel.menuLevel, itemID);
		var selKey = "";
		var selFam = "";
		if (selRow != null) {
			selKey = selRow[Levels.RKEY];
			selFam = selRow[Levels.RFAM];
		}
		var genRoute = false;
		if (selRow != null) {
			genRoute = selFam.equals("v") || selFam.equals("p") || selFam.equals("r");
		}
		// Tell of the axis of the entry: the id, the level in force, the family
		// and the key of the row, printed before the branch below decides.
		Sys.println("[route] " + itemID + " gen=" + genRoute.toString()
			+ " level=" + obsText(BLEBarrel.menuLevel) + " fam=" + selFam + " key=" + selKey);
		if (genRoute && selKey.equals("")) {
			Sys.println("[refused] id=" + itemID + " key=none level=" + obsText(BLEBarrel.menuLevel));
		}
		if (genRoute) {
			if (itemID.equals("p0") && BLEBarrel.GPSon && location != null && info != null) {
				// GPS photo: the fix is written in the header before the mode.
				BLEBarrel.cmdSetPhoto = bleDevice.photoGpsHeader(location[0], location[1], info.altitude);
			}
			// CdC item 68, axis S-15 (persistence): this block used to patch the
			// arrays cmdStartRec/cmdStopRec for p2. Two measured reasons it never
			// reached the press (item 65): the settings onSelect re-assigns those
			// arrays at :393-:394 on every entry, and this guard was == on a String,
			// the trap of note 9 (object identity, never content). The stop of a
            // photo Interval sequence is now its own measured frame in the barrel
            // (cmdStopTimelapse, 12 ... 17 ... 08 02, code 23, TimelapseMode member
            // 2 = TIMELAPSE_INTERVAL_SHOOTING, green at the bench, item 68), and the
            // selection arms it with a boolean that no re-assignment can wipe.
            // The old patch also moved the start frame of p2 (cmdStartRec[7] = 0x16):
            // the start of the Interval stays the capture of the press (S-14), the
            // frame of the resolver, untouched.
				// Item 162 (the arming S-37 owed): the id of an entry of a model of the matrix
				// names no protocol number (rea/11), so the id face of this test is the datum of
				// the X5 only, and the second face answers the ROLE of the entry of the row in
				// force, the key of the cell the matrix names as the Interval, PhotoInterval.
				// Both faces are .equals() on a String (note 9: == is identity, never content),
				// and selKey answers the empty String for an X5 id, for a cell that carries no
				// key, and for a model the tables do not know (mi = -1 answers rowIds, then entry
				// at -1, then the empty key), so an unknown model arms nothing.
						BLEBarrel.timelapseStopMode = itemID.equals("p2") or selKey.equals("PhotoInterval");
                        // CdC item 93, axis S-23 (the second reading of that tell): the start
                        // of the Timelapse command, 12 ... 16 ... 08 02, crossed once and the window
                        // answered n8208=0 n8256=0 again. The body carried 2, the enum member that
                        // names an INTERVAL, not a Starlapse; the library names a Starlapse 5.
                        // So the entry whose start rides that command arms a frame carrying 08 05,
                        // the way the p2 entry armed the stop carrying 08 02 at item 68. The other
                        // video sub-modes keep the start of the video function and their own rungs.
                        // The test is .equals(), the content test of note 9, never == on a String.
                        // CdC item 100: the entry that would arm it is no longer offered, so this
                        // flag stays false and the press keeps the leg item 95 named for it.
                        	// Item 162, kept at the id on purpose: an entry of the Starlapse cell of a model
                        	// of the matrix is official, its selection answers [refused] id=... tier=official
                        	// and writes nothing, so no press of that selection exists and a key face of this
                        	// arming could never pay (EF-22: no acceptance of this axis closes on a reply).
                        	// v12 stays the datum of the Starlapse entry of the X5 itself.
                        				BLEBarrel.starlapseStartMode = itemID.equals("v12");
			// The chain names the entry selected by its key: the key of a measured
			// row of the X5 line IS its protocol id (the numbering exists over
			// BLE on the X5 only, rea/11), and the key of a doc row is the
			// semantic name the reference app speaks. entryFrame() above answers
			// both at the single site; a key that answers no frame leaves the
			// write below unreached, so no frame is ever supposed from a label
			// of a document.
			var frame = entryFrame(selKey);
			// Axis S-2, at the call site of the selection. The tell of an axis lives at
			// the boundary that axis crosses (note 8 of the CdC): the print inside the
			// resolver says what the local variable holds, never the value the call site
			// received. This line never appears when the resolver was never called, and
			// it answers false when the resolver answered null.
			Sys.println("[res2] " + itemID + " frame=" + (frame != null).toString());
			if (frame != null) {
				// Axis S-3: the frame at this call site, in bytes, to compare with the
				// table of the protocol barrel (r167 is 27 o, r0 is 23 o, p0 is 63 o).
				Sys.println("[frame] " + itemID + " size=" + frame.size().toString());
				// Axis S-8, the shape of the frame the write sends. The envelope of
                // the X5 carries the declared length at 0..3 and the command at
                // byte 7 (rea/10 §11.1, and the barrel writes the same envelope).
                // The tell reads the datum at the boundary the axis cross.
                var shDeclared = (frame[0] & 0xff) | ((frame[1] & 0xff) << 8)
                    | ((frame[2] & 0xff) << 16) | ((frame[3] & 0xff) << 24);
                Sys.println("[shape] " + itemID + " cmd=" + (frame[7] & 0xff).toString()
                    + " declared=" + shDeclared.toString()
                    + " body=" + (shDeclared - 16).toString());
                // Content of the same frame, one line per boundary: the probe prints the
                // bytes it handed to sendCMD with the tags "sent frame" and "sent chunk"
                // (BLEBarrel.mc:1232 and :1242, probe-only). The tell here answers with the
                // bytes the app handed. One question: are the two routes handing the same
                // frame ? The idiom is the barrel's own bytesToHex (`BLEBarrel.mc:333`, the
                // one the Probe uses at runtime), never Number.toString(16), whose arity is
                // not measured.
                Sys.println("[shape2] " + itemID + " bytes=" + BLEBarrel.bytesToHex(frame));
				// Axis S-4: the write below crosses a module boundary. currentMode is
				// declared Lang.String or Lang.ByteArray in the barrel. Test the value
				// on both sides of the write, with the idiom the barrel itself uses at
				// its boundaries. A boundary that keeps Lang.String after the write
				// holds the fault there and nowhere else.
				var modeIsFrameBefore = BLEBarrel.currentMode instanceof Lang.ByteArray;
				BLEBarrel.currentMode = frame;
				var modeIsFrameAfter = BLEBarrel.currentMode instanceof Lang.ByteArray;
				Sys.println("[mode] " + itemID + " " + modeIsFrameBefore.toString() + " -> "
                    + modeIsFrameAfter.toString());
				// Axis S-7, family write of a photo selection. The flag of the
				// barrel decides the photo leg of the transport and the encoding of
				// the telemetry (BLEBarrel.mc:2045). Measured (item 39): the run of
				// p3 answered [vw] p3 after=true want=false, while axes S-1 and
				// S-5 were green. != on a String compares object identity (note 9),
				// so that write paid true whatever the id. The fix is this test and
				// nothing else: one boolean, printed then assigned, so the tell and
				// the write answer the same datum (note 8). The top of onSelect
                // assigns videoMode = true for each selection, and this write comes
                // later, so the family of a generated id is decided here alone.
					// Axis chain: the family of the entry answers the row of the level in
					// force, not a letter of the id — the row that answers the
					// family is the row that answers the key and the frame, one
					// datum that cannot be paired wrong (note 8 of the CdC).
					var photoFam = selFam.equals("p");
				BLEBarrel.videoMode = !photoFam;
				// Axis of the separation (item 48): a p3 selection arms the mode only;
				// the capture frame belongs to the start press. The datum is set
				// here, printed at the site that reads it (:219). The legacy ids
				// never touch this flag: their own axis stays out of reach.
					// Item 162 (the arming S-37 owed), the same shape: the cell the matrix names as
					// the Burst carries the key PhotoBurst, so an entry of that cell of a model of
					// the matrix arms the mode, while the id face stays the datum of the X5. An
					// official cell of that row answers [refused] at the tier boundary and writes
					// nothing, so its own press never reaches this arming (EF-22).
								BLEBarrel.photoBurstMode = itemID.equals("p3") or selKey.equals("PhotoBurst");
				// CdC item 57, axis S-12: the arming of the capture at the press is the
				// whole photo family of the generated entries, not the p3 entry alone. Set
				// with the family write of the S-7 just above, read at the press of start.
				// photoBurstMode stays the frame choice of the entry, unchanged.
				BLEBarrel.photoCaptureMode = photoFam;
				Sys.println("[vw] " + itemID + " photoFam=" + photoFam.toString()
					    + " after=" + BLEBarrel.videoMode.toString());
			}
		}

        switch(itemID) {
            case "8k30" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSet8k30;
            	break;  
            case "5k30" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSet5k30;
            	break;  
            case "5k25" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSet5k25;
            	break;
            case "5k24" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSet5k24;
            	break;
            case "4k30" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSet4k30;
            	break;
            case "4k50" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSet4k50;
            	break;
            case "3k100" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSet3k100;
            	break;
            case "HDR" :
				// for HDR the start & stop commands are slightly differant
            	BLEBarrel.cmdStartRec[17] = 0x03;
            	BLEBarrel.cmdStartRec[7] = 0x04;
            	BLEBarrel.cmdStopRec[17] = 0x03;
            	BLEBarrel.cmdStopRec[7] = 0x05;
            	BLEBarrel.currentMode = BLEBarrel.cmdSetHDR;
            	break;
            case "TimeLapse" :
            	// for Timelapse the start & stop commands are slightly differant
            	BLEBarrel.cmdStartRec[7] = 0x16;
            	BLEBarrel.cmdStopRec[16] = 0x08;
            	BLEBarrel.cmdStopRec[7] = 0x17;
            	BLEBarrel.currentMode = BLEBarrel.cmdSetTL;
            	break;
            case "BulletTime" :
				// for Bullet time the start & stop commands are slightly differant
            	BLEBarrel.cmdStartRec[17] = 0x02;
            	BLEBarrel.cmdStopRec[17] = 0x02;
            	BLEBarrel.currentMode = BLEBarrel.cmdSetBullet;
            	break;
case "Photo" :
if ((BLEBarrel.GPSon) && (location != null) && (info != null)) {
    	// fill GPS position before sending command.
				BLEBarrel.cmdSetPhoto = bleDevice.photoGpsHeader(location[0], location[1], info.altitude);
 			}
				BLEBarrel.currentMode = BLEBarrel.cmdSetPhoto;
            	BLEBarrel.videoMode = false;
            	break;
            case "PhotoHDR" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSetPhotoHDR;
            	BLEBarrel.videoMode = false;
            	break;
            case "PhotoBurst" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSetPhotoBurst;
            	BLEBarrel.videoMode = false;
            	break;
            case "PhotoInterval" :
            	// Intervall Photo is almost treated as a Timelapse video. 
            	BLEBarrel.currentMode = BLEBarrel.cmdSetInterval;
            	BLEBarrel.cmdStartRec[17] = 0x02;
            	BLEBarrel.cmdStartRec[7] = 0x16;
            	BLEBarrel.cmdStopRec[17] = 0x02;
            	BLEBarrel.cmdStopRec[16] = 0x08;
            	BLEBarrel.cmdStopRec[7] = 0x17;
				break;
			case "NightShot" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSetNightShot;
            	BLEBarrel.videoMode = false;
            	break;
			case "GPSon" :
            	BLEBarrel.GPSon = !BLEBarrel.GPSon;
             	// The flag keeps answering the user's intent alone; what the radio
             	// is asked answers the pair of the flag and of the family in force,
             	// decided at the one site that reads both (Main.gpsSync, item 8 of
             	// the integration). A toggle ON on a camera of the X5 line is kept
             	// and named: the flag is true, the radio stays off, the [gps] line
             	// of the flip says which of the two datums answered.
             	mainApp.gpsSync();
				chglbl = false;
             	break;
			case "MenuLevel" :
				// Item 161 (the finding item 159 named on the artefact): the switch of the
				// ids held no case naming the entry of the axis, so the selection of MenuLevel
				// changed no mode at all, and the apply below is guarded on the MODE and never
				// on the id, so it re-sent what the PREVIOUS selection had armed: the second visit
				// of the axis answered [apply] MenuLevel frame=true and crossed two writes of the
				// family in force before its new choice armed. A visit of the entry of the axis is
				// to the family what a choice is: it gives back the value that names no frame,
				// the way the choice site does, so the visit costs no write of the family forced
				// and the bound of a family answers the writes of that family, not the visit.
				BLEBarrel.currentMode = "DefaultV";
				break;
			case "DefaultV" :
				BLEBarrel.currentMode = "DefaultV";
				break;
			case "X6Video" :
				// Arm the UCD2 envelope. currentMode stays at the "DefaultV"
				// sentinel on purpose: the apply block below is guarded by it
				// and would otherwise hand sendCMD() a String where it expects
				// a ByteArray. The intent of the spec (no legacy frame reaches
				// the camera while armed) is met either way.
				BLEBarrel.ucd2Armed = true;
				BLEBarrel.currentMode = "DefaultV";
				BLEBarrel.currentLabel = "X6 Video";
         }
		// Name of mode to be displayed. 
        if (chglbl) {
			Sys.println("item ID:" + itemID);
			BLEBarrel.currentLabel = item.getLabel();
		}
		// Apply changes. 
        // Axis S-5: the state of the mode printed before the guard takes its
        // decision. The test is an instanceof, so the print never raises when
        // the mode is a frame.
        var modeIsFrame = BLEBarrel.currentMode instanceof Lang.ByteArray;
        Sys.println("[apply] " + itemID + " frame=" + modeIsFrame.toString());
        if (!BLEBarrel.currentMode.equals("DefaultV")) {
			Sys.println("Apply changes");
			bleDevice.sendCMD(BLEBarrel.currentMode);
        	bleDevice.sendCMD(BLEBarrel.cmdApply);
		}
         
        // A state printed by name, never by bytes: adding a ByteArray to a String
        // raises "Unable to add incompatible types", and that crash would hide
        // the rest of the ladder. A frame prints as frame.
        var modeName = "frame";
        if (BLEBarrel.currentMode instanceof Lang.String) {
            modeName = BLEBarrel.currentMode;
        }
       	Sys.println("Menu ID + Name: " + itemID + ":" + BLEBarrel.currentLabel + " cmd : " + modeName);
        // CdC item 107, axis S-0 (the shape of the menu): the entry Video hands
        // a sub-menu of its own instead of going back to the main view. Nothing
        // above changes: the write of the family and its apply ran just above,
        // so the sub-menu is offered once the camera is in VIDEO_NORMAL, and a
        // resolution chosen there lands inside VIDEO_NORMAL (rea/11 §5.3, the
        // measured rule that kept the resolutions under Normal Video at item 74
        // in the first place). The test is .equals(), the content test of note
        // 9: == on a String compares object identity and is never true.
        // The flag of the barrel is the datum of the pop depth. A delegate of
        // the sub-menu is a new instance of the same class, so it cannot carry
        // what the delegate of the main menu set, and the depth is not a fact
        // of the view: the sub-menu is one more view to leave, so its selection
        // answers two popView to come back to the main one. One print per
        // branch, read before the branch takes its decision (note 8 of the CdC:
        // the tell lives at the boundary the axis crosses).
        // Axis model: the submenu of MenuLevel is one more view to leave, so its
        // datum is a flag of the barrel of its own, the way the resolution submenu
        // carries its own. Two flags, two questions, never one flag read for two
        // submenus (note 8 of the CdC). The print answers the pop depth of both
        // before the branch reads either, so the tell of the axis and the decision
        // answer one datum, and an absence of a line is never a verdict (criterion
        // 14 of 11.3).
        // CdC item 159: the resolutions of a model of the matrix answer a submenu of
        // their own too, so the opener answers the Video entry of the model in force.
        // The measured opener of the X5 was its own entry v0 (CdC item 107);
        // the chain of Levels.mc answers the opener as the sub flag of the row of
        // the level in force, at the same position that answers the id, the label
        // and the key of that row — one datum, no hand-written second list
        // (note 8 of the CdC). The rows of the submenu keep the rule of the
        // chain: a doc row answers [refused] at its selection and writes nothing.
        // The print answers the decisions before any branch reads one of them
        // (note 8 of the CdC: the tell and the decision answer one datum).
        var resOpen = false;
        if (selRow != null) {
            resOpen = selRow[Levels.RSUB] == 1;
        }
        Sys.println("[sub] res=" + resOpen.toString() + " push=" + (resOpen || itemID.equals("MenuLevel")).toString()
            + " depth=" + BLEBarrel.resolutionSubmenuOn.toString()
            + " forcedepth=" + BLEBarrel.menuLevelSubmenuOn.toString());
        if (resOpen) {
            BLEBarrel.resolutionSubmenuOn = true;
            var resMenu = new Ui.Menu2({:title=>"Resolution"});
            addLevelResItems(resMenu, BLEBarrel.menuLevel);
            Ui.pushView(resMenu, new Menu2Delegate(), Ui.SLIDE_IMMEDIATE);
        } else if (itemID.equals("MenuLevel")) {
            // CdC item 158, the submenu of MenuLevel: the same shape the Video entry
            // uses for its resolutions (CdC item 107), so a choice is selected at the
            // submenu and the forcing lands at the selection of the choice, where the
            // datum of the run changes, and never at the build of a menu. The choices
            // answer the models of the matrix (addMenuLevelItems above), plus the
            // choice off that gives the detected model back. A choice carries a model
            // name and a level, never a frame and never a protocol number: the frame
            // of an entry arrives at entryFrame(), the single site that turns a key into
            // a frame, and the ceiling of the barrel bounds what reaches the camera the
            // user owns (CdC note 52).
            BLEBarrel.menuLevelSubmenuOn = true;
            var forceMenu = new Ui.Menu2({:title=>"Force model"});
            addMenuLevelItems(forceMenu);
            Ui.pushView(forceMenu, new Menu2Delegate(), Ui.SLIDE_IMMEDIATE);
        } else {
            if (BLEBarrel.resolutionSubmenuOn) {
                BLEBarrel.resolutionSubmenuOn = false;
                Ui.popView(Ui.SLIDE_IMMEDIATE);
            }
            if (BLEBarrel.menuLevelSubmenuOn) {
                // The selection of a choice of the submenu of MenuLevel answers one
                // more popView to come back to the main menu, the way the selection of
                // a resolution answers its own: the flag of the barrel is the datum of
                // the pop depth, not a fact of the view. The datum of the forcing is
                // already in the fields of the barrel, so the main menu the walk rebuilds
                // is the menu of the model forced.
                BLEBarrel.menuLevelSubmenuOn = false;
                Ui.popView(Ui.SLIDE_IMMEDIATE);
            }
            Ui.popView(Ui.SLIDE_IMMEDIATE);
        }
        BLEBarrel.mMessage = BLEBarrel.currentLabel + "\n" + BLEBarrel.startMessage;
		WatchUi.requestUpdate();
        
   }
   	function onPosition(info) {
//		System.println("[onPosition]");
		bleDevice.sendPosition(info);
	}
   
}

class actionDelegate extends Ui.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
		
        switch(item.getId()) {
            case "Stop" :
            	BLEBarrel.recState = BLEBarrel.stateStopping;
            	BLEBarrel.mMessage = "Stopping...";
            		// CdC item 63, axis S-15: the stop of a sequence is a frame of its own,
            		// and an action of its own. Two tells at the site that sends it, the pair
            		// the resolver uses: the shape of the envelope (command byte, declared
            		// length, body length) and the content (the bytes themselves). Printed
            		// before the send, so a negative reads the frame that was sent instead of
            		// an absence of a line (criterion 14 of 11.3). Instrumentation only:
            		// the frame stays as it is until a measured datum closes the value of the
            		// stop of a photo Interval sequence (note 14 of 15: the shape tell and
            		// the content tell answer separately, and an unmeasured frame is not a
            		// guess of a fix).
            		// CdC item 68, axis S-15 (persistence): the press sends the array the
            		// selection armed. p2 armed cmdStopTimelapse (measured green at the bench,
            		// item 68); every other entry keeps cmdStopRec, the measured stop of the
            		// video family. The flag is a barrel boolean, so it survives the re-assignments
            		// of the arrays at :393-:394 that wiped the old p2 patch (measured negative,
            		// item 65). A datum of the transport is kept, no fix drawn: its retry watchdog
            		// keys on cmdStopRec, not on the new frame. The tells below print the array
            		// actually chosen, before the send (criterion 14). No ternary: a trap of the
            		// repo notes.
            		var stopFrame = BLEBarrel.cmdStopRec;
            		if (BLEBarrel.timelapseStopMode) {
            			stopFrame = BLEBarrel.cmdStopTimelapse;
            		}
            		var stDeclared = (stopFrame[0] & 0xff) | ((stopFrame[1] & 0xff) << 8)
            			| ((stopFrame[2] & 0xff) << 16) | ((stopFrame[3] & 0xff) << 24);
            		Sys.println("[stop] cmd=" + (stopFrame[7] & 0xff).toString() + " declared=" + stDeclared.toString() + " body=" + (stDeclared - 16).toString());
            		Sys.println("[stop2] bytes=" + BLEBarrel.bytesToHex(stopFrame));
              	bleDevice.sendCMD(stopFrame);
            	break;  
            case "Highlight" :
            	bleDevice.sendCMD(BLEBarrel.cmdHighlight);
               	break;  
            case "Track" :
            	bleDevice.sendCMD(BLEBarrel.cmdTrackThat);
            	break;
         }   
        // Sys.println("[Menu] Actions" );
		WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.requestUpdate();
   }
}
