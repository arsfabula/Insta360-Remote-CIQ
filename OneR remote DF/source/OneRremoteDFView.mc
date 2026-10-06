using Toybox.WatchUi;
using Toybox.Activity;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Position;
using Toybox.System;
using Toybox.Time;
using BLEBarrel;

const vNum = "0.9.29";
var width as Lang.Number = 0;
var height as Lang.Number = 0;
var selectedFont as Graphics.FontDefinition = Graphics.FONT_LARGE;


class OneRremoteDFView extends WatchUi.DataField {

 
    function initialize() {
        DataField.initialize();
    }

    // The given info object contains all the current workout information.
    // Calculate a value and save it locally in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info as Activity.Info) as Void {
        // See Activity.Info in the documentation for available information.
        var GPSinfo = new Position.Info();

		if (info.currentLocationAccuracy == 0) {
			return;
		}
 		GPSinfo.altitude = info.altitude;
        GPSinfo.heading = info.currentHeading;
		GPSinfo.position = info.currentLocation;
		GPSinfo.speed = info.currentSpeed;
		GPSinfo.when = Time.now();

//        System.println("Compute GPS info " + GPSinfo.altitude);
        if (bleDevice != null) {
        	bleDevice.sendPosition(GPSinfo);
        }

    }
    function onLayout(dc as Graphics.Dc) as Void {
    	width = dc.getWidth();
    	height = dc.getHeight();
    	// fonts are numbered form 0 to 5 (XTINY to LARGE)
    	// Select the largest font possible
    	selectedFont = Graphics.FONT_LARGE;
    	var i = Graphics.FONT_LARGE;
    	for (i = selectedFont; i > Graphics.FONT_XTINY; i = (i - 1) as Graphics.FontDefinition) {
    		if (dc.getFontHeight(i)*5 > width) {
      			selectedFont = (i - 1) as Graphics.FontDefinition;
      		}
    		
    	}    		
    	for (i = selectedFont; i > Graphics.FONT_XTINY; i = (i - 1) as Graphics.FontDefinition) {
    		if (dc.getFontHeight(i)*2 > height) {
      			selectedFont = (i - 1) as Graphics.FontDefinition;
      		}
    		
    	}    		
    }

    // Display the value you computed here. This will be called
    // once a second when the data field is visible.
    function onUpdate(dc as Graphics.Dc) as Void {
    	var centerX = dc.getWidth()/2;
    	var centerY = dc.getHeight()/2;
    	var radius = centerX * 0.8;
    	
		if(dc has :setAntiAlias) {dc.setAntiAlias(true);}
		// Grey circle for standby, Red Circle for shooting.
        if (BLEBarrel.recState == BLEBarrel.stateStartRec) {
        	dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        } else {
        	dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        }
        dc.setPenWidth(width*0.08);
        dc.clear();
        dc.drawCircle(centerX,centerY,radius);
		// Draw arcs as buttons for selecting the shooting mode
        dc.setPenWidth(20);
        
		dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(centerX, centerY, centerX, Graphics.ARC_COUNTER_CLOCKWISE, 157, 202);
        dc.drawArc(centerX, centerY, centerX, Graphics.ARC_COUNTER_CLOCKWISE, 337, 22);
		dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0.05*centerX,centerY,selectedFont, "<", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);		
		dc.drawText(1.95*centerX,centerY,selectedFont, ">", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);		
		// Text with Shooting status, mode and timer.
        if (getBackgroundColor() == Graphics.COLOR_BLACK) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        }
//        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
		var head = BLEBarrel.mMessage.substring(0,4);
		if (head != null && head.equals("Scan")) {
        	dc.drawText(centerX, centerY, selectedFont, BLEBarrel.mMessage + "\n" + vNum, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
        	dc.drawText(centerX, centerY, selectedFont, BLEBarrel.mMessage, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
       }
     }

}