import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

//! A data field for a race on a fixed course, split into segments by named
//! waypoints. It shows the distance to the next waypoint, the target, segment
//! and current paces, the standing of each finish projection, and a bar
//! giving the shape of the whole course.
class PuffingBillyField extends WatchUi.DataField {

    //! The distance to the next waypoint is in metres and displayed in km.
    private const M_PER_KM = 1000.0;

    //! Pace spread at which a segment's colour saturates, as a fraction of the
    //! course's average pace. The segment targets run from 19% faster than
    //! average to 24% slower.
    private const PACE_SPREAD = 0.25;

    //! Divisor dimming the colour of course not yet run. Must be an integer.
    private const DIM = 2;

    //! Duration of the target pace highlight on entering a new segment, in
    //! seconds.
    private const HIGHLIGHT_S = 10.0;

    //! Mix fraction from the segment's colour towards the foreground for the
    //! highlight. Gives the segment colours a contrast ratio of about 9:1 with
    //! the background, the same as the labels and standings.
    private const HIGHLIGHT_LIFT = 0.45;

    //! The margin around the target pace label inside its pill, as fractions of
    //! the label font's height. The pill's corner radius is a quarter of its
    //! own height.
    private const PILL_MARGIN_X = 0.3;
    private const PILL_MARGIN_Y = 0.05;

    //! The rules separating the sections of the face: their width, the
    //! length over which a free end fades to the background, the number of
    //! segments in a fade, and the x step between points of the curved rule,
    //! all in pixels except the segment count.
    private const RULE_PEN = 2;
    private const RULE_FADE = 30;
    private const RULE_FADE_SEGMENTS = 8;
    private const HR_RULE_STEP = 3.0;

    //! Labels, in a slate blue dimmer than the foreground. The upcoming
    //! waypoint is a value rather than a label, and is a blue of the same
    //! contrast ratio but more saturated.
    //!
    //! One pair per background, since a single colour cannot be the same
    //! distance from both black and white. Each has a contrast ratio near 9:1
    //! with its own background, where the white-on-black figures have 21:1.
    private const LABEL_ON_DARK = 0x96AFC8;    // 9.3:1 on black
    private const LABEL_ON_LIGHT = 0x334C66;   // 8.9:1 on white
    private const NAME_ON_DARK = 0x74BEF5;     // 10.4:1 on black
    private const NAME_ON_LIGHT = 0x14508A;    // 8.3:1 on white

    //! The rules separating the sections of the face, in a saturated blue.
    private const RULE_ON_DARK = 0x54A8FD;     // 8.4:1 on black
    private const RULE_ON_LIGHT = 0x0D4F9E;    // 8.0:1 on white

    //! Colours for the time a projection is ahead or behind the target
    //! finishing time, green when ahead and red when behind. Near 9:1 on their
    //! own background, the same contrast ratio as the labels.
    private const AHEAD_ON_DARK = 0x4CCB6A;    // 10.1:1 on black
    private const AHEAD_ON_LIGHT = 0x0A5A1E;   // 8.4:1 on white
    private const BEHIND_ON_DARK = 0xFF8A7A;   // 9.2:1 on black
    private const BEHIND_ON_LIGHT = 0x8C1A1A;  // 9.2:1 on white

    private var _course as Course;
    private var _race as Race;
    private var _face as Face;
    private var _layout as Layout;

    //! Labels for the three pace columns and for the two standings, the
    //! target-pace projection's first and the performance-ratio one's second.
    private var _paceLabels as Array<String>;
    private var _standingLabels as Array<String>;

    //! Screen region dimensions and obscurity flags from the last layout. -1
    //! before the first onUpdate().
    private var _laidOutW as Number;
    private var _laidOutH as Number;
    private var _laidOutObscurity as Number;

    function initialize() {
        DataField.initialize();

        _course = new Course();
        _race = new Race(_course);
        _face = new Face();
        _layout = new Layout(_face);

        _paceLabels = ["target", "segment", "pace"] as Array<String>;
        _standingLabels = ["curr", "proj"] as Array<String>;

        _laidOutW = -1;
        _laidOutH = -1;
        _laidOutObscurity = -1;
    }

    //! Called once per second with fresh activity data. Do the computation
    //! here, not in onUpdate() — onUpdate() is called on the device's own
    //! schedule, which on an AMOLED watch slows considerably in low-power mode.
    function compute(info as Activity.Info) as Void {
        _race.update(info);
    }

