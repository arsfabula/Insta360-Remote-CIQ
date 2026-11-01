using Toybox.WatchUi;
using Toybox.System;
using Toybox.Math;
using BLEBarrel;
const vNum = "0.9.96";


class ViewData extends WatchUi.View {
	hidden var bleDevice;
	// var metricsPrinted = false;  // only the commented print below needs it (item 145)

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
        // Display decision (item 146): the ring of the RECORDING is a bit smaller than it was, while the
        // standby ring keeps its old path; the path is named so the marker of the walk can sit on the
        // same circle.
        var ringPath = radius - 20;
        if (BLEBarrel.recState == BLEBarrel.stateStartRec) {
            ringPath = radius - 26;
        }
        dc.drawCircle(centerX,centerY,ringPath );
		if (BLEBarrel.GPSon) {
			// Draw some chevrons for GPS signal Quality
        	if (BLEBarrel.GPSaccuracy == Position.QUALITY_NOT_AVAILABLE) {
        		dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        	} else if (BLEBarrel.GPSaccuracy == Position.QUALITY_POOR) {
        		dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_BLACK);
			} else if ((BLEBarrel.GPSaccuracy == Position.QUALITY_GOOD) or (BLEBarrel.GPSaccuracy == Position.QUALITY_USABLE))   {
        		dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
			}         
        	// Display decision (item 149): the wedge of the GPS follows the path of the ring, so it never
        	// hangs outside it; the two inner arcs keep the old step of 17 pixels between them.
        	dc.drawArc(centerX, centerY, ringPath, Graphics.ARC_COUNTER_CLOCKWISE, 70, 110);
        	dc.drawArc(centerX, centerY, ringPath - 17, Graphics.ARC_COUNTER_CLOCKWISE, 70, 110);
        	dc.drawArc(centerX, centerY, ringPath - 34, Graphics.ARC_COUNTER_CLOCKWISE, 70, 110);
        }
		// Text with Shooting status, mode and timer.
       	dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
		if (BLEBarrel.mMessage.substring(0,4).equals("Scan")) {
			dc.drawText(centerX, centerY, Graphics.FONT_SMALL, BLEBarrel.mMessage + "\n" + vNum, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
        	var nameFont = Graphics.FONT_XTINY;
        	var msgFont = Graphics.FONT_MEDIUM;
        	var nameTxt = BLEBarrel.deviceName;
        	var msgTxt = BLEBarrel.mMessage;
        	// The message is two lines, the label of the mode and the line of the start: they are drawn
        	// one by one, never as one string of several lines, because one drawText of several lines
        	// uses the internal leading of the target and the artefact that did so let the label line
        	// climb over the name line. The gallery of the SDK has no indexOf on a String (only on an
        	// Array and a ByteArray), so the newline is located with length and substring, both named
        	// since 1.0.0.
        	var msgChars = msgTxt.length();
        	var nl = null;
        	for (var k = 1; k < msgChars; k = k + 1) {
        		// The test is .equals(), never ==: note 9 says == on a String compares object identity on this
        		// target, so a comparison against a newline literal answers false for every position.
        		if (nl == null && msgTxt.substring(k - 1, k).equals("\n")) {
        			nl = k - 1;
        		}
        	}
        	var msg1 = msgTxt;
        	var msg2 = null;
        	var msgLines = 1;
        	if (nl != null) {
        		msg1 = msgTxt.substring(0, nl);
        		msg2 = msgTxt.substring(nl + 1, msgChars);
        		msgLines = 2;
        	}
        	// The console reading of this artefact names the boxes of the fonts of this target at their
        	// boundary: 33 for FONT_XTINY, 45 for FONT_TINY, 51 for FONT_SMALL, 59 for FONT_MEDIUM, 65 for
        	// FONT_LARGE, and the ascent and descent of the two fonts the draws ask for. The boxes are read
        	// with one-argument calls: getFontAscent and getFontDescent, both since 1.2.0, add to the height
        	// the same calls name. The ladder answers the size question: FONT_TINY at 45 was only a hair of
        	// the 59 of the message font, so the name now asks FONT_XTINY at 33.
        	var nameBox = Graphics.getFontAscent(nameFont) + Graphics.getFontDescent(nameFont);
        	var msgBox = Graphics.getFontAscent(msgFont) + Graphics.getFontDescent(msgFont);
        	// Boxes that only touch are not enough: the target paints an opaque box of its background colour
        	// behind each line, which is taller than the box the calls name, and that box is what ate the
        	// lower part of the name line last time. So the name is given a band as tall as a whole line of
        	// the message font, and each of the two boundaries gets the descent of the message font as its
        	// leading, the part of a line that hangs under its baseline.
        	// The band never shrinks below the box of the name's own font.
        	var nameBand = msgBox;
        	if (nameBox > msgBox) {
         		// the name's font asks a taller line than the message font, so its own box is the band
         		nameBand = nameBox;
        	}
        	var lead = Graphics.getFontDescent(msgFont);
        	var top = centerY - (nameBand + msgLines * (msgBox + lead)) / 2;
        	var yName = top + nameBand / 2;
        	var yMsg1 = top + nameBand + lead + msgBox / 2;
        	var yMsg2 = yMsg1 + lead + msgBox;
        	// KEPT AS A COMMENT, NOT COMPILED (item 145): this print was the pin that tied a pasted screen to an
        	// artefact, and items 141 to 144 record the readings it answered, the font ladder of this target (33, 45,
        	// 51, 59, 65) and the three y's the draws use. A decision asked for a clean console, so the block is out
        	// of the artefact and no paste answers it any more; a decision that needs to read the boxes again puts this
        	// block back and re-pins the view.
        	// // The artefact of this decision still let the name line climb over the label line and did not
        	// // read the name as smaller, so the boxes it was measured from are now read at the boundary
        	// // they belong to: the console prints, once per run, the box of every font of the ladder of
        	// // this target, the ascent and descent of the two fonts the draws ask for, and the three y
        	// // the draws will use. The screen is an eye and this print is a reading of the display of
        	// // the artefact: it belongs to no rung and to no acceptance. Each sentence is one statement,
        	// // because the newline ends a statement for this language.
        	// if (!metricsPrinted) {
        	// 	metricsPrinted = true;
        	// 	var info = "[view] screen " + dc.getWidth() + "x" + dc.getHeight() + " centerY " + centerY;
        	// 	info = info + " boxes XTINY " + Graphics.getFontHeight(Graphics.FONT_XTINY);
        	// 	info = info + " TINY " + Graphics.getFontHeight(Graphics.FONT_TINY);
        	// 	info = info + " SMALL " + Graphics.getFontHeight(Graphics.FONT_SMALL);
        	// 	info = info + " MEDIUM " + Graphics.getFontHeight(Graphics.FONT_MEDIUM);
        	// 	info = info + " LARGE " + Graphics.getFontHeight(Graphics.FONT_LARGE);
        	// 	info = info + " name a/d " + Graphics.getFontAscent(nameFont) + "/" + Graphics.getFontDescent(nameFont);
        	// 	info = info + " msg a/d " + Graphics.getFontAscent(msgFont) + "/" + Graphics.getFontDescent(msgFont);
        	// 	info = info + " y " + yName + "/" + yMsg1 + "/" + yMsg2;
        	// 	System.println(info);
        	// }
        	// Display decision: the device name line is drawn smaller than the two message lines, which
        	// keep their words, their size and their two lines. The TextJustification enum of this
        	// target has CENTER, LEFT, RIGHT and VCENTER and no TOP, so each line is placed by its own
        	// centre.
        	dc.drawText(centerX, yName, nameFont, nameTxt, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        	dc.drawText(centerX, yMsg1, msgFont, msg1, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        	if (msg2 != null) {
        		dc.drawText(centerX, yMsg2, msgFont, msg2, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        	}
    	}
     	// Display decision (item 146): while the camera is recording, a small red circle with a black
     	// centre walks around the ring like the hand of a watch: it starts at the top and comes back to
     	// the top in sixty seconds, one step of six degrees per second. The seconds are the SAME reading
     	// the printed timer is built from - elapsedRecTime at the barrel - so the marker and the words of
     	// the screen agree, and at "0:00:16" the centre sits at 96 degrees from the top. sin and cos take
     	// RADIANS (the gallery names the parameter "The angle in radians" and there is no degrees form),
     	// and drawCircle paints a ring at the pen width, never a filled disc: the black disc is painted
     	// first so it hides the big ring behind the marker, and the red ring is painted over it. The sizes
     	// are knobs of the eye, whose gate is the capture and never a rung.
     	if (BLEBarrel.recState == BLEBarrel.stateStartRec) {
     		var recSecs = 0;
     		if (BLEBarrel.elapsedRecTime != null) {
     			recSecs = BLEBarrel.elapsedRecTime.value() % 60;
     		}
     		var angle = recSecs * Math.PI / 30;
     		var mx = centerX + ringPath * Math.sin(angle);
     		var my = centerY - ringPath * Math.cos(angle);
     		var markerR = 11;
     		var fillR = 4;
     		dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
     		dc.setPenWidth(2 * fillR + 2);
     		dc.drawCircle(mx, my, fillR);
     		dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_BLACK);
     		dc.setPenWidth(4);
     		dc.drawCircle(mx, my, markerR);
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
