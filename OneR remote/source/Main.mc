using Toybox.Application;
using Toybox.BluetoothLowEnergy;
using Toybox.Position;
using Toybox.System;
using BLEBarrel;

var bleDevice;


class Main extends Application.AppBase {
//	hidden var bleDevice;

	function initialize() {
		AppBase.initialize();
	}

	function onStart(state) {
		bleDevice = new BLEBarrel.BleDevice();
		// Connect to camera
		BluetoothLowEnergy.setDelegate(bleDevice);
		bleDevice.open();
		// System.println("[Main] on start: " + BLEBarrel.GPSon);
		GPSenable(BLEBarrel.GPSon);
		
		return false;
	}
	
	function GPSenable (state) {
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

	function onStop(state) {
		bleDevice.close();
		return false;
	}
	
	function onPosition(info) {
		System.println("[onPosition]");
		bleDevice.sendPosition(info);
	}

(:glance)    
	function getGlanceView() {
        return [ new MyGlanceView() ];
    }     

}

