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