using Toybox.Application;
using Toybox.BluetoothLowEnergy;
using Toybox.Lang;
using Toybox.WatchUi as Ui;
using BLEBarrel;
var bleDevice as BLEBarrel.BleDevice or Null = null;

class OneRremoteDFApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state) as Void {
		// The timer pool is not the data field's own: its free budget varies
		// by device, and on the reported Edge 840 (ERA, 20 nov. 2026,
		// BLEBarrel.armLinkAlarm:2076) nothing was left when the link built
		// its alarm - while the same build on the author's Edge Explore was
		// granted the Timer. The DF never asks. The link's five delayed
		// actions stay booked as dates; this host rings them from the data
		// field's own once-a-second cycle (OneRremoteDFView.compute ->
		// pumpLinkAsks). Named before the device opens: no ask may arm a
		// Timer before this.
		BLEBarrel.hostRingsTheBell = true;
		bleDevice = new BLEBarrel.BleDevice();
		BluetoothLowEnergy.setDelegate(bleDevice);
		bleDevice.open();
		BLEBarrel.mMessage = "Starting DF";
    }

    // onStop() is called when your application is exiting
    function onStop(state) as Void {
    }

    //! Return the initial view of your application here
    function getInitialView() {
        return [ new OneRremoteDFView(),new InputDelegate()];
    }

    function getSettingsView() {
        return [new OneRSettingsMenu(), new OneRSettingsDelegate()];
    }

}