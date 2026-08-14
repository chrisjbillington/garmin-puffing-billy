import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

//! A data field for a race on a fixed course, split into segments by named
//! waypoints. It shows how far is left to the next waypoint, how the segment is
//! being run against its target pace, and a bar giving the shape of the whole
//! course at a glance.
//!
//! The watch does not know the course: it is compiled in as a JSON resource
//! built by segments/make_segments.py. See README.md for that pipeline.
class PuffingBillyField extends WatchUi.DataField {

    //! 2**31 semicircles to 180 degrees. Gate coordinates are held as integer
    //! semicircles rather than as degrees because Monkey C loads JSON reals as
    //! 32-bit Float, whose steps span 1.3 m of longitude at this course.
    //! Integer semicircles are exact, at about a centimetre each, so the
    //! conversion is done on the one fix per second instead, in Double.
    private const DEG_TO_SEMI = 2147483648.0d / 180.0d;

    //! How far past a gate the runner may get before we give up waiting for it
    //! and move on. Gates are only ever tested in order, so without this one
    //! missed gate — a long GPS dropout, a wide detour around the course —
    //! would stall every later one for the rest of the race.
    private const OVERDISTANCE_M = 200.0;

    //! Pace spread at which a segment's colour saturates, as a fraction of the
    //! course's average pace. The segment targets run from 19% faster than
    //! average to 24% slower, so 0.25 uses most of the ramp without clipping
    //! either end to a flat block of colour.
    private const PACE_SPREAD = 0.25;

    //! How much a segment's colour is knocked back for course not yet run.
    //! Integer, used as a divisor on each colour channel.
    private const DIM = 2;

    //! Clearance kept from the edge of the screen. The watch shifts the whole
    //! display by a few pixels every so often to spare the panel from burn-in,
    //! and whatever it shifts towards goes under the bezel — so nothing may be
    //! drawn hard against the edge.
    //!
    //! The bar, the rule and the pace columns are all measured against this.
    //! The remaining rows are placed by eye and are narrower than it anyway.
    private const SAFE_INSET = 10;

    //! The progress bar's thickness, as a divisor of the screen width. Given
    //! 390px that is a 10px bar.
    private const BAR_PEN_DIV = 39;

    //! Where a Roboto glyph stands in its line box, as fractions of the height
    //! the font was asked for. Every font on this face is a Roboto — the system
    //! text fonts and the scalable one alike — and they share these: in a line
    //! of 2400 units, an ascent of 1900, a cap height of 1456 and an x-height of
    //! 1082. Ascent comes from Graphics.getFontAscent(); the other two the API
    //! does not report, so they are taken from the font itself.
    private const CAP_FRAC = 1456.0 / 2400.0;
    private const X_HEIGHT_FRAC = 1082.0 / 2400.0;

    //! The narrowest blank a digit carries beside its ink, on the same scale.
    //! Glyphs are spaced by their advance, which includes that blank, so a row
    //! measured with getTextWidthInPixels() reads wider than what is drawn.
    //! Taken as the smallest any digit has — 60 units, on a 4, against 115 on a
    //! 0 — because a pace can begin or end on any of them, and it is the
    //! tightest one that has to clear the margin.
    private const DIGIT_BEARING_FRAC = 60.0 / 2400.0;

    //! Where a pace label sits between the rule above it and the digits below,
    //! as the fraction D/C of the gap the rest of the top of the face is spaced
    //! by. At 1 the label is centred between the two; the lower it goes the
    //! more it belongs to the column under it rather than to the rule, which is
    //! the whole reason a label is nearer its value than its neighbours.
    private const LABEL_GAP_RATIO = 0.6;

    //! The font every figure on the face is set in, as a height in pixels and a
    //! scalable face. Scalable because the system fonts step straight from
    //! FONT_LARGE at 61px to FONT_NUMBER_MILD at 97px, and these want to sit
    //! between the two: at 70px the digits stand 43px, against 37px and 49px.
    //!
    //! Condensed because three four-character paces have to sit side by side
    //! across the middle of the face. In Roboto proper they leave 8px between
    //! columns even pushed out as far as the bezel clearance allows; condensed
    //! digits are a sixth narrower, which opens that to 27px.
    private const FIGURE_FONT_PX = 70;
    private const FIGURE_FONT_FACE = "RobotoCondensedRegular";

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

    //! Total course length in metres, and the distance-weighted average of the
    //! segment target paces in seconds per km. Both fixed for the race, so
    //! worked out once rather than on every draw.
    private var _courseM as Float;
    private var _meanPaceS as Float;

