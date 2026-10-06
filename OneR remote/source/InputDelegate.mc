using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.Position;
using BLEBarrel;

class InputDelegate extends Ui.BehaviorDelegate {
//	hidden var bleDevice;
	var photoHeader = new [0]b;
	var photoFiller = new [0]b;

    function initialize(device) {
        BehaviorDelegate.initialize();
        bleDevice = device;
    }

	// Capture Start / Stop button event
    function onSelect() {
 //   	var key = Ui.KeyEvent.getKey();
		var actionMenu = new Ui.Menu2({:title=>"Action"});
        actionMenu.addItem(new Ui.MenuItem("Stop","","Stop",{}));
        actionMenu.addItem(new Ui.MenuItem("Highlight","","Highlight",{}));
        actionMenu.addItem(new Ui.MenuItem("Track","","Track",{}));
//        actionMenu.addItem(new Ui.ToggleMenuItem("Lock","","Lock",locked,{}));

//  System.println("[input] Key "+key);
//        if (key == KEY_ENTER) {
            if (BLEBarrel.recState == BLEBarrel.stateStopRec) {
            	BLEBarrel.recState = BLEBarrel.stateStarting;
            	BLEBarrel.mMessage = "Starting...";
            	WatchUi.requestUpdate();
            	if (BLEBarrel.videoMode) {
            		// The camera drops a start that immediately follows a mode+apply
            		// whose mode did not actually change (no 0x65 confirmation), which
            		// is always the case here since currentMode is the persisted mode.
            		// A bare start records in the camera's current (already applied)
            		// mode - same as the working DF "Default Video" path.
            		bleDevice.sendCMD(BLEBarrel.cmdStartRec);
            	} else {
            	   	bleDevice.sendCMD(BLEBarrel.cmdApply);
            		bleDevice.sendCMD(BLEBarrel.currentMode);
            	}
            } else if (BLEBarrel.recState == BLEBarrel.stateStartRec) {
        		Ui.pushView(actionMenu, new actionDelegate(), Ui.SLIDE_IMMEDIATE);
        	} else {
        		// Starting or Stopping a recording might take time. 
        		// Do nothing until recording has started or stopped. 
				// to debug allow a second time the menu to appear...
       			Ui.pushView(actionMenu, new actionDelegate(), Ui.SLIDE_IMMEDIATE);
       			BLEBarrel.recState = BLEBarrel.stateStopRec;
        	}
//		}
        return false;
    }
    

    function onMenu() {
        var menu = new Ui.Menu2({:title=>"Settings"});

		// Build menu according to device 
		switch (BLEBarrel.menuLevel) {
			case 0:
				break;
			case 1:
				menu.addItem(new Ui.MenuItem("5.7K / 30","","5k30",{}));
        		menu.addItem(new Ui.MenuItem("5.7K / 25","","5k25",{}));
        		menu.addItem(new Ui.MenuItem("5.7K / 24","","5k24",{}));
        		menu.addItem(new Ui.MenuItem("4K / 50","","4k50",{}));
        		menu.addItem(new Ui.MenuItem("4K / 30","","4k30",{}));
        		menu.addItem(new Ui.MenuItem("HDR Video","","HDR",{}));
        		menu.addItem(new Ui.MenuItem("Timelapse","","TimeLapse",{}));
        		menu.addItem(new Ui.MenuItem("Bullet Time","","BulletTime",{}));
        		menu.addItem(new Ui.MenuItem("Photo","","Photo",{}));
        		menu.addItem(new Ui.MenuItem("Photo HDR","","PhotoHDR",{}));
        		menu.addItem(new Ui.MenuItem("Photo Burst","","PhotoBurst",{}));
        		menu.addItem(new Ui.MenuItem("Photo Interval","","PhotoInterval",{}));
        		menu.addItem(new Ui.MenuItem("Night Shot","","NightShot",{}));
				break;
			case 2:
				menu.addItem(new Ui.MenuItem("8K / 30","","8k30",{}));
				menu.addItem(new Ui.MenuItem("5.7K / 30","","5k30",{}));
        		menu.addItem(new Ui.MenuItem("5.7K / 25","","5k25",{}));
        		menu.addItem(new Ui.MenuItem("5.7K / 24","","5k24",{}));
        		menu.addItem(new Ui.MenuItem("4K / 50","","4k50",{}));
        		menu.addItem(new Ui.MenuItem("4K / 30","","4k30",{}));
        		menu.addItem(new Ui.MenuItem("HDR Video","","HDR",{}));
        		menu.addItem(new Ui.MenuItem("Timelapse","","TimeLapse",{}));
        		menu.addItem(new Ui.MenuItem("Bullet Time","","BulletTime",{}));
        		menu.addItem(new Ui.MenuItem("Photo","","Photo",{}));
        		menu.addItem(new Ui.MenuItem("Photo HDR","","PhotoHDR",{}));
        		menu.addItem(new Ui.MenuItem("Photo Burst","","PhotoBurst",{}));
        		menu.addItem(new Ui.MenuItem("Photo Interval","","PhotoInterval",{}));
        		menu.addItem(new Ui.MenuItem("Night Shot","","NightShot",{}));
		}
        
        if (BLEBarrel.GPSon) {
        	menu.addItem(new Ui.MenuItem("GPS OFF","","GPSon",{}));
        } else {
        	menu.addItem(new Ui.MenuItem("GPS ON","","GPSon",{}));
		} 
		menu.addItem(new Ui.MenuItem("Default Video","","DefaultV",{}));
        
        Ui.pushView(menu, new Menu2Delegate(), Ui.SLIDE_IMMEDIATE);
        
        return true;
    }

}


class Menu2Delegate extends Ui.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

