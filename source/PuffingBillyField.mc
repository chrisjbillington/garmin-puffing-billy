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

    //! How far past a gate the runner may get before we give up waiting for it
    //! and move on. Gates are only ever tested in order, so without this one
    //! missed gate — a long GPS dropout, a wide detour around the course —
    //! would stall every later one for the rest of the race.
    private const OVERDISTANCE_M = 200.0;

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

    //! Odometer reading at the start of the current segment, so that the
    //! distance still to run is measured from the last gate rather than from
    //! the start of the race. The odometer drifts against the course — about
    //! 1-2% on a real watch, far more under simulated GPS — and measuring each
    //! segment fresh keeps that drift from compounding over thirteen km.
    private var _segmentStartM as Float;

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
        _segmentStartM = 0.0;
    }

    //! Distance still to run in this segment, in metres. Goes negative once the
    //! runner is past where the gate should have been but has not yet crossed
    //! it — which is the normal case for a metre or two, since the odometer and
    //! the course never agree exactly.
    private function remainingM() as Float {
        return _lengths[_next] - (_distanceM - _segmentStartM);
    }

    //! Move on to the next segment.
    //!
    //! `startM` is the odometer reading to treat as the boundary: the reading
    //! at the moment of crossing when a gate actually fired, or the nominal one
    //! when we gave up on it. Using the nominal in that case keeps the whole
    //! OVERDISTANCE_M of slop from being charged to the following segment.
    private function advance(startM as Float, reason as String) as Void {
        System.println(
            "gate " + _next + " " + _names[_next] + " " + reason +
            " at " + (_distanceM / 1000.0).format("%.3f") + " km" +
            " (" + (_distanceM - _segmentStartM - _lengths[_next]).format("%+.0f") +
            " m against segment)"
        );
        _segmentStartM = startM;
        _next += 1;
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

        var prevLat = _prevLat;
        var prevLon = _prevLon;

        var loc = info.currentLocation;
        if (loc != null) {
            var deg = loc.toDegrees();
            _prevLat = deg[0] * DEG_TO_SEMI;
            _prevLon = deg[1] * DEG_TO_SEMI;
        }

        // Follow the position whether or not the timer is running, but only
        // count gates while it is. Tracking through a pause means restarting
        // somewhere else leaves no stale fix behind to draw a false crossing
        // from — the line tested is always one the runner actually ran.
        if (info.timerState != Activity.TIMER_STATE_ON || _next >= _names.size()) {
            return;
        }

        // Guarded on loc as well as on the coordinates: without a fix this
        // second, _prevLat and _prevLon still hold the previous one, and
        // testing that point against itself is a zero-length segment.
        var lat = _prevLat;
        var lon = _prevLon;
        if (loc != null && lat != null && lon != null && prevLat != null && prevLon != null) {
            if (crossedGate(_next, prevLon, prevLat, lon, lat)) {
                advance(_distanceM, "crossed");
                return;
            }
        }

        // Deliberately outside the fix check above: the whole point of the
        // fallback is to keep the race moving when there is no fix to test.
        if (remainingM() < -OVERDISTANCE_M) {
            advance(_segmentStartM + _lengths[_next], "timed out");
        }
    }

    //! Draw two strings side by side in different fonts, the pair centred
    //! together on x. drawText() takes a single font, so mixing sizes on one
    //! line means measuring both halves and placing each one by hand.
    private function drawPair(
        dc as Dc, x as Number, y as Number, gap as Number,
        left as String, leftFont as FontType,
        right as String, rightFont as FontType
    ) as Void {
        var leftW = dc.getTextWidthInPixels(left, leftFont);
        var rightW = dc.getTextWidthInPixels(right, rightFont);
        var start = x - (leftW + gap + rightW) / 2;
        var justify = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.drawText(start, y, leftFont, left, justify);
        dc.drawText(start + leftW + gap, y, rightFont, right, justify);
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

        if (_next >= _names.size()) {
            drawPair(
                dc, w / 2, h * 2 / 5, w / 40,
                (_distanceM / 1000.0).format("%.3f"), Graphics.FONT_NUMBER_MILD,
                "km", Graphics.FONT_XTINY
            );
            dc.drawText(
                w / 2, h * 3 / 4, Graphics.FONT_TINY, "finished",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }
        var remaining = remainingM() / 1000.0;
        drawPair(
            dc, w / 2, h * 2 / 5, w / 40,
            remaining.format("%.2f"), Graphics.FONT_NUMBER_MEDIUM,
            "km", Graphics.FONT_XTINY
        );

        drawPair(
            dc, w / 2, h * 3 / 4, w / 40,
            "to", Graphics.FONT_XTINY,
            _names[_next], Graphics.FONT_TINY
        );
    }
}