    //! Index of the gate being watched for, so equal to the segment count once
    //! the last one has been crossed. Gates are tested one at a time and in
    //! order — this is a race on a known course, and testing only the next one
    //! is both cheaper and immune to a doubling-back section triggering a later
    //! gate.
    private var _next as Number;

    //! The most recent fix, in semicircles. Held from the last compute() that
    //! had one, not simply the last compute(), so that a GPS dropout leaves a
    //! longer line to test against rather than a hole detection can fall
    //! through.
    private var _lastLat as Double?;
    private var _lastLon as Double?;

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

    //! The figure font, built once. Falls back to FONT_LARGE on a device that
    //! cannot supply the face at the size asked for.
    private var _figureFont as FontType;

    //! The vertical rhythm, in pixels down the face, solved in onLayout(). Each
    //! is the y a row is drawn at, not the top of its ink.
    private var _yHr as Number;
    private var _yRule as Number;
    private var _yPaceLabel as Number;
    private var _yPaceValue as Number;
    private var _yBar as Number;
    private var _yName as Number;
    private var _yRemaining as Number;

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
        _lastLat = null;
        _lastLon = null;
        _distanceM = 0.0;
        _segmentStartM = 0.0;
        _timerMs = 0;
        _segmentStartMs = 0;
        _speedMps = null;
        _heartRate = null;

        _figureFont = Graphics.FONT_LARGE;
        var scalable = Graphics.getVectorFont({
            :face => FIGURE_FONT_FACE, :size => FIGURE_FONT_PX
        });
        if (scalable != null) {
            _figureFont = scalable;
        }

        // Placed properly by onLayout(), which runs before the first onUpdate().
        _yHr = 0;
        _yRule = 0;
        _yPaceLabel = 0;
        _yPaceValue = 0;
        _yBar = 0;
        _yName = 0;
        _yRemaining = 0;

        var planS = 0.0;
        _courseM = 0.0;
        for (var i = 0; i < _lengths.size(); i += 1) {
            planS += _lengths[i] / 1000.0 * _paces[i];
            _courseM += _lengths[i];
        }
        _meanPaceS = planS / (_courseM / 1000.0);
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