function onSelect(item) as Void {
  	  	var info = null; 
    	var location = null;
		var itemID = "";
		var chglbl = true; 
   	
   		if (BLEBarrel.GPSon) {
       		info = Position.getInfo();
       		// With GPS on but no fix, getInfo() still succeeds and .position is
       		// Null; toDegrees() on that Null raised "Unexpected Type Error".
       		if ((info != null) && (info.position != null)) {
        		location = info.position.toDegrees();
        		if ((location == null) || (location.size() < 2)) {
        			location = null;
        		}
        	} else {
        		location = null;
        		}
   		}
		
    	BLEBarrel.cmdStartRec = [0x12, 0, 0, 0, 0x4, 0, 0, 0x4, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x1]b;  // Start video Recording commmand
	 	BLEBarrel.cmdStopRec =  [0x12, 0, 0, 0, 0x4, 0, 0, 0x5, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x10, 0x1]b; // Stop recording command
    	BLEBarrel.recState = BLEBarrel.stateStopRec;
    	BLEBarrel.videoMode = true;
		
		itemID = item.getId();
        switch(itemID) {
            case "8k30" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSet8k30;
            	break;  
            case "5k30" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSet5k30;
            	break;  
            case "5k25" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSet5k25;
            	break;
            case "5k24" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSet5k24;
            	break;
            case "4k30" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSet4k30;
            	break;
            case "4k50" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSet4k50;
            	break;
            case "3k100" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSet3k100;
            	break;
            case "HDR" :
				// for HDR the start & stop commands are slightly differant
            	BLEBarrel.cmdStartRec[17] = 0x03;
            	BLEBarrel.cmdStartRec[7] = 0x04;
            	BLEBarrel.cmdStopRec[17] = 0x03;
            	BLEBarrel.cmdStopRec[7] = 0x05;
            	BLEBarrel.currentMode = BLEBarrel.cmdSetHDR;
            	break;
            case "TimeLapse" :
            	// for Timelapse the start & stop commands are slightly differant
            	BLEBarrel.cmdStartRec[7] = 0x16;
            	BLEBarrel.cmdStopRec[16] = 0x08;
            	BLEBarrel.cmdStopRec[7] = 0x17;
            	BLEBarrel.currentMode = BLEBarrel.cmdSetTL;
            	break;
            case "BulletTime" :
				// for Bullet time the start & stop commands are slightly differant
            	BLEBarrel.cmdStartRec[17] = 0x02;
            	BLEBarrel.cmdStopRec[17] = 0x02;
            	BLEBarrel.currentMode = BLEBarrel.cmdSetBullet;
            	break;
case "Photo" :
if ((BLEBarrel.GPSon) && (location != null) && (info != null)) {
    	// fill GPS position before sending command.
				BLEBarrel.cmdSetPhoto = bleDevice.photoGpsHeader(location[0], location[1], info.altitude);
 			}
				BLEBarrel.currentMode = BLEBarrel.cmdSetPhoto;
            	BLEBarrel.videoMode = false;
            	break;
            case "PhotoHDR" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSetPhotoHDR;
            	BLEBarrel.videoMode = false;
            	break;
            case "PhotoBurst" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSetPhotoBurst;
            	BLEBarrel.videoMode = false;
            	break;
            case "PhotoInterval" :
            	// Intervall Photo is almost treated as a Timelapse video. 
            	BLEBarrel.currentMode = BLEBarrel.cmdSetInterval;
            	BLEBarrel.cmdStartRec[17] = 0x02;
            	BLEBarrel.cmdStartRec[7] = 0x16;
            	BLEBarrel.cmdStopRec[17] = 0x02;
            	BLEBarrel.cmdStopRec[16] = 0x08;
            	BLEBarrel.cmdStopRec[7] = 0x17;
				break;
			case "NightShot" :
            	BLEBarrel.currentMode = BLEBarrel.cmdSetNightShot;
            	BLEBarrel.videoMode = false;
            	break;
			case "GPSon" :
            	BLEBarrel.GPSon = !BLEBarrel.GPSon;
             	mainApp.GPSenable(BLEBarrel.GPSon);
				chglbl = false;
             	break;
			case "DefaultV" :
				BLEBarrel.currentMode = "DefaultV";
         }
		// Name of mode to be displayed. 
        if (chglbl) {
			Sys.println("item ID:" + itemID);
			BLEBarrel.currentLabel = item.getLabel();
		}
		// Apply changes. 
        if (!BLEBarrel.currentMode.equals("DefaultV")) {
			Sys.println("Apply changes");
			bleDevice.sendCMD(BLEBarrel.currentMode);
        	bleDevice.sendCMD(BLEBarrel.cmdApply);
		}
         
       	Sys.println("Menu ID + Name: " + itemID + ":" + BLEBarrel.currentLabel + " cmd : " + BLEBarrel.currentMode);
        Ui.popView(Ui.SLIDE_IMMEDIATE);
        BLEBarrel.mMessage = BLEBarrel.currentLabel + "\n" + BLEBarrel.startMessage;
		WatchUi.requestUpdate();
        
   }
   	function onPosition(info) {
//		System.println("[onPosition]");
		bleDevice.sendPosition(info);
	}
   
}

class actionDelegate extends Ui.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
		
        switch(item.getId()) {
            case "Stop" :
            	BLEBarrel.recState = BLEBarrel.stateStopping;
            	BLEBarrel.mMessage = "Stopping...";
              	bleDevice.sendCMD(BLEBarrel.cmdStopRec);
            	break;  
            case "Highlight" :
            	bleDevice.sendCMD(BLEBarrel.cmdHighlight);
               	break;  
            case "Track" :
            	bleDevice.sendCMD(BLEBarrel.cmdTrackThat);
            	break;
         }   
        // Sys.println("[Menu] Actions" );
		WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.requestUpdate();
   }
}