    //! The activity has ended. Reset the race state, so the next activity
    //! starts from zero distance and time.
    function onTimerReset() as Void {
        _race = new Race(_course);
    }

    //! Lay out the field for its assigned screen region and cache the result,
    //! recomputing only if the region's dimensions or obscurity flags change.
    //! Call this only during onUpdate(), since getObscurityFlags() must only be
    //! called from onUpdate().
    private function ensureLayout(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var obscurity = getObscurityFlags();
        if (w == _laidOutW && h == _laidOutH &&
            obscurity == _laidOutObscurity) {
            return;
        }
        _laidOutW = w;
        _laidOutH = h;
        _laidOutObscurity = obscurity;

        var top = (_face.h - h) / 2;
        if ((obscurity & DataField.OBSCURE_TOP) != 0) {
            top = 0;
        } else if ((obscurity & DataField.OBSCURE_BOTTOM) != 0) {
            top = _face.h - h;
        }

        _face.place(top);
        _layout.solve(dc);
    }

    //! Green through amber to red as a segment's target pace goes from
    //! PACE_SPREAD faster than the course average to the same amount slower.
    private function segmentColour(paceS as Float) as Number {
        var t = (paceS / _course.meanPaceS - 1.0) / PACE_SPREAD;
        if (t < -1.0) { t = -1.0; }
        if (t > 1.0) { t = 1.0; }

        // Full green at -1, full red at +1, red = green = 255 at 0 for amber.
        var red = 255;
        var green = 255;
        if (t < 0.0) {
            red = ((1.0 + t) * 255).toNumber();
        } else {
            green = ((1.0 - t) * 255).toNumber();
        }
        return (red << 16) | (green << 8);
    }

    //! The same colour dimmed, for course not yet run.
    private function dim(colour as Number) as Number {
        return ((((colour >> 16) & 0xFF) / DIM) << 16) |
            ((((colour >> 8) & 0xFF) / DIM) << 8) |
            ((colour & 0xFF) / DIM);
    }

    //! One channel of `from` mixed `t` of the way towards `to`.
    private function mixChannel(
        from as Number, to as Number, t as Float
    ) as Number {
        return (from + (to - from) * t).toNumber();
    }

    //! `from` mixed `t` of the way towards `to`, channel by channel.
    private function blend(from as Number, to as Number, t as Float) as Number {
        return (mixChannel((from >> 16) & 0xFF, (to >> 16) & 0xFF, t) << 16) |
            (mixChannel((from >> 8) & 0xFF, (to >> 8) & 0xFF, t) << 8) |
            mixChannel(from & 0xFF, to & 0xFF, t);
    }

    //! Whether the segment being run started less than HIGHLIGHT_S ago. False
    //! while previewing.
    private function highlighted() as Boolean {
        var age = _race.segmentAgeS();
        return age != null && age < HIGHLIGHT_S;
    }

    //! The pill drawn behind the pace label centred on x, sized to that label's
    //! ink and margin.
    private function drawPill(
        dc as Dc, w as Number, x as Number, label as String, colour as Number
    ) as Void {
        var font = Graphics.FONT_XTINY;
        var fontH = Graphics.getFontHeight(font);
        var up = Roboto.inkUp(font);
        var marginY = PILL_MARGIN_Y * fontH;

        var h = up + Roboto.inkDown(font) + 2.0 * marginY;
        var top = Roboto.baselineAt(_layout.yPaceLabel, font) - up - marginY;
        var radius = h / 4.0;

        // Limit the pill to the inset width at its highest full-width row,
        // which is its narrowest.
        var half = dc.getTextWidthInPixels(label, font) / 2.0
            + PILL_MARGIN_X * fontH;
        var offset = x - w / 2;
        if (offset < 0) { offset = -offset; }
        var limit = _face.halfWidthAt((top + radius + 0.5).toNumber()) - offset;
        if (half > limit) { half = limit; }

        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(
            (x - half + 0.5).toNumber(), (top + 0.5).toNumber(),
            (2.0 * half + 0.5).toNumber(), (h + 0.5).toNumber(),
            (radius + 0.5).toNumber()
        );
    }