    //! Whether the step from (lat0, lon0) to (lat1, lon1) passed through gate i.
    //!
    //! Two segments cross exactly when each separates the other's endpoints,
    //! which is four cross products and a comparison of their signs. Working in
    //! semicircles rather than metres is fine and saves projecting: scaling an
    //! axis by a positive constant scales all four cross products by that same
    //! constant, leaving every sign — and so the result — untouched.
    private function crossedGate(
        i as Number,
        lat0 as Double, lon0 as Double,
        lat1 as Double, lon1 as Double
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

    //! Move on to the next segment, taking the current odometer and timer
    //! readings as the boundary.
    private function advance() as Void {
        _segmentStartM = _distanceM;
        _segmentStartMs = _timerMs;
        _next += 1;
    }

    //! Called once per second with fresh activity data. Do the computation
    //! here, not in onUpdate() — onUpdate() is called on the device's own
    //! schedule, which on an AMOLED watch drops right off in low-power mode.
    function compute(info as Activity.Info) as Void {

        _speedMps = info.currentSpeed;
        _heartRate = info.currentHeartRate;

        if (_next >= _lengths.size() || info.timerState == Activity.TIMER_STATE_OFF) {
            // Race finished or not yet started
            return;
        }

        var d = info.elapsedDistance;
        _distanceM = (d == null) ? 0.0 : d;

        var t = info.timerTime;
        _timerMs = (t == null) ? 0 : t;

        var crossed_gate = false;
        var loc = info.currentLocation;
        if (loc != null) {
            var deg = loc.toDegrees();
            var lat = deg[0] * DEG_TO_SEMI;
            var lon = deg[1] * DEG_TO_SEMI;
            if (_lastLat != null && _lastLon != null) {
                crossed_gate = crossedGate(_next, _lastLat, _lastLon, lat, lon);
            }
            _lastLat = lat;
            _lastLon = lon;
        }
        if (crossed_gate || remainingM() < -OVERDISTANCE_M) {
            advance();
        }
    }

    //! Distance still to run in this segment, in metres. Goes negative once the
    //! runner is past where the gate should have been but has not yet crossed
    //! it — which is the normal case for a metre or two, since the odometer and
    //! the course never agree exactly.
    private function remainingM() as Float {
        return _lengths[_next] - (_distanceM - _segmentStartM);
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

    //! A pace in seconds per km as m:ss, or a placeholder when there is no
    //! sensible pace to show — before the runner has moved, or so slow that the
    //! number would be meaningless anyway. The minutes are always a single
    //! digit, so the string is always four characters wide.
    private function paceString(paceS as Float?) as String {
        if (paceS == null || paceS <= 0.0) {
            return "-:--";
        }
        var whole = (paceS + 0.5).toNumber();
        if (whole > 599) {
            return "-:--";
        }
        return (whole / 60).format("%d") + ":" + (whole % 60).format("%02d");
    }

    //! Half the width available at height y, inside the circle the face leaves
    //! once SAFE_INSET is taken off it. Zero past that circle's top and bottom.
    private function safeHalfWidthAt(w as Number, h as Number, y as Number) as Float {
        var r = w / 2 - SAFE_INSET;
        var dy = y - h / 2;
        if (dy < 0) { dy = -dy; }
        if (dy >= r) {
            return 0.0;
        }
        // toFloat() because sqrt() is typed as Float-or-Double, and a chord on a
        // 390px face has no need of the extra precision.
        return Math.sqrt(r * r - dy * dy).toFloat();
    }

    //! The height of a capital, and of a lowercase letter with neither stem nor
    //! descender, for a font asked for at a given height.
    private function capHeight(font as FontType) as Float {
        return Graphics.getFontHeight(font) * CAP_FRAC;
    }

    private function xHeight(font as FontType) as Float {
        return Graphics.getFontHeight(font) * X_HEIGHT_FRAC;
    }

    //! The y a row must be drawn at for its baseline to fall on `baseline`.
    //! TEXT_JUSTIFY_VCENTER centres the line box, which reaches further below
    //! the baseline than anything drawn here actually goes.
    private function yForBaseline(baseline as Float, font as FontType) as Number {
        return (baseline + Graphics.getFontHeight(font) / 2.0
                - Graphics.getFontAscent(font) + 0.5).toNumber();
    }

    //! Solve the vertical rhythm. The rows are not placed by eye: they are
    //! measured between the ink of one row and the ink of the next, rather than
    //! between line boxes, since the fonts carry descent that these strings —
    //! figures, and names without descenders — never use.
    //!
    //! Reading down the face, the gaps are
    //!
    //!     A  top of the display to the top of the heart rate's digits
    //!     B  heart rate baseline to the rule
    //!     C  rule to the top of the pace labels' x-height
    //!     D  pace label baseline to the top of the pace digits
    //!     E  pace baseline to the top of the bar
    //!     F  bottom of the bar to the cap height of the waypoint name
    //!     G  name baseline to the top of the remaining-distance digits
    //!     H  its baseline to the bottom of the display
    //!
    //! wanted as A = B = C = E and F = G = H, with D a set fraction of C and
    //! the pace digits centred on the face. That is seven equations for the
    //! seven rows, and it falls out top down: centring places the paces, then
    //! the whole top group solves at once — D and C are both multiples of the
    //! same gap, so the space above the digits divides into 3 + LABEL_GAP_RATIO
    //! of it — and that gap places the bar, which in turn places the two rows
    //! under it.
    //!
    //! The pace digits sit on the middle of the face because that is where the
    //! chord is longest, which is what lets their columns stand furthest apart.
    private function layOut(dc as Dc) as Void {
        var h = dc.getHeight();
        var pen = dc.getWidth() / BAR_PEN_DIV;

        var figCap = capHeight(_figureFont);
        var labelX = xHeight(Graphics.FONT_XTINY);
        var nameCap = capHeight(Graphics.FONT_TINY);

        var paceTop = h / 2.0 - figCap / 2.0;
        var paceBase = h / 2.0 + figCap / 2.0;
        _yPaceValue = yForBaseline(paceBase, _figureFont);

        // A + B + C + D spans the display top to the pace digits, less the two
        // rows of ink standing in it. Three of those gaps are the group's, the
        // fourth is D at its own fraction of one.
        var above = (paceTop - labelX - figCap) / (3.0 + LABEL_GAP_RATIO);
        var labelBase = paceTop - above * LABEL_GAP_RATIO;
        var labelTop = labelBase - labelX;
        _yPaceLabel = yForBaseline(labelBase, Graphics.FONT_XTINY);

        _yRule = (labelTop - above + 0.5).toNumber();
        _yHr = yForBaseline(labelTop - 2.0 * above, _figureFont);

        // E closes the top group, and the bar hangs its own half width below.
        _yBar = (paceBase + above + pen / 2.0 + 0.5).toNumber();

        // F + G + H likewise, over the two rows of ink below the bar.
        var barBottom = _yBar + pen / 2.0;
        var below = (h - barBottom - nameCap - figCap) / 3.0;
        _yName = yForBaseline(barBottom + below + nameCap, Graphics.FONT_TINY);
        _yRemaining = yForBaseline(
            barBottom + 2.0 * below + nameCap + figCap, _figureFont
        );
    }

    function onLayout(dc as Dc) as Void {
        layOut(dc);
    }

    //! How far either side of centre the outer pace columns sit, so that they
    //! stand as far apart as the face allows: the ink of an outer pace lands on
    //! the circle SAFE_INSET leaves.
    //!
    //! Taken at the digits' baseline. paceString() only ever emits digits, a
    //! colon and a dash, none of which descend, so the row's ink stops there
    //! rather than at the bottom of the line box. layOut() centres that ink on
    //! the face, which leaves the top of the digits as far above the middle as
    //! the baseline is below it — so either edge answers the same question.
    //!
    //! The labels are centred on the same columns and are the shorter row, so
    //! they follow the paces out without needing to be measured themselves.
    private function paceColumnOffset(dc as Dc, w as Number, h as Number) as Float {
        var baseline = _yPaceValue
            - Graphics.getFontHeight(_figureFont) / 2
            + Graphics.getFontAscent(_figureFont);
        // Every digit in this face is one width, so any four-character pace is
        // as wide as the row ever gets — measured in advances, off which the
        // ink stops short by a side bearing at each end.
        var half = dc.getTextWidthInPixels("0:00", _figureFont) / 2.0
            - Graphics.getFontHeight(_figureFont) * DIGIT_BEARING_FRAC;
        return safeHalfWidthAt(w, h, baseline) - half;
    }

    //! Green through amber to red as a segment's target pace goes from
    //! PACE_SPREAD faster than the course average to the same amount slower.
    private function segmentColour(paceS as Float) as Number {
        var t = (paceS / _meanPaceS - 1.0) / PACE_SPREAD;
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

    //! The same colour knocked back, for course not yet run.
    private function dim(colour as Number) as Number {
        return ((((colour >> 16) & 0xFF) / DIM) << 16) |
            ((((colour >> 8) & 0xFF) / DIM) << 8) |
            ((colour & 0xFF) / DIM);
    }

    //! A horizontal divider at y, spanning the middle three fifths of what is
    //! available there — so the rules draw in shorter as they approach the top
    //! and bottom of the face, which reads as dividers following the shape of
    //! the display rather than as a box drawn across it.
    private function drawRule(dc as Dc, w as Number, h as Number, y as Number) as Void {
        var half = safeHalfWidthAt(w, h, y) * 3.0 / 5.0;
        dc.drawLine(w / 2 - half, y, w / 2 + half, y);
    }

    //! Race progression as a horizontal bar centred on y, with a marker at the
    //! runner's position.
    //!
    //! Every segment is coloured by its target pace against the course
    //! average, green where the plan is fast, red where it is slow,
    //!
    //! Each segment is laid down dimmed and refilled at full strength over the
    //! part already covered, so the plan is legible end to end from the start
    //! and progress reads as it brightening from the left.
    private function drawBar(
        dc as Dc, w as Number, h as Number, y as Number, fg as Number
    ) as Void {
        var pen = w / BAR_PEN_DIV;
        var top = y - pen / 2;

        // Measured at whichever of the bar's long edges is further from the
        // middle of the face, so the whole rectangle clears the inset rather
        // than just its centre line.
        var far = (y < h / 2) ? top : y + pen / 2;
        var half = safeHalfWidthAt(w, h, far);
        if (half <= 0.0) {
            return;
        }

        var x0 = w / 2 - half;
        var span = 2.0 * half;
        var barLeft = (x0 + 0.5).toNumber();

        // Each segment's right edge is rounded once and reused as the next
        // one's left, so the seams neither gap nor overlap however the
        // kilometres divide up.
        var done = 0.0;
        var left = barLeft;
        var here = barLeft;
        for (var i = 0; i < _lengths.size(); i += 1) {
            var colour = segmentColour(_paces[i]);
            var len = _lengths[i].toFloat();
            var right = (x0 + span * (done + len) / _courseM + 0.5).toNumber();

            dc.setColor(dim(colour), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(left, top, right - left, pen);

            // How much of this segment is behind us. Clamped to its nominal
            // length so overrunning a gate can't bleed into the next one.
            var run = 0.0;
            if (i < _next) {
                run = len;
            } else if (i == _next) {
                run = _distanceM - _segmentStartM;
                if (run > len) { run = len; }
                if (run < 0.0) { run = 0.0; }
                here = (x0 + span * (done + run) / _courseM + 0.5).toNumber();
            }

            if (run > 0.0) {
                var upto = (x0 + span * (done + run) / _courseM + 0.5).toNumber();
                dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(left, top, upto - left, pen);
            }

            done += len;
            left = right;
        }
        var barRight = left;

        // One marker at the runner's position, drawn last so it stays legible
        // over any segment colour, and standing a little proud of the bar top
        // and bottom. Pulled in by its own half-width at either end so that it
        // reads as the first and last thing on the bar rather than overhanging
        // it — most of a race is spent nowhere near the ends, but the start is
        // exactly when the field is looked at hardest.
        var markPen = pen / 2 - 1;
        var proud = pen / 2 + markPen / 2;
        var lo = barLeft + markPen / 2;
        var hi = barRight - markPen / 2;
        if (here < lo) { here = lo; }
        if (here > hi) { here = hi; }

        dc.setPenWidth(markPen);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(here, y - proud, here, y + proud);
    }

    //! Draw a value and its unit side by side, the pair centred together on the
    //! face. drawText() takes one font and the device one colour, so mixing
    //! either on a line means measuring both halves and placing each by hand.
    private function drawValueUnit(
        dc as Dc, w as Number, y as Number,
        value as String, valueFont as FontType, valueColour as Number,
        unit as String, unitColour as Number
    ) as Void {
        var gap = w / 40;
        var valueW = dc.getTextWidthInPixels(value, valueFont);
        var unitW = dc.getTextWidthInPixels(unit, Graphics.FONT_XTINY);
        var start = w / 2 - (valueW + gap + unitW) / 2;
        var justify = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(valueColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(start, y, valueFont, value, justify);
        dc.setColor(unitColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(start + valueW + gap, y, Graphics.FONT_XTINY, unit, justify);
    }

    //! Draw the field. `dc` is the whole round face, but it is sized off
    //! getWidth()/getHeight() rather than off a hardcoded 390x390.
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
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Past the last gate there is nothing left to pace, and the activity is
        // about to be stopped, so the word is the whole screen. Centred the same
        // way as the paces: on the ink, not on the line box.
        if (_next >= _lengths.size()) {
            var capMid = h / 2.0 + capHeight(_figureFont) / 2.0;
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                w / 2, yForBaseline(capMid, _figureFont), _figureFont,
                "Finished", centre
            );
            return;
        }

        // Three digits and a short unit, high on the face where it is narrow:
        // still the row with the most room to spare at the shared size.
        var hr = _heartRate;
        drawValueUnit(
            dc, w, _yHr,
            (hr == null ? "---" : hr.format("%d")), _figureFont, fg,
            "BPM", labelColour
        );

        // Three paces straddling the middle of the face, each label centred over
        // its value, the columns as far apart as they will go.
        var labels = ["target", "segment", "pace"];
        var paces = [_paces[_next], segmentPaceS(), currentPaceS()];
        var col = paceColumnOffset(dc, w, h);

        for (var i = 0; i < 3; i += 1) {
            var x = (w / 2 + (i - 1) * col).toNumber();
            dc.setColor(labelColour, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x, _yPaceLabel, Graphics.FONT_XTINY, labels[i] as String, centre
            );
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x, _yPaceValue, _figureFont,
                paceString(paces[i] as Float?), centre
            );
        }

        dc.setColor(nameColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2, _yName, Graphics.FONT_TINY, _names[_next], centre
        );

        // The face is narrow this near the bottom, and this row is the widest of
        // the three: the value runs to five characters once remainingM() goes
        // negative on the approach to a gate, and "km" hangs off the end of it.
        // That, rather than the rows above, is what holds its size down.
        drawValueUnit(
            dc, w, _yRemaining,
            (remainingM() / 1000.0).format("%.2f"), _figureFont, fg,
            "km", labelColour
        );

        dc.setColor(labelColour, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        drawRule(dc, w, h, _yRule);

        // Last, because it leaves the pen width and colour where it likes.
        drawBar(dc, w, h, _yBar, fg);
    }
}
