using Toybox.WatchUi;

// Decision (17 nov. 2026): the glance is PASSIVE. This class draws one static
// line - the app name - and holds nothing of the barrel: no mMessage read as
// this class used to do, no BLE, no reference that would pull the barrel into
// the glance-side slice of the PRG. The shape of items 152/154/155 (three
// annotated sites, the delegate class among them) is dropped: it gave the
// glance process a slice measured at 58 402 octets the 17 nov. (PRG head,
// marqexpedition: glance_code_offset 44 747 / glance_data_offset 13 655),
// while the SDK's Glances page names the pool given to a glance 32 Ko "for
// most devices" - the marq-generation of the widget class died at the very
// boot there ("Encountered an app crash", no stack). The shape written here
// measures 5 501 octets (head glance_code 1 557 / glance_data 3 944) and its
// start was traced alive on the simulators of marqexpedition and
// epix2pro51mm: onStart, getGlanceView and onUpdate all answer, nothing faults.
// The built app of this very shape measures the 5 501 o minus its probes: the
// shipped PRG head answers glance_code_offset 1 473 / glance_data_offset 3 734,
// 5 207 o of slice.
// Why the view stays instead of nothing at all: a widget that answers no
// getGlanceView cannot be added to the loop on a real epix pro Gen 2 51mm
// (bench of the 17 nov. - the app itself ran, the entry was refused), and the
// SDK docs answer the same for API >= 4.0.0 devices; the default name-only
// glance belongs to the generations before 4.0.0 only.
// This class starts because the lines marked "Decision (17 nov. 2026)" in
// Main.onStart, Main.getInitialView and BLE Barrel\BLEBarrel.mc keep the
// barrel out of the boot process and out of this view. It is the rule the
// PR's own page already wrote (docs/x5-pr-app/watch-app.md, "start BLE only
// from getInitialView"); the app code had drifted from it, this decision ends
// the drift.
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

		dc.drawText(dc.getWidth()/2, 5, Graphics.FONT_TINY,"Insta360 Remote", Graphics.TEXT_JUSTIFY_CENTER);
    }
}