    //! A rule from (x0, y0) to (x1, y1), fading to the background over the
    //! RULE_FADE of its length nearest (x1, y1).
    private function drawFadingRule(
        dc as Dc, x0 as Float, y0 as Float, x1 as Float, y1 as Float,
        colour as Number, bg as Number
    ) as Void {
        var dx = x1 - x0;
        var dy = y1 - y0;
        var len = Math.sqrt(dx * dx + dy * dy).toFloat();
        if (len == 0.0) {
            return;
        }
        var fade = RULE_FADE.toFloat();
        if (fade > len) { fade = len; }
        var f0 = 1.0 - fade / len;

        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        if (f0 > 0.0) {
            dc.drawLine(x0, y0, x0 + f0 * dx, y0 + f0 * dy);
        }
        for (var i = 0; i < RULE_FADE_SEGMENTS; i += 1) {
            var a = f0 + (1.0 - f0) * i / RULE_FADE_SEGMENTS;
            var b = f0 + (1.0 - f0) * (i + 1) / RULE_FADE_SEGMENTS;
            var t = (i + 0.5) / RULE_FADE_SEGMENTS;
            dc.setColor(blend(colour, bg, t), Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x0 + a * dx, y0 + a * dy, x0 + b * dx, y0 + b * dy);
        }
    }

    //! One arm of the rule curved around the heart rate, from its bottom at
    //! the centre of the face to the inset circle, fading to the background
    //! over the RULE_FADE of its length nearest the circle. `side` is -1 for
    //! the left arm and 1 for the right.
    private function drawHrRuleArm(
        dc as Dc, w as Number, side as Number, colour as Number, bg as Number
    ) as Void {
        var xs = [] as Array<Float>;
        var ys = [] as Array<Float>;
        var dx = 0.0;
        while (true) {
            var y = _layout.yHrRule - _layout.hrRuleK * dx * dx;
            if (y < 0.0 || dx >= _face.halfWidthAt((y + 0.5).toNumber())) {
                break;
            }
            xs.add(w / 2.0 + side * dx);
            ys.add(y);
            dx += HR_RULE_STEP;
        }
        var n = xs.size();
        if (n < 2) {
            return;
        }

        var fromEnd = new [n] as Array<Float>;
        fromEnd[n - 1] = 0.0;
        for (var i = n - 2; i >= 0; i -= 1) {
            var sx = xs[i + 1] - xs[i];
            var sy = ys[i + 1] - ys[i];
            fromEnd[i] = fromEnd[i + 1]
                + Math.sqrt(sx * sx + sy * sy).toFloat();
        }
        for (var i = 0; i < n - 1; i += 1) {
            var d = (fromEnd[i] + fromEnd[i + 1]) / 2.0;
            var t = d >= RULE_FADE ? 0.0 : 1.0 - d / RULE_FADE;
            dc.setColor(blend(colour, bg, t), Graphics.COLOR_TRANSPARENT);
            dc.drawLine(xs[i], ys[i], xs[i + 1], ys[i + 1]);
        }
    }

    //! The rules separating the sections of the face: a curve around the
    //! heart rate, a vertical rule between the standings, a horizontal rule
    //! between the standings and the paces, and a vertical rule between each
    //! pair of pace columns. Ends at the inset circle and the lower ends of
    //! the pace-column rules fade to the background.
    private function drawRules(
        dc as Dc, w as Number, colour as Number, bg as Number
    ) as Void {
        dc.setPenWidth(RULE_PEN);

        var mid = w / 2.0;
        var yRule = _layout.yRule.toFloat();

        // The horizontal rule, drawn from the centre to each side.
        var half = _face.halfWidthAt(_layout.yRule);
        drawFadingRule(dc, mid, yRule, mid - half, yRule, colour, bg);
        drawFadingRule(dc, mid, yRule, mid + half, yRule, colour, bg);

        // The vertical rule between the standings, from the curved rule's
        // bottom to the horizontal rule.
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(mid, _layout.yHrRule, mid, yRule);

        // The rules between the pace columns, hanging from the horizontal
        // rule at the midpoints of the gaps between the columns.
        var xPace = _layout.paceColumn / 2.0;
        var yEnd = _layout.yPaceRuleEnd.toFloat();
        drawFadingRule(dc, mid - xPace, yRule, mid - xPace, yEnd, colour, bg);
        drawFadingRule(dc, mid + xPace, yRule, mid + xPace, yEnd, colour, bg);

        drawHrRuleArm(dc, w, -1, colour, bg);
        drawHrRuleArm(dc, w, 1, colour, bg);

        dc.setPenWidth(1);
    }

