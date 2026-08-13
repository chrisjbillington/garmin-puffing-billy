import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
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

    //! Pace spread at which the ring's colour saturates, as a fraction of the
    //! course's average pace. The segment targets run from 19% faster than
    //! average to 24% slower, so 0.25 uses most of the ramp without clipping
    //! either end to a flat block of colour.
    private const PACE_SPREAD = 0.25;

    //! How much the ring is knocked back for course not yet run. Integer, used
    //! as a divisor on each colour channel.
    private const DIM = 3;

    //! The ring, as divisors of the screen width: its thickness, and how far
    //! its inner edge sits in from the edge of the screen. Given 390px that is
    //! a 10px band from radius 176 to 186.
    //!
    //! Placed by its inner edge rather than its outer one, so thinning the ring
    //! pulls it away from the bezel without disturbing the clearance to the
    //! text. The margin matters: the panel sits a couple of pixels off from the
    //! nominal 390x390, so anything drawn hard against the edge clips on one
    //! side and gaps on the other.
    private const RING_PEN_DIV = 39;
    private const RING_INNER_DIV = 20;

    //! Labels and rules, in a slate blue a few stops down from the foreground:
    //! enough contrast to read when looked at, little enough that the eye goes
    //! to the numbers rather than to what they are called. The upcoming
    //! waypoint is a value rather than a label, so it takes a blue of the same
    //! weight but with the grey taken out of it — told apart by its hue rather
    //! than by being brighter.
    //!
    //! One pair per background, because a single colour cannot sit the same
    //! distance from both black and white. Each is picked to land near 9:1
    //! against its own background, against the 21:1 the white-on-black numbers
    //! get, so the hierarchy holds whichever way round the field is drawn.
    private const LABEL_ON_DARK = 0x96AFC8;    // 9.3:1 on black
    private const LABEL_ON_LIGHT = 0x334C66;   // 8.9:1 on white
    private const NAME_ON_DARK = 0x74BEF5;     // 10.4:1 on black
    private const NAME_ON_LIGHT = 0x14508A;    // 8.3:1 on white

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

    //! Timer time, in milliseconds, and the reading of it at the start of the
    //! current segment. Timer time rather than elapsed time, so that a pause at
    //! a drink station doesn't count against the segment's pace.
    private var _timerMs as Number;
    private var _segmentStartMs as Number;

    //! Current speed in metres per second, straight from Activity.Info. Null
    //! when the watch has nothing to report yet.
    private var _speedMps as Float?;

    //! Heart rate in bpm. Null with no strap and no wrist reading yet.
    private var _heartRate as Number?;

    //! Total time the whole course takes at target pace, in seconds, and the
    //! total course length in metres. Both fixed for the race, so summed once
    //! rather than on every draw.
    private var _planS as Float;
    private var _courseM as Float;

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
        _timerMs = 0;
        _segmentStartMs = 0;
        _speedMps = null;
        _heartRate = null;

        _planS = 0.0;
        _courseM = 0.0;
        for (var i = 0; i < _lengths.size(); i += 1) {
            _planS += _lengths[i] / 1000.0 * _paces[i];
            _courseM += _lengths[i];
        }
    }

    //! A pace in seconds per km as m:ss, or a placeholder when there is no
    //! sensible pace to show — before the runner has moved, or so slow that the
    //! number would be meaningless anyway.
    private function paceString(paceS as Float?) as String {
        if (paceS == null || paceS <= 0.0 || paceS > 3599.0) {
            return "--:--";
        }
        var whole = (paceS + 0.5).toNumber();
        return (whole / 60).format("%d") + ":" + (whole % 60).format("%02d");
    }

    //! Average pace over the part of the current segment run so far, in seconds
    //! per km. Null until far enough into the segment to divide by.
    private function segmentPaceS() as Float? {
        var km = (_distanceM - _segmentStartM) / 1000.0;
        if (km <= 0.0) {
            return null;
        }
        return ((_timerMs - _segmentStartMs) / 1000.0) / km;
    }

    //! Instantaneous pace, in seconds per km.
    private function currentPaceS() as Float? {
        var speed = _speedMps;
        if (speed == null || speed <= 0.0) {
            return null;
        }
        return 1000.0 / speed;
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
    //! `startM` and `startMs` are the odometer and timer readings to treat as
    //! the boundary: the actual ones at the moment of crossing when a gate
    //! fired, or backdated ones when we gave up on it. Backdating the distance
    //! keeps the whole OVERDISTANCE_M of slop from being charged to the next
    //! segment, and the clock has to move with it — otherwise that segment
    //! starts with distance already on it but no time, and its pace reads
    //! absurdly fast for a kilometre afterwards.
    private function advance(startM as Float, startMs as Number) as Void {
        _segmentStartM = startM;
        _segmentStartMs = startMs;
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

        var t = info.timerTime;
        _timerMs = (t == null) ? 0 : t;

        _speedMps = info.currentSpeed;
        _heartRate = info.currentHeartRate;

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
                advance(_distanceM, _timerMs);
                return;
            }
        }

        // Deliberately outside the fix check above: the whole point of the
        // fallback is to keep the race moving when there is no fix to test.
        if (remainingM() < -OVERDISTANCE_M) {
            // Backdate the clock by however long the target pace says the
            // overshoot should have taken, to match the backdated distance.
            var slopMs = (OVERDISTANCE_M * _paces[_next]).toNumber();
            advance(_segmentStartM + _lengths[_next], _timerMs - slopMs);
        }
    }

    //! Where a distance along the course sits on the ring, in the degrees
    //! drawArc wants: 0 at 3 o'clock, counting counter-clockwise. The race
    //! starts at 12 o'clock and runs clockwise, like a clock face.
    private function angleAt(d as Float) as Float {
        var a = 90.0 - 360.0 * d / _courseM;
        while (a < 0.0) { a += 360.0; }
        while (a >= 360.0) { a -= 360.0; }
        return a;
    }

    //! Green through amber to red as a segment's pace goes from PACE_SPREAD
    //! faster than its target to the same amount slower.
    private function paceColour(actual as Float, target as Float) as Number {
        var t = (actual / target - 1.0) / PACE_SPREAD;
        if (t < -1.0) { t = -1.0; }
        if (t > 1.0) { t = 1.0; }

        // Full green at -1, full red at +1, both channels up at 0 for amber.
        var red = 255;
        var green = 255;
        if (t < 0.0) {
            red = ((1.0 + t) * 255).toNumber();
        } else {
            green = ((1.0 - t) * 255).toNumber();
        }
        return (red << 16) | (green << 8);
    }

    //! One arc of the ring, between two distances along the course.
    //!
    //! Skips anything that rounds away to nothing, because drawArc truncates
    //! its angles towards zero and draws a *complete circle* when the two land
    //! on the same degree — so a sliver of a segment would otherwise paint the
    //! whole ring its colour.
    private function arcBetween(
        dc as Dc, cx as Number, cy as Number, r as Number, d0 as Float, d1 as Float
    ) as Void {
        var a0 = angleAt(d0);
        var a1 = angleAt(d1);
        if (a0.toNumber() == a1.toNumber()) {
            return;
        }
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, a0, a1);
    }

    //! The same colour knocked back, for course not yet run.
    private function dim(colour as Number) as Number {
        return ((((colour >> 16) & 0xFF) / DIM) << 16) |
            ((((colour >> 8) & 0xFF) / DIM) << 8) |
            ((colour & 0xFF) / DIM);
    }

    //! Radius of the inner edge of the ring — the circle everything else has to
    //! stay inside.
    private function ringInnerR(w as Number, h as Number) as Number {
        return (w < h ? w : h) / 2 - w / RING_INNER_DIV;
    }

    //! A horizontal divider at y, spanning the middle three fifths of the chord
    //! the ring encloses at that height.
    //!
    //! Measured off the ring rather than off the screen so the rules always stop
    //! short of it instead of running under it, and so they draw in shorter as
    //! they approach the top and bottom of the face — which reads as dividers
    //! following the shape of the display rather than as a box drawn across it.
    private function rule(dc as Dc, w as Number, h as Number, y as Number) as Void {
        var r = ringInnerR(w, h);
        var dy = y - h / 2;
        if (dy < 0) { dy = -dy; }
        if (dy >= r) {
            return;
        }
        // Three fifths of the full chord, so three tenths of it either side.
        var half = Math.sqrt(r * r - dy * dy) * 3.0 / 5.0;
        dc.drawLine(w / 2 - half, y, w / 2 + half, y);
    }

    //! Progress ring around the rim, with a marker at the runner's position.
    //!
    //! Every segment is coloured by its *target* pace against the course
    //! average, so the ring is a picture of the route's shape rather than of
    //! how the run is going — green where the plan is fast, red where it is
    //! slow, which on this course means green downhill and red up. Nothing here
    //! reacts to the pace actually being run.
    //!
    //! Each segment is laid down dimmed and redrawn at full strength over the
    //! part already covered, so the plan is legible the whole way round from
    //! the start and progress reads as it brightening.
    private function drawRing(dc as Dc, w as Number, h as Number, fg as Number) as Void {
        var pen = w / RING_PEN_DIV;
        var cx = w / 2;
        var cy = h / 2;
        var r = ringInnerR(w, h) + pen / 2;
        var mean = _planS / (_courseM / 1000.0);

        dc.setPenWidth(pen);

        var done = 0.0;
        var here = 0.0;
        for (var i = 0; i < _lengths.size(); i += 1) {
            var colour = paceColour(_paces[i], mean);
            var span = _lengths[i].toFloat();

            dc.setColor(dim(colour), Graphics.COLOR_TRANSPARENT);
            arcBetween(dc, cx, cy, r, done, done + span);

            // How much of this segment is behind us. Clamped to its nominal
            // length so overrunning a gate can't bleed into the next arc.
            var run = 0.0;
            if (i < _next) {
                run = span;
            } else if (i == _next) {
                run = _distanceM - _segmentStartM;
                if (run > span) { run = span; }
                if (run < 0.0) { run = 0.0; }
                here = done + run;
            }

            if (run > 0.0) {
                dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
                arcBetween(dc, cx, cy, r, done, done + run);
            }
            done += span;
        }

        // One marker at the runner's position, drawn last so it stays legible
        // over any arc colour. There used to be a tick at every gate; the
        // segments are already delimited by the colours changing, and one mark
        // is found at a glance where one of ten has to be picked out.
        //
        // Wider than those ticks were and standing a little proud of the band on
        // both sides, since it is now the only thing on the ring that moves.
        var markPen = pen / 2 - 1;
        var inner = r - pen / 2 - markPen / 2;
        var outer = r + pen / 2 + markPen / 2;
        var rad = Math.toRadians(angleAt(here));
        var dx = Math.cos(rad);
        var dy = Math.sin(rad);

        dc.setPenWidth(markPen);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(
            cx + inner * dx, cy - inner * dy,
            cx + outer * dx, cy - outer * dy
        );
    }

    //! Draw two strings side by side in different fonts and colours, the pair
    //! centred together on x. drawText() takes one font and the device one
    //! colour, so mixing either on a line means measuring both halves and
    //! placing each one by hand.
    //!
    //! Leaves the colour set to the right half's.
    private function drawPair(
        dc as Dc, x as Number, y as Number, gap as Number,
        left as String, leftFont as FontType, leftColour as Number,
        right as String, rightFont as FontType, rightColour as Number
    ) as Void {
        var leftW = dc.getTextWidthInPixels(left, leftFont);
        var rightW = dc.getTextWidthInPixels(right, rightFont);
        var start = x - (leftW + gap + rightW) / 2;
        var justify = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(leftColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(start, y, leftFont, left, justify);
        dc.setColor(rightColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(start + leftW + gap, y, rightFont, right, justify);
    }

    //! Draw the field. `dc` covers only this field's slice of the screen, so
    //! everything is sized off getWidth()/getHeight() rather than the 390x390
    //! display — the same code has to work in a 1-, 2- or 4-field layout.
    function onUpdate(dc as Dc) as Void {
        var bg = getBackgroundColor();
        var dark = (bg == Graphics.COLOR_BLACK);
        var fg = dark ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        var labelColour = dark ? LABEL_ON_DARK : LABEL_ON_LIGHT;
        var nameColour = dark ? NAME_ON_DARK : NAME_ON_LIGHT;

        dc.setColor(bg, bg);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        // No blanket setColor here: with two colours in play every draw below
        // sets its own, and a default would only be there to be overridden.
        if (_next >= _names.size()) {
            drawPair(
                dc, w / 2, h * 2 / 5, w / 40,
                (_distanceM / 1000.0).format("%.3f"), Graphics.FONT_NUMBER_MILD, fg,
                "km", Graphics.FONT_XTINY, labelColour
            );
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                w / 2, h * 3 / 4, Graphics.FONT_TINY, "finished",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }
        // FONT_LARGE rather than a number font: FONT_NUMBER_MILD is the
        // smallest of those, so a notch down leaves the number fonts entirely.
        var remaining = remainingM() / 1000.0;
        drawPair(
            dc, w / 2, h * 14 / 100, w / 40,
            remaining.format("%.2f"), Graphics.FONT_LARGE, fg,
            "km", Graphics.FONT_XTINY, labelColour
        );

        dc.setColor(nameColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2, h * 27 / 100, Graphics.FONT_TINY, _names[_next],
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        // Three paces straddling the middle of the face, each label centred over
        // its value, the columns three tenths of the width either side of
        // centre rather than out on the sixths — which pulls them in off the
        // bezel without the four-character paces coming near each other.
        //
        // Sized for a four-character pace, since this course is never run at
        // 10:00/km or worse. On a 390px face at this height the ring encloses
        // 340px, and 4:30 measures 100px in FONT_LARGE, 130px in the smallest
        // number font: three of the latter want 390px, so the number fonts do
        // not fit across at any spacing, and FONT_LARGE is as large as this row
        // goes. The three columns leave 17px between neighbours.
        var labels = ["target", "segment", "pace"];
        var paces = [_paces[_next], segmentPaceS(), currentPaceS()];
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        for (var i = 0; i < 3; i += 1) {
            var x = w / 2 + (i - 1) * w * 3 / 10;
            dc.setColor(labelColour, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x, h * 44 / 100, Graphics.FONT_XTINY, labels[i] as String, centre
            );
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x, h * 57 / 100, Graphics.FONT_LARGE,
                paceString(paces[i] as Float?), centre
            );
        }

        // A number font for the rate itself: it is the one value here read at a
        // glance mid-effort rather than studied, and the bottom of the face has
        // the room for it now.
        var hr = _heartRate;
        drawPair(
            dc, w / 2, h * 83 / 100, w / 40,
            (hr == null ? "---" : hr.format("%d")), Graphics.FONT_NUMBER_MILD, fg,
            "BPM", Graphics.FONT_XTINY, labelColour
        );

        // Rules under the heading and under the pace row. The offsets clear each
        // row's baseline rather than its line box: fonts here carry several
        // pixels of descent that none of these strings actually use.
        dc.setColor(labelColour, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        rule(dc, w, h, h * 35 / 100);
        rule(dc, w, h, h * 70 / 100);

        // Last, because it leaves the pen width and colour where it likes.
        drawRing(dc, w, h, fg);
    }
}
