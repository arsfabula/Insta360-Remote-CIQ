using Toybox.Application;
using Toybox.BluetoothLowEnergy;
using Toybox.Lang;
using Toybox.Position;
using Toybox.System;
using BLEBarrel;

var bleDevice;
var mainApp = null;


class Main extends Application.AppBase {
//	hidden var bleDevice;

	// The edge-guard of gpsSync: the state this app last put the position radio
	// in. The actuator is only asked when the decision below flips.
	var gpsLive as Lang.Boolean = false;

	// The start-warning flag (design of 14 nov.): answered once per cold
	// start, from the property alone, at the view's first draw - the site
	// note in RemoteView.onUpdate says why that site and not onStart. Never
	// re-evaluated in the session - this app has no onShow and the wake of
	// the watch continues the session (verified fact of the design); nothing
	// but the warning menu's own choices lifts it.
	var warnIntro as Lang.Boolean = false;

	function initialize() {
		AppBase.initialize();
	}

	function onStart(state) as Void {
		// Decision (17 nov. 2026): onStart names NOTHING of the barrel. Once the
		// widget answers a getGlanceView (it must - the words above that method
		// and the GlanceView page say why), these devices run the app's start
		// through the glance-sliced process, and every barrel symbol named here
		// faults: measured the 17 nov. on marqexpedition, constructing the
		// delegate here gave "Error: Illegal Access (Out of Bounds) / Failed
		// invoking <symbol>" at the `new` line, and with the construction moved
		// away but this method still calling gpsSync(), the identical fault
		// moved to the first barrel read inside gpsSync (BLEBarrel.capModel).
		// The boot lines left this method with their own words and now sit in
		// getInitialView - the rule the PR's own page had already set
		// (docs/x5-pr-app/watch-app.md, "start BLE only from getInitialView").
		// What stays is what both processes can hold.
		mainApp = self;
		// The start-warning flag itself is decided at the first draw, in
		// RemoteView.onUpdate - see the note there for why not here: an
		// entry-class call of a source module function faults in this VM,
		// twice observed. What stays here: the one field, false until the
		// view's first decision answers it.
	}
	
	function GPSenable (state as Lang.Boolean) as Void {
		// System.println("[Main] [GPS Enable] State: "+ state);
		if (state) {
			// Only GPS, and only the plain call. The dictionary form pinned
			// :constellations => [Position.CONSTELLATION_GPS], which the 9.3 doc says
			// is already the default when the option is left out - and that enum is
			// deprecated, "may be removed after System 10". Same behaviour, one
			// warning less, nothing to chase on the next SDK.
			Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
		} else {
			Position.enableLocationEvents(Position.LOCATION_DISABLE,null);
		}
	}

	// The one decision about the position radio (item 8 of the integration, twice
	// corrected on the 13 nov. - by the user's field datum, then by the user's
	// ruling that the option is PERMANENT). One datum answers it: the user's
	// intent, kept in BLEBarrel.GPSon. The first reading of item 8 gated the
	// radio on the model of the family in force; that was wrong twice over. The
	// X5 line does carry a position path - the timeline of docs/x5-protocol.md
	// L371 records the phone app sending UPLOAD_GPS (cmd 0x35) DURING a video
	// recording, and the barrel's own sendPosition emits exactly that frame (its
	// header opens with 0x35); the user verified in the Insta360 phone app that
	// a recorded X5 video carries a GPS track. And the option itself is not a
	// row of a camera's envelope: the user named it permanent, independent of
	// the level in force, so no model list stands in front of it. What the
	// original note was true about is only the frames it had looked at - the
	// photo GPS header belongs to the older envelope, the UCD2 settings path
	// holds no position field; on a line whose protocol carries no 0x35, the
	// radio runs because the user asked for it, and the window of the send is
	// the recording itself (sendPosition). Application by its edge only
	// (gpsLive keeps the state the app put; a [gps] line names a flip, never a
	// poll - criterion 14 of 11.3). The sites and the flag-keeping of the
	// original item 8 stand untouched.
	function gpsSync() as Void {
		var model = BLEBarrel.capModel;
		var want = BLEBarrel.GPSon;
		if (want == gpsLive) {
			// No edge, nothing to name: silent on purpose, the line below answers
			// a flip only.
			return;
		}
		System.println("[gps] flip=" + want.toString() + " model=" + (model == null ? "none" : model) + " user_flag=" + BLEBarrel.GPSon.toString());
		GPSenable(want);
		gpsLive = want;
	}

