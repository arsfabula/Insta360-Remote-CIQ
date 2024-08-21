using Toybox.WatchUi;
using Toybox.System;
using BLEBarrel;
var mMessage = "Starting Widget";
const vNum = "0.9.69";


class ViewData extends WatchUi.View {
	hidden var bleDevice;

    function initialize(device) {
        WatchUi.View.initialize();
		bleDevice = device;
    }

    function onUpdate(dc) {
    	var centerX = dc.getWidth()/2;
    	var centerY = dc.getHeight()/2;
    	var radius = centerX;
    	
		if(dc has :setAntiAlias) {dc.setAntiAlias(true);}
    	if (radius > centerY) {
    		radius = centerY;
    	}
		// Grey circle for standby, Red Circle for shooting.
        if (BLEBarrel.recState == BLEBarrel.stateStartRec) {
        	dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_BLACK);
        } else {
        	dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        }
        dc.setPenWidth(15);
        dc.clear();
        dc.drawCircle(centerX,centerY,radius - 20 );
		System.println("[VIEW] onupdate GPS: " + BLEBarrel.GPSon);
		if (BLEBarrel.GPSon) {
			// Draw some chevrons for GPS signal Quality
        	if (BLEBarrel.GPSaccuracy == Position.QUALITY_NOT_AVAILABLE) {
        		dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        	} else if (BLEBarrel.GPSaccuracy == Position.QUALITY_POOR) {
        		dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_BLACK);
			} else if ((BLEBarrel.GPSaccuracy == Position.QUALITY_GOOD) or (BLEBarrel.GPSaccuracy == Position.QUALITY_USABLE))   {
        		dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
			}         
        	dc.drawArc(centerX, centerY, radius - 20, Graphics.ARC_COUNTER_CLOCKWISE, 70, 110);
        	dc.drawArc(centerX, centerY, radius - 37, Graphics.ARC_COUNTER_CLOCKWISE, 70, 110);
        	dc.drawArc(centerX, centerY, radius - 54, Graphics.ARC_COUNTER_CLOCKWISE, 70, 110);
        }
		// Text with Shooting status, mode and timer.
		// mMessage = vNum + "\n" + mMessage;
       	dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
		if (mMessage.substring(0,4).equals("Scan")) {
			dc.drawText(centerX, centerY, Graphics.FONT_SMALL, mMessage + "\n" + vNum, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
        	dc.drawText(centerX, centerY, Graphics.FONT_MEDIUM, BLEBarrel.deviceName + "\n" + mMessage, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    	}
	}

	function compute(info) {

		if (bleDevice.scanning) {
			return "Scanning...";
		} else if (bleDevice.device == null) {
			return "Disconnected";
		}



		return true;
	}
}
