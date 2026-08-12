import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class PuffingBillyField extends WatchUi.DataField {

    private var _distanceM as Float;

    function initialize() {
        DataField.initialize();
        _distanceM = 0.0;
    }

    //! Called once per second with fresh activity data. Do the computation
    //! here, not in onUpdate() — onUpdate() is called on the device's own
    //! schedule, which on an AMOLED watch drops right off in low-power mode.
    function compute(info as Activity.Info) as Void {
        var d = info.elapsedDistance;
        _distanceM = (d == null) ? 0.0 : d;
    }

    //! Draw the field. `dc` covers only this field's slice of the screen, so
    //! everything is sized off getWidth()/getHeight() rather than the 390x390
    //! display — the same code has to work in a 1-, 2- or 4-field layout.
    function onUpdate(dc as Dc) as Void {
        var bg = getBackgroundColor();
        var fg = (bg == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;

        dc.setColor(bg, bg);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);

        dc.drawText(
            w / 2, h / 4, Graphics.FONT_XTINY, "PUFFING BILLY",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        dc.drawText(
            w / 2, h * 5 / 8, Graphics.FONT_NUMBER_MEDIUM,
            (_distanceM / 1000.0).format("%.2f"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }
}
