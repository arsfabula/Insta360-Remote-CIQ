using Toybox.WatchUi;
using BLEBarrel;

// NOTE: the (:glance) class annotation is deliberately absent.
//
// On edge1040 (Epix Pro) an app that both depends on a monkey barrel and
// carries ANY (:glance) annotation crashes at startup with
//   Error: Illegal Access (Out of Bounds) / Failed invoking <symbol>
//   - onStart() at source/Main.mc  (the `new BLEBarrel.BleDevice()` line)
// Bisected against the real barrel: the annotation on THIS class alone, or on
// Main.getGlanceView() alone, is each enough to trigger it. A glance view with
// no barrel dependency runs fine, so it is the annotation+barrel combination,
// not the view itself.
//
// Glance still works: getGlanceView() on Main is picked up by signature, so no
// annotation is required for the glance view to appear and draw.
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