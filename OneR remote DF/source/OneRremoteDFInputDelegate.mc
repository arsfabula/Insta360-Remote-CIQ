using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.Position;
using BLEBarrel;

class InputDelegate extends Ui.BehaviorDelegate {
//	hidden var bleDevice;
	var photoHeader = new [0]b;
	var photoFiller = new [0]b;
	var nbMode = 0;
	var maxNbMode = 14;

    function initialize() {
        BehaviorDelegate.initialize();
//        bleDevice = device;
    }

	function switchMode(nb) {
	    var header = new [0]b;
    	var filler = new [0]b;
    	var temp64 = new [0]b;
//      var info = Position.getInfo();
//    	var location = info.position.toDegrees();
  	
    	BLEBarrel.cmdStartRec = [0x12, 0, 0, 0, 0x4, 0, 0, 0x4, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x1]b;  // Start video Recording commmand
	 	BLEBarrel.cmdStopRec =  [0x12, 0, 0, 0, 0x4, 0, 0, 0x5, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x10, 0x1]b; // Stop recording command
//    	BLEBarrel.recState = BLEBarrel.stateStopRec;
    	BLEBarrel.videoMode = true;
		
        switch(nb) {
            case 0 : 
            	BLEBarrel.currentLabel = "5.7k / 30";
            	BLEBarrel.currentMode = BLEBarrel.cmdSet5k30;
            	break;  
            case 1 :
            	BLEBarrel.currentLabel = "5.7k / 25";
            	BLEBarrel.currentMode = BLEBarrel.cmdSet5k25;
            	break;
            case 2 :
            	BLEBarrel.currentLabel = "5.7k / 24";
            	BLEBarrel.currentMode = BLEBarrel.cmdSet5k24;
            	break;
            case 3 :
            	BLEBarrel.currentLabel = "4k / 30";
            	BLEBarrel.currentMode = BLEBarrel.cmdSet4k30;
            	break;
            case 4 :
            	BLEBarrel.currentLabel = "4k / 50";
            	BLEBarrel.currentMode = BLEBarrel.cmdSet4k50;
            	break;
            case 5 : 
            	BLEBarrel.currentLabel = "3k / 100";
            	BLEBarrel.currentMode = BLEBarrel.cmdSet3k100;
            	break;
            case 6 :
            	BLEBarrel.currentLabel = "Video HDR";
				// for HDR the start & stop commands are slightly differant
            	BLEBarrel.cmdStartRec[17] = 0x03;
            	BLEBarrel.cmdStartRec[7] = 0x04;
            	BLEBarrel.cmdStopRec[17] = 0x03;
            	BLEBarrel.cmdStopRec[7] = 0x05;
            	BLEBarrel.currentMode = BLEBarrel.cmdSetHDR;
            	break;
            case 7 :
            	BLEBarrel.currentLabel = "TimeLapse";
            	// for Timelapse the start & stop commands are slightly differant
            	BLEBarrel.cmdStartRec[7] = 0x16;
            	BLEBarrel.cmdStopRec[16] = 0x08;
            	BLEBarrel.cmdStopRec[7] = 0x17;
            	BLEBarrel.currentMode = BLEBarrel.cmdSetTL;
            	break;
            case 8 :
            	BLEBarrel.currentLabel = "BulletTime";
				// for Bullet time the start & stop commands are slightly differant
            	BLEBarrel.cmdStartRec[17] = 0x02;
            	BLEBarrel.cmdStopRec[17] = 0x02;
            	BLEBarrel.currentMode = BLEBarrel.cmdSetBullet;
            	break;
            case 9 :
            	BLEBarrel.currentLabel = "Photo";
            	// fill GPS position before sending command.
//            	header = [0x3f, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0xe3, 0x00, 0x00, 0x80, 0x00, 0x00, 0x12, 0x2d, 0x5a, 0x18]b;
//				filler = [0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
				// get GPS info for Photo mode
//				temp64 = BLEBarrel.BleDevice.toDouble(location[0]);
//				header.addAll(temp64);
//				temp64 = BLEBarrel.BleDevice.toDouble(location[1]);
//				header.addAll(temp64);
//				temp64 = BLEBarrel.BleDevice.toDouble(info.altitude);
//				header.addAll(temp64);
//				header.addAll(filler);
//				BLEBarrel.cmdSetPhoto = header;
				BLEBarrel.currentMode = BLEBarrel.cmdSetPhoto;
            	BLEBarrel.videoMode = false;
            	break;
            case 10 :
            	BLEBarrel.currentLabel = "Photo HDR";
            	BLEBarrel.currentMode = BLEBarrel.cmdSetPhotoHDR;
            	BLEBarrel.videoMode = false;
            	break;
            case 11 :
            	BLEBarrel.currentLabel = "Photo Burst";
            	BLEBarrel.currentMode = BLEBarrel.cmdSetPhotoBurst;
            	BLEBarrel.videoMode = false;
            	break;
            case 12 :
            	BLEBarrel.currentLabel = "Photo Interval";
            	// Intervall Photo is almost treated as a Timelapse video. 
            	BLEBarrel.currentMode = BLEBarrel.cmdSetInterval;
            	BLEBarrel.cmdStartRec[17] = 0x02;
            	BLEBarrel.cmdStartRec[7] = 0x16;
            	BLEBarrel.cmdStopRec[17] = 0x02;
            	BLEBarrel.cmdStopRec[16] = 0x08;
            	BLEBarrel.cmdStopRec[7] = 0x17;
				break;
			case 13 :
				BLEBarrel.currentLabel = "Night Shot";
            	BLEBarrel.currentMode = BLEBarrel.cmdSetNightShot;
            	BLEBarrel.videoMode = false;
            	break;
			case 14:
				BLEBarrel.currentLabel = "Standby";
				BLEBarrel.currentMode = "Standby";
				break;
			
         }   
//       	BLEBarrel.currentLabel = item.getLabel();
//        Sys.println("Menu Item:" + BLEBarrel.currentLabel + " cmd : " + BLEBarrel.currentMode);
//        Ui.popView(Ui.SLIDE_IMMEDIATE);
        mMessage = BLEBarrel.currentLabel + "\n" + "Tap Here";
		WatchUi.requestUpdate();
        
	
	}
	// Capture Start / Stop button event
    function onTap(evt) {
    	var x = evt.getCoordinates()[0];
		System.println(x + " Type " + evt.getType());
		if (x < width*0.15) {
			// menu left
//			System.println("left");
			nbMode-- ;
			if (nbMode < 0) {
				nbMode = maxNbMode;
			}
			switchMode(nbMode);
		} else if (x > width *0.85) {
		// menu right
//			System.println("Right");
			nbMode++ ;
			if (nbMode > maxNbMode) {
				nbMode = 0;
			}
			switchMode(nbMode);
		} else if (BLEBarrel.recState == BLEBarrel.stateStopRec) {
       		BLEBarrel.recState = BLEBarrel.stateStarting;
            mMessage = "Starting...";
            WatchUi.requestUpdate();
            if (BLEBarrel.videoMode) {
				if (!BLEBarrel.currentLabel.equals("Standby")) {
            		bleDevice.sendCMD(BLEBarrel.currentMode);
            		bleDevice.sendCMD(BLEBarrel.cmdApply);
				}
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
        return true;
    }
}