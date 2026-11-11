// Fork of ArsFabula's Insta360 Remote (MPL-2.0) — new UI, original BLE protocol.
using Toybox.Application;
using Toybox.BluetoothLowEnergy;
using Toybox.Position;
using Toybox.System;
using BLEBarrel;

var bleDevice;
// Written by the BLE module; the new view only uses it to spot "Busy...".
var mMessage = "";

class Main extends Application.AppBase {

	function initialize() {
		AppBase.initialize();
	}

	// onStart also runs for the glance. Bluetooth must only be started by the full app:
	// a glance calling setDelegate/scan steals the callbacks from the running app.
	function onStart(state) {
	}

	hidden function startBle() {
		if (bleDevice != null) { return; }
		bleDevice = new BLEBarrel.BleDevice();
		BluetoothLowEnergy.setDelegate(bleDevice);
		bleDevice.open();
	}

	// GPS overlay: location events only while the option is on AND the camera is a legacy one.
	// The X5 path never uses the position, so a saved GPSon = true must not run the watch's GPS.
	// The camera type is known once the scan has named it, so this is re-checked every tick.
	hidden var gpsActive = false;

	function gpsSync() {
		var want = BLEBarrel.GPSon && !BLEBarrel.isX5() && BLEBarrel.deviceName != null
			&& !BLEBarrel.deviceName.equals("n/a");
		if (want != gpsActive) {
			gpsActive = want;
			GPSenable(want);
		}
	}

	function GPSenable(on) {
		if (on) {
			if (Toybox.Position has :CONSTELLATION_GPS) {
				Position.enableLocationEvents({
					:acquisitionType => Position.LOCATION_CONTINUOUS,
					:constellations => [Position.CONSTELLATION_GPS]
				}, method(:onPosition));
			} else {
				Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
			}
		} else {
			Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
		}
	}

	function getInitialView() {
		startBle();
		return [new RemoteView(bleDevice), new RemoteDelegate(bleDevice)];
	}

	function onStop(state) {
		if (bleDevice != null) {
			bleDevice.close();
		}
	}

	function onPosition(info) {
		if (bleDevice != null) { bleDevice.sendPosition(info); }
	}

	(:glance :noDemo)
	function getGlanceView() {
		return [new RemoteGlance()];
	}
}
