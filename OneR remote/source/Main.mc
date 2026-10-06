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

// NOTE: the (:glance) annotation is deliberately absent.
	//
	// On edge1040 (Epix Pro) an app that both depends on a monkey barrel and
	// carries ANY (:glance) annotation crashes at startup with
	//   Error: Illegal Access (Out of Bounds) / Failed invoking <symbol>
	//   - onStart() at source/Main.mc  (the `new BLEBarrel.BleDevice()` line)
	// The fault is in the link step, not in the glance view. Bisected against
	// the real barrel: the identical app passes with the annotation removed and
	// fails with it present, whether it sits on this method or on the
	// GlanceView class. A (:glance)-annotated app with no barrel dependency
	// runs fine, so it is specifically the annotation+barrel combination.
	// Verified with monkeydo on edge1040.
	//
	// Glance is unaffected: WatchUi.AppBase.getGlanceView() is picked up by
	// signature from the API (no annotation required), so the glance view
	// still appears and draws.
	function getGlanceView() {
        return [ new MyGlanceView() ];
    }     

}

