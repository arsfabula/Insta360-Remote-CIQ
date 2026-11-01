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

	function initialize() {
		AppBase.initialize();
	}

	function onStart(state) as Void {
		// The UCD2 codec trace is fired from inside the barrel (BleDevice.open),
		// not from here. Calling BLEBarrel.ucd2DiagFrame() across the unit
		// boundary produced no output and still failed, so the trigger was moved.
		bleDevice = new BLEBarrel.BleDevice();
		// Connect to camera
		BluetoothLowEnergy.setDelegate(bleDevice);
		bleDevice.open();
		// System.println("[Main] on start: " + BLEBarrel.GPSon);
		mainApp = self;
		GPSenable(BLEBarrel.GPSon);
	}
	
	function GPSenable (state as Lang.Boolean) as Void {
		// System.println("[Main] [GPS Enable] State: "+ state);
		if (state) {
		// GPS initialisation
		// Position.enableLocationEvents(Position.LOCATION_CONTINUOUS,	method(:onPosition));
			if (Toybox.Position has :CONSTELLATION_GPS) {
				// System.println("[Main] has constellation");
				Position.enableLocationEvents({
        			:acquisitionType => Position.LOCATION_CONTINUOUS,
        			:constellations => [Position.CONSTELLATION_GPS]
    				},
    				method(:onPosition)
				);
			} else {
				Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
			}
		} else {
			Position.enableLocationEvents(Position.LOCATION_DISABLE,null);
		}
	}

	function getInitialView() {
		return [new ViewData(bleDevice), new InputDelegate(bleDevice)];
	}

	function onStop(state) as Void {
		Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
		bleDevice.close();
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
	//    with no barrel dependency ran fine. Kept as a datum about that device and that
	//    build, and as a reason to test on edge1040 again - NOT a reason to leave the
	//    annotation off: the fault sat in the link step, not in the glance view.
	//
	// Decision (Cahier item 152): the annotation is RESTORED, as a prefix qualifier on the
	//    declaration - the form the SDK documents for a process scope (the Background
	//    Services page decorates with (:background) before the class and the var).
	// Without it the build answers, on every device of the manifest,
	//    WARNING: <device>: This is a 'watch-app' app type but no source code was
	//    annotated with (:glance). The entire application will be loaded as a glance
	//    process.
	// and devices.xml gives the glance process a 65 536-octet pool on these devices while
	// the app PRG is well above it, so a watch that had to load the whole app as a glance
	// process is over its pool. With (:glance) on this method and on the view class the
	// PRG carries its own glance section (the glance_code/glance_data offsets of the PRG
	// head are non-zero). Annotating only the view class makes the build add the entry
	// point to the glance process implicitly and say so; annotating class Main as well changes
	// nothing of the PRG, but annotating the barrel class instead of it is what makes the app
	// start - see the decision of item 155 below. The two app sites below are the app half of it.
	// Decision (Cahier item 155): THREE sites carry this decision, and the third of them is inside the barrel -
	//   BLE Barrel\BLEBarrel.mc:381, the blank line before `class BleDevice extends BluetoothLowEnergy.BleDelegate`
	//   at :382, which takes the delegate class into the glance process beside this method and the view class.
	// The shape of the three sites is what the simulator of the Epix 2 Pro 51mm answers: with only the two sites
	// below, that simulator crashed at Main.mc:23 (the `new BLEBarrel.BleDevice()` line) with Error: Illegal
	// Access (Out of Bounds) / Failed invoking <symbol>, Cahier item 154; with the barrel site added it starts.
	// So the fault is not owned by the annotation of this method: what has to be IN the glance process is the
	// class the app constructs at onStart(), and the reading that keeps the decision there is the PRG head
	// answering a glance slice (glance_code_offset 11852 / glance_data_offset 6173) that sits inside the 65 536-o
	// pool devices.xml gives the glance process, where loading the whole PRG of 162 156 o was over it.
	// One cost paid and named here: the informative type check (`-l 2`, a probe of the build gate, never the
	// route of the workstation, which runs `-l 0` = off) widens from the two lines item 152 named to 432 of the
	// same family, because the whole delegate class is now in the process and every module var it uses is read
	// as not available in all function scopes. That route is not clean for this app at all, and no line is drawn
	// on it; the acceptance of this shape is the app running, which is the eye of a runtime, never a log.
	// The words below are the datum of the workstation that had kept its own words about edge1040.
	(:glance)
	function getGlanceView() {
        return [ new MyGlanceView() ];
    }     

}

