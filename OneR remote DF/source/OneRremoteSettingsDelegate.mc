using Toybox.WatchUi as Ui;
using Toybox.Lang;
using Toybox.System as Sys;
using Toybox.Application as App;
using BLEBarrel;

var CHmenu as Lang.Object or Null = null;
// var state;

// Menu principal (Pénalité, Horaire, Remise à Zero)
class OneRSettingsDelegate extends Ui.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as Ui.MenuItem) as Void {
    	Sys.println("[OnSelect - Main]");
        switch(item.getId() as Lang.String) {
    	case "StartStop" :
            var dev = bleDevice;
            if (dev != null) {
	            if (BLEBarrel.recState == BLEBarrel.stateStopRec) {
    		    	BLEBarrel.recState = BLEBarrel.stateStarting;
                	BLEBarrel.mMessage = "Starting...";
//                 	WatchUi.requestUpdate();
if (BLEBarrel.videoMode) {
                	// "Default Video" leaves currentMode as the string "DefaultV" and
                	// not a command, so it must not be sent. Same guard as the OneR
                	// Remote InputDelegate: start the capture, leave the camera
                	// settings alone.
            		if (BLEBarrel.currentMode instanceof Lang.ByteArray) {
            	    		dev.sendCMD(BLEBarrel.currentMode as Lang.ByteArray);
            		}
            	    		dev.sendCMD(BLEBarrel.cmdApply);
            		dev.sendCMD(BLEBarrel.cmdStartRec);
                	} else {
                		if (BLEBarrel.currentMode instanceof Lang.ByteArray) {
                	    dev.sendCMD(BLEBarrel.cmdApply);
                	    dev.sendCMD(BLEBarrel.currentMode as Lang.ByteArray);
                		}
                	}
	            } else if (BLEBarrel.recState == BLEBarrel.stateStartRec) {
        		    BLEBarrel.recState = BLEBarrel.stateStopping;
            	    BLEBarrel.mMessage = "Stopping...";
            	    dev.sendCMD(BLEBarrel.cmdStopRec);
	            } else {
        			// Starting or Stopping a recording might take time.
        			// Do nothing until recording has started or stopped.
    				// to debug allow a second time the menu to appear...
	            }
            }
			break;
		case "5.7k30" :
		    switchMode(0);
			break;
		case "PhotoHDR" :
			switchMode(10);
			break;
		case "item_horaire" :
			break;
		case "item_nbCH" :
            break;
		}
        BLEBarrel.mMessage = BLEBarrel.currentLabel;
        Ui.popView(Ui.SLIDE_IMMEDIATE);
	}

	function onBack() as Void {
	    Sys.println("[onBack - Main]");
        Ui.popView(Ui.SLIDE_IMMEDIATE);
	}

}
