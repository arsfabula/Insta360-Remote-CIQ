using Toybox.WatchUi;
using BLEBarrel;

// Datum of the workstation (same run, verified with monkeydo on edge1040, and kept beside
// the fuller words at Main.mc): an app that both depends a monkey barrel and carries ANY
// (:glance) annotation crashed at startup at onStart(); the annotation on THIS class alone
// or on Main.getGlanceView() alone was each enough to trigger it, and the same view with
// no barrel dependency ran fine. A datum about that device and that build, not a reason
// to leave the annotation off.
//
// Decision (Cahier item 152): the annotation is restored, so the glance process gets its
// own slice of the PRG instead of the whole application - the prefix qualifier form the
// SDK documents for a process scope. With it the PRG head answers a non-zero glance_code
// and glance_data offset, and the build drops the "loaded as a glance process" warning.
// Decision (Cahier item 155): the annotation is ON, as one of THREE sites. The decision also sits on
// Main.getGlanceView() and, the third, on the barrel: `BLE Barrel\BLEBarrel.mc:381`, before the
// `class BleDevice extends BluetoothLowEnergy.BleDelegate` it declares at :382. Three sites and not two:
// with only the two of this app, the simulator of the Epix 2 Pro 51mm crashed at Main.mc:23 (the `new
// BLEBarrel.BleDevice()` line, Error: Illegal Access (Out of Bounds) / Failed invoking <symbol>, Cahier
// item 154); with the class the app constructs at onStart() taken into the glance process, it starts.
// The words below are the datum of the workstation that had kept its own words about edge1040, never a
// verdict, and not a reason to leave this annotation off.
(:glance)
class MyGlanceView extends WatchUi.GlanceView
{

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc) {
		dc.setColor(Graphics.COLOR_BLACK,Graphics.COLOR_BLACK);
		dc.clear();
		dc.setColor(Graphics.COLOR_WHITE,Graphics.COLOR_TRANSPARENT);

		dc.drawText(dc.getWidth()/2, 5, Graphics.FONT_TINY, BLEBarrel.mMessage, Graphics.TEXT_JUSTIFY_CENTER);

//		dc.drawText(dc.getWidth()/2, 5, Graphics.FONT_TINY,"Insta360 Remote", Graphics.TEXT_JUSTIFY_CENTER);
    }
}