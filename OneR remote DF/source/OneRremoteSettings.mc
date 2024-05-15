using Toybox.WatchUi as Ui;

class OneRSettingsMenu extends Ui.Menu2 {

    function initialize() {
        Menu2.initialize(null);
        Menu2.setTitle("Insta360 Mode");
		Menu2.addItem(new Ui.MenuItem("Start - Stop","","StartStop",{}));
		Menu2.addItem(new Ui.MenuItem("5.7k / 30","","5.7k30",{}));
		Menu2.addItem(new Ui.MenuItem("Photo HDR","","PhotoHDR",{}));
    }    
}