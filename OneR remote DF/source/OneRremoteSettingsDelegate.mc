using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.Application as App;

var CHmenu;
// var state;

// Menu principal (P�nalit�, Horaire, Remise � Zero)
class OneRSettingsDelegate extends Ui.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
    Sys.println("[OnSelect - Main]");
        switch(item.getId()) {
    	case "StartStop" :
            if (BLEBarrel.recState == BLEBarrel.stateStopRec) {
       		    	BLEBarrel.recState = BLEBarrel.stateStarting;
                	mMessage = "Starting...";
//                	WatchUi.requestUpdate();
                	if (BLEBarrel.videoMode) {
            	    	bleDevice.sendCMD(BLEBarrel.currentMode);
            	    	bleDevice.sendCMD(BLEBarrel.cmdApply);
            	    	bleDevice.sendCMD(BLEBarrel.cmdStartRec);
                	} else {
               	    	bleDevice.sendCMD(BLEBarrel.cmdApply);
            	    	bleDevice.sendCMD(BLEBarrel.currentMode);
                	}
            } else if (BLEBarrel.recState == BLEBarrel.stateStartRec) {
        		    BLEBarrel.recState = BLEBarrel.stateStopping;
            	    mMessage = "Stopping...";
            	    bleDevice.sendCMD(BLEBarrel.cmdStopRec);
            } else {
        		// Starting or Stopping a recording might take time. 
        		// Do nothing until recording has started or stopped. 
				// to debug allow a second time the menu to appear...
            }
			break;
		case "5.7k30" :
		    InputDelegate.switchMode(0);
			break;
		case "PhotoHDR" :
			InputDelegate.switchMode(10);
			break;
		case "item_horaire" :
			break;
		case "item_nbCH" :	
            break;
		}
        mMessage = BLEBarrel.currentLabel;
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
	
		return true;
	}

	function onBack() {
	    Sys.println("[onBack - Main]");
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
		return false;
    }

}