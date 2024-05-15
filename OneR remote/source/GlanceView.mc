using Toybox.WatchUi;

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

		dc.drawText(dc.getWidth()/2, 5, Graphics.FONT_TINY,mMessage, Graphics.TEXT_JUSTIFY_CENTER);

//		dc.drawText(dc.getWidth()/2, 5, Graphics.FONT_TINY,"Insta360 Remote", Graphics.TEXT_JUSTIFY_CENTER);
    } 
}