    //! Colour for the time a projection is ahead of or behind the target
    //! finishing time.
    private function standingColour(offS as Float, dark as Boolean) as Number {
        return Fmt.ahead(offS)
            ? (dark ? AHEAD_ON_DARK : AHEAD_ON_LIGHT)
            : (dark ? BEHIND_ON_DARK : BEHIND_ON_LIGHT);
    }

    //! One standing, centred on x.
    private function drawStanding(
        dc as Dc, x as Number, offS as Float, dark as Boolean
    ) as Void {
        dc.setColor(standingColour(offS, dark), Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            x, _layout.yStanding, _layout.figureFont, Fmt.standing(offS),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    //! Race progression as a horizontal bar centred on y, with a marker at the
    //! runner's position.
    //!
    //! Every segment is coloured by the ratio of its target pace to the course
    //! average, green where the plan is fast and red where it is slow. We fill
    //! each segment in its dimmed colour, then overdraw the part already run in
    //! the full colour.
    private function drawBar(
        dc as Dc, w as Number, y as Number, fg as Number
    ) as Void {
        var pen = _layout.barPen;
        var top = y - pen / 2;

        // Measured at the bar's long edge further from the middle of the face,
        // so the whole rectangle clears the inset.
        var far = _face.aboveCentre(y) ? top : y + pen / 2;
        var half = _face.halfWidthAt(far);
        if (half <= 0.0) {
            return;
        }

        var x0 = w / 2 - half;
        var span = 2.0 * half;
        var barLeft = (x0 + 0.5).toNumber();
        var segment = _race.segment();

        // Each segment's right edge is rounded once and reused as the next
        // one's left, so the seams neither gap nor overlap at any segment
        // division.
        var done = 0.0;
        var left = barLeft;
        var here = barLeft;
        for (var i = 0; i < _course.size(); i += 1) {
            var colour = segmentColour(_course.paceS(i));
            var len = _course.lengthM(i).toFloat();
            var endFrac = (done + len) / _course.totalM;
            var right = (x0 + span * endFrac + 0.5).toNumber();

            dc.setColor(dim(colour), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(left, top, right - left, pen);

            // Distance completed in this segment, clamped to its nominal
            // length so overrunning a gate cannot fill past the segment's
            // right edge.
            var run = 0.0;
            if (i < segment) {
                run = len;
            } else if (i == segment) {
                run = _race.ranInSegmentM();
                if (run > len) { run = len; }
                if (run < 0.0) { run = 0.0; }
            }

            var runFrac = (done + run) / _course.totalM;
            var upto = (x0 + span * runFrac + 0.5).toNumber();
            if (i == segment) {
                here = upto;
            }
            if (run > 0.0) {
                dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(left, top, upto - left, pen);
            }

            done += len;
            left = right;
        }
        var barRight = left;

        // One marker at the runner's position, drawn after the segment bars so
        // it is legible over any segment colour. It extends past the bar top
        // and bottom, and its position is clamped by half the marker width at
        // each end so it does not overhang the bar.
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

    //! Draw the full-screen field: the heart rate, the three paces, the course
    //! bar, and the next waypoint with the distance still to run.
    private function drawFullScreenField(
        dc as Dc, w as Number, bg as Number, fg as Number,
        labelColour as Number, nameColour as Number, dark as Boolean
    ) as Void {
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var segment = _race.segment();

        // First, so any text that reaches a rule is drawn over it.
        drawRules(dc, w, dark ? RULE_ON_DARK : RULE_ON_LIGHT, bg);

        // The heart rate, with BPM centred below it, then the standings,
        // each centred with its label on its own column: "plan" for the
        // target-pace projection on the left, "perf" for the
        // performance-ratio one on the right.
        var hr = _race.heartRate;
        var hrText = hr == null ? "---" : hr.format("%d");
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, _layout.yHr, _layout.figureFont, hrText, centre);

        dc.setColor(labelColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, _layout.yBpm, _layout.bpmFont, "BPM", centre);
        dc.drawText(
            _layout.xPlan, _layout.yStandingLabel, Graphics.FONT_XTINY,
            _standingLabels[0], centre
        );
        dc.drawText(
            _layout.xPerf, _layout.yStandingLabel, Graphics.FONT_XTINY,
            _standingLabels[1], centre
        );

        drawStanding(
            dc, _layout.xPlan, _race.targetFinishS() - _course.planS, dark
        );
        drawStanding(
            dc, _layout.xPerf, _race.perfRatioFinishS() - _course.planS, dark
        );

        // Three pace columns centred on the middle of the face, each label
        // centred over its value, the outer two offset by _layout.paceColumn.
        var paces = [
            _course.paceS(segment), _race.segmentPaceS(), _race.currentPaceS()
        ] as Array<Float?>;

        // For the first HIGHLIGHT_S of a segment, draw the target pace in the
        // segment's bar colour mixed towards the foreground, and its label in
        // the background colour over a pill in that same colour.
        var lit = highlighted();
        var accent = fg;
        if (lit) {
            accent = blend(
                segmentColour(_course.paceS(segment)), fg, HIGHLIGHT_LIFT
            );
        }

        for (var i = 0; i < paces.size(); i += 1) {
            var x = (w / 2 + (i - 1) * _layout.paceColumn).toNumber();
            var target = lit && i == 0;
            if (target) {
                drawPill(dc, w, x, _paceLabels[i], accent);
            }
            dc.setColor(
                target ? bg : labelColour, Graphics.COLOR_TRANSPARENT
            );
            dc.drawText(
                x, _layout.yPaceLabel, Graphics.FONT_XTINY, _paceLabels[i], centre
            );
            dc.setColor(target ? accent : fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x, _layout.yPaceValue, _layout.figureFont,
                Fmt.pace(paces[i]), centre
            );
        }

        dc.setColor(nameColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2, _layout.yName, Graphics.FONT_TINY, _course.name(segment), centre
        );

        // The remaining distance, its digits centred with km at their right.
        // On the approach to a gate the distance can be negative, meaning
        // the runner has exceeded the nominal segment length without a
        // detected gate crossing; it is then red, and its sign hangs to the
        // left of the centred digits.
        var remainingM = _race.remainingM();
        var remText = (remainingM / M_PER_KM).format("%.2f");
        var remDigits = remText;
        if (remainingM < 0.0) {
            remDigits = remText.substring(1, remText.length()) as String;
        }
        var remHalf =
            dc.getTextWidthInPixels(remDigits, _layout.figureFont) / 2;
        var remainingColour = (remainingM < 0.0)
            ? (dark ? BEHIND_ON_DARK : BEHIND_ON_LIGHT)
            : fg;
        dc.setColor(remainingColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2 + remHalf, _layout.yRemaining, _layout.figureFont, remText,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.setColor(labelColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2 + remHalf + _layout.labelPad,
            _layout.yKm, Graphics.FONT_XTINY, "km", left
        );

        // Last, because drawBar() leaves the pen width and colour set.
        drawBar(dc, w, _layout.yBar, fg);
    }

    //! Draw the field into its assigned screen region.
    function onUpdate(dc as Dc) as Void {
        ensureLayout(dc);

        var bg = getBackgroundColor();
        var dark = (bg == Graphics.COLOR_BLACK);
        var fg = dark ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        var labelColour = dark ? LABEL_ON_DARK : LABEL_ON_LIGHT;
        var nameColour = dark ? NAME_ON_DARK : NAME_ON_LIGHT;

        dc.setColor(bg, bg);
        dc.clear();

        var w = dc.getWidth();

        // After the final gate, centre "Finished" on its cap height, like the
        // pace rows. Otherwise, when the field is given half a data screen, we
        // show a projected finish time, and given the whole screen the pace,
        // heart rate and current segment info.
        if (_race.finished()) {
            var font = _layout.figureFont;
            var capMid = dc.getHeight() / 2.0 + Roboto.capHeight(font) / 2.0;
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                w / 2, Roboto.yForBaseline(capMid, font), font,
                "Finished",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        } else {
            drawFullScreenField(dc, w, bg, fg, labelColour, nameColour, dark);
        }

        // // The inset circle, for checking on the watch whether the layout
        // // clips under the bezel. Temporary — delete once SAFE_INSET is
        // // settled.
        // dc.setPenWidth(1);
        // dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        // _face.drawInset(dc);
    }
}