	function getInitialView() {
		// Phase 4: the ported PR #2 UI (RemoteView / RemoteDelegate). The old ViewData /
// InputDelegate pair stays in the tree, unreferenced, as the bench fallback until the
// new pair passes the Phase 5 physical session; one line here switches back.
		// The boot of the link, moved here by the decision of the 17 nov. marked
		// at onStart: this method runs in the full-mode process only, which holds
		// the whole PRG - the UCD2 codec trace is still fired from inside the
		// barrel (BleDevice.open), and calling BLEBarrel.ucd2DiagFrame() across
		// the unit boundary produced no output and still failed, so the trigger
		// stays on that side. The guard is for the session that reaches a view
		// twice: one delegate, one open, no second setDelegate over itself.
		if (bleDevice == null) {
			// Connect to camera
			bleDevice = new BLEBarrel.BleDevice();
			BluetoothLowEnergy.setDelegate(bleDevice);
			bleDevice.open();
		}
		// The position radio is never switched from the user's flag alone: one
		// decision reads the flag and the family in force together (gpsSync, the
		// pattern the PR's app named in its table, item 8 of the integration). At
		// this point no bond has named a model yet, so the decision answers the
		// flag, which is the older envelope's behavior; the sites that see a
		// family re-ask it.
		gpsSync();
return [new RemoteView(bleDevice), new RemoteDelegate(bleDevice)];
	}

	function onStop(state) as Void {
		Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
		// The guard is for the pure-glance session of the 17 nov. decision: it
		// never reaches getInitialView, so it has no delegate to close.
		if (bleDevice != null) {
			bleDevice.close();
		}
	}
	
	function onPosition(info as Position.Info) as Void {
		System.println("[onPosition]");
		bleDevice.sendPosition(info);
	}

	// Datum of the workstation (measured earlier, on the artefact that carried the annotation and this
	// barrel, verified with monkeydo on edge1040): an app that BOTH depends on a monkey barrel
	// and carries ANY (:glance) annotation crashed at startup with
	//    Error: Illegal Access (Out of Bounds) / Failed invoking <symbol>
	//    at onStart() (the `new BLEBarrel.BleDevice()` line). Bisected against the real barrel:
	//    the identical app passed with the annotation removed and failed with it present,
	//    whether it sat on this method or on the GlanceView class; a (:glance)-annotated app
	//    with no barrel dependency ran fine. Kept as a datum: the decision below is what that
	//    datum was really pointing at - an annotated app naming barrel symbols from the boot
	//    process - never the annotation of this method by itself.
	//
	// Decision (17 nov. 2026): TWO sites keep this annotation, this method and the view class.
	//   The third site of items 152/155 - the (:glance) that sat on the barrel's BleDevice
	//   class, at BLE Barrel\BLEBarrel.mc:788 when it was dropped (the words of the items
	//   named :381, an older line of a barrel that has grown) - is removed, the view went
	//   static, and the boot lines moved to getInitialView. The rule that replaces the site
	//   counting: the boot process and the glance view must name nothing outside the slice.
	// Measured the same day, and this is why. The three-site shape gave the glance process a
	//   slice of 58 402 o (PRG head, marqexpedition: glance_code_offset 44 747 /
	//   glance_data_offset 13 655) while the SDK's Glances page names the glance pool 32 Ko
	//   "for most devices" - the marq-generation of the widget class died at the boot exactly
	//   there ("Encountered an app crash", no stack). Taking the barrel site away while the
	//   view still read the barrel's mMessage reproduced the item 154 fault at the
	//   construction line, on marqexpedition AND epix2pro51mm; and with the construction
	//   moved but gpsSync() still in onStart, the identical fault moved to the first barrel
	//   read inside gpsSync (BLEBarrel.capModel) - the pairing of slice and boot, not the
	//   number of sites, owns the fault. The shape kept here measures 5 207 o (head
	//   glance_code 1 473 / glance_data 3 734, built app) and started traced alive on both simulators.
	// What is NOT removed, and why. This method stays: dropping the glance entirely was tried
	//   first, the real epix pro Gen 2 51mm bench ran the app but refused to add it to the
	//   loop, and the SDK docs give the automatic name-only glance to API < 4.0.0 devices
	//   only. And item 152's datum stands as its datum: a widget that answers getGlanceView
	//   with nothing annotated pays the "entire application will be loaded as a glance
	//   process" warning, and the whole PRG is over the pool devices.xml names for a glance.
	(:glance)
	function getGlanceView() {
        return [ new MyGlanceView() ];
    }     

}

