import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class PuffingBillyField extends WatchUi.DataField {

    //! 2**31 semicircles to 180 degrees. Gate coordinates arrive as integer
    //! semicircles and stay that way: it is cheaper to convert the one fix per
    //! second than the forty gate endpoints, and Number is cheaper to hold.
    private const DEG_TO_SEMI = 2147483648.0d / 180.0d;

    private var _names as Array<String>;
    private var _lengths as Array<Number>;
    private var _paces as Array<Float>;
    private var _gates as Array<Number>;

    //! Index of the gate being watched for, so equal to _names.size() once the
    //! last one has been crossed. Gates are tested one at a time and in order —
    //! this is a race on a known course, and testing only the next one is both
    //! cheaper and immune to a doubling-back section triggering a later gate.
    private var _next as Number;

    //! Previous fix, in semicircles. Held from the last compute() that had a
    //! fix, not simply the last compute(), so that a GPS dropout leaves a longer
    //! line to test against rather than a hole detection can fall through.
    private var _prevLat as Double?;
    private var _prevLon as Double?;

    private var _distanceM as Float;

    function initialize() {
        DataField.initialize();

        var data =
            Application.loadResource($.Rez.JsonData.Segments) as
            Dictionary<String, Array>;
        _names = data["names"] as Array<String>;
        _lengths = data["lengths"] as Array<Number>;
        _paces = data["paces"] as Array<Float>;
        _gates = data["gates"] as Array<Number>;

        _next = 0;
        _prevLat = null;
        _prevLon = null;
        _distanceM = 0.0;
    }

    //! Twice the signed area of the triangle abc, which is positive when c lies
    //! left of the directed line ab, negative when it lies right, and zero when
    //! the three are collinear. Only the sign is ever read.
    private function cross(
        ax as Double, ay as Double,
        bx as Double, by as Double,
        cx as Double, cy as Double
    ) as Double {
        return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    }

    //! Whether the step from (lon0, lat0) to (lon1, lat1) passed through gate i.
    //!
    //! Two segments cross exactly when each separates the other's endpoints,
    //! which is four cross products and a comparison of their signs. Working in
    //! semicircles rather than metres is fine and saves projecting: scaling an
    //! axis by a positive constant scales all four cross products by that same
    //! constant, leaving every sign — and so the result — untouched.
    private function crossedGate(
        i as Number,
        lon0 as Double, lat0 as Double,
        lon1 as Double, lat1 as Double
    ) as Boolean {
        // Four values per gate, left end then right end, each lat before lon.
        var ay = _gates[4 * i].toDouble();
        var ax = _gates[4 * i + 1].toDouble();
        var by = _gates[4 * i + 2].toDouble();
        var bx = _gates[4 * i + 3].toDouble();

        var d1 = cross(ax, ay, bx, by, lon0, lat0);
        var d2 = cross(ax, ay, bx, by, lon1, lat1);
        var d3 = cross(lon0, lat0, lon1, lat1, ax, ay);
        var d4 = cross(lon0, lat0, lon1, lat1, bx, by);

        return (d1 > 0) != (d2 > 0) && (d3 > 0) != (d4 > 0);
    }

    //! Called once per second with fresh activity data. Do the computation
    //! here, not in onUpdate() — onUpdate() is called on the device's own
    //! schedule, which on an AMOLED watch drops right off in low-power mode.
    function compute(info as Activity.Info) as Void {
        var d = info.elapsedDistance;
        _distanceM = (d == null) ? 0.0 : d;

        var loc = info.currentLocation;
        if (loc == null) {
            return;
        }

        var deg = loc.toDegrees();
        var lat = deg[0] * DEG_TO_SEMI;
        var lon = deg[1] * DEG_TO_SEMI;

        var prevLat = _prevLat;
        var prevLon = _prevLon;
        _prevLat = lat;
        _prevLon = lon;

        // Follow the position whether or not the timer is running, but only
        // count gates while it is. Tracking through a pause means restarting
        // somewhere else leaves no stale fix behind to draw a false crossing
        // from — the line tested is always one the runner actually ran.
        if (info.timerState != Activity.TIMER_STATE_ON) {
            return;
        }

        if (prevLat == null || prevLon == null || _next >= _names.size()) {
            return;
        }

        if (crossedGate(_next, prevLon, prevLat, lon, lat)) {
            System.println(
                "gate " + _next + " " + _names[_next] +
                " at " + (_distanceM / 1000.0).format("%.3f") + " km" +
                " (expected " + (_lengths[_next] / 1000.0).format("%.3f") + ")"
            );
            _next += 1;
        }
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
            w / 2, h / 4, Graphics.FONT_XTINY,
            (_next < _names.size()) ? _names[_next] : "FINISH",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        dc.drawText(
            w / 2, h * 5 / 8, Graphics.FONT_NUMBER_MEDIUM,
            (_distanceM / 1000.0).format("%.2f"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }
}
