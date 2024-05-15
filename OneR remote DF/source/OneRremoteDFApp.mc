using Toybox.Application;
using Toybox.BluetoothLowEnergy;
using BLEBarrel;
var bleDevice;

class OneRremoteDFApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state) {
		bleDevice = new BLEBarrel.BleDevice();
		BluetoothLowEnergy.setDelegate(bleDevice);
		bleDevice.open();
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    //! Return the initial view of your application here
    function getInitialView() {
        return [ new OneRremoteDFView(),new InputDelegate()];
    }

    function getSettingsView() {
        return [new OneRSettingsMenu(), new OneRSettingsDelegate()];
    }

}