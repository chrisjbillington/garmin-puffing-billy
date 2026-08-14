import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! A data field for a race on a fixed course, split into segments by named
//! waypoints. Given the whole face it shows how far is left to the next
//! waypoint, how the segment is being run against its target pace, and a bar
//! giving the shape of the whole course at a glance. Given half the face there
//! is no room for any of that, so it shows the two finish times the race is on
//! for instead, and how each stands against the plan.
class PuffingBillyField extends WatchUi.DataField {

    //! Pace spread at which a segment's colour saturates, as a fraction of the
    //! course's average pace. The segment targets run from 19% faster than
    //! average to 24% slower, so 0.25 uses most of the ramp without clipping
    //! either end to a flat block of colour.
    private const PACE_SPREAD = 0.25;

    //! How much a segment's colour is knocked back for course not yet run.
    //! Integer, used as a divisor on each colour channel.
    private const DIM = 2;

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

    //! Where a projection stands against the plan, green when the race is being
    //! run up on it and red when it is being run down. Picked to the same
    //! weight as the labels, near 9:1 on their own background, so the colour
    //! carries the sense of the number without shouting over the figures.
    private const AHEAD_ON_DARK = 0x4CCB6A;    // 10.1:1 on black
    private const AHEAD_ON_LIGHT = 0x0A5A1E;   // 8.4:1 on white
    private const BEHIND_ON_DARK = 0xFF8A7A;   // 9.2:1 on black
    private const BEHIND_ON_LIGHT = 0x8C1A1A;  // 9.2:1 on white

    private var _course as Course;
    private var _race as Race;
    private var _face as Face;
    private var _layout as Layout;

    //! What the three paces across the middle of the face are, and what each
    //! projection assumes, in the order they are drawn. Held rather than built
    //! per draw, since a data field draws about once a second for the length of
    //! a race.
    private var _paceLabels as Array<String>;
    private var _projLabels as Array<String>;

    //! The train shown in the otherwise empty, tapered end of a half-height
    //! field. It is imported without dithering in drawables.xml so its small,
    //! deliberately limited palette stays crisp.
    private var _train as Graphics.BitmapReference;

    function initialize() {
        DataField.initialize();

        _course = new Course();
        _race = new Race(_course);
        _face = new Face();
        _layout = new Layout(_face);

        _paceLabels = ["target", "segment", "pace"] as Array<String>;
        _projLabels =
            ["at target pace", "at current perf. ratio"] as Array<String>;

        _train = Application.loadResource(
            $.Rez.Drawables.PuffingBillyTrain
        ) as Graphics.BitmapReference;
    }

    //! Called once per second with fresh activity data. Do the computation
    //! here, not in onUpdate() — onUpdate() is called on the device's own
    //! schedule, which on an AMOLED watch drops right off in low-power mode.
    function compute(info as Activity.Info) as Void {
        _race.update(info);
    }

    //! Take the size and placing the watch has given the field, and lay it out
    //! to suit. Placing comes from the obscurity flags, which name the edges of
    //! the display the field is up against.
    function onLayout(dc as Dc) as Void {
        var h = dc.getHeight();
        var obscurity = getObscurityFlags();
        var top = (_face.h - h) / 2;
        if ((obscurity & DataField.OBSCURE_TOP) != 0) {
            top = 0;
        } else if ((obscurity & DataField.OBSCURE_BOTTOM) != 0) {
            top = _face.h - h;
        }

        _face.place(top, h);
        _layout.solve(dc, _projLabels, _train);
    }

    //! Green through amber to red as a segment's target pace goes from
    //! PACE_SPREAD faster than the course average to the same amount slower.
    private function segmentColour(paceS as Float) as Number {
        var t = (paceS / _course.meanPaceS - 1.0) / PACE_SPREAD;
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
    private function drawRule(dc as Dc, w as Number, y as Number) as Void {
        var half = _face.halfWidthAt(y) * 3.0 / 5.0;
        dc.drawLine(w / 2 - half, y, w / 2 + half, y);
    }

    //! Race progression as a horizontal bar centred on y, with a marker at the
    //! runner's position.
    //!
    //! Every segment is coloured by its target pace against the course average,
    //! green where the plan is fast and red where it is slow. Each is laid down
    //! dimmed and refilled at full strength over the part already covered, so
    //! the plan is legible end to end from the start and progress reads as the
    //! bar brightening from the left.
    private function drawBar(
        dc as Dc, w as Number, y as Number, fg as Number
    ) as Void {
        var pen = _layout.barPen;
        var top = y - pen / 2;

        // Measured at whichever of the bar's long edges is further from the
        // middle of the face, so the whole rectangle clears the inset rather
        // than just its centre line.
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
        // one's left, so the seams neither gap nor overlap however the
        // kilometres divide up.
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

            // How much of this segment is behind us. Clamped to its nominal
            // length so overrunning a gate can't bleed into the next one.
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

    //! Draw two runs of text side by side, the pair centred together on the
    //! face. drawText() takes one font and the device one colour, so mixing
    //! either on a line means measuring both halves and placing each by hand.
    private function drawPair(
        dc as Dc, w as Number, y as Number,
        left as String, leftFont as FontType, leftColour as Number,
        right as String, rightFont as FontType, rightColour as Number
    ) as Void {
        var gap = _layout.pairGap;
        var leftW = dc.getTextWidthInPixels(left, leftFont);
        var rightW = dc.getTextWidthInPixels(right, rightFont);
        var start = w / 2 - (leftW + gap + rightW) / 2;
        var justify = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(leftColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(start, y, leftFont, left, justify);
        dc.setColor(rightColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(start + leftW + gap, y, rightFont, right, justify);
    }

    //! Draw the half-height field: the two finish times the race is on for,
    //! each under the name of the pace it assumes and beside where it stands
    //! against the plan.
    private function drawProjections(
        dc as Dc, w as Number,
        fg as Number, labelColour as Number, dark as Boolean
    ) as Void {
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var finishes =
            [_race.targetFinishS(), _race.effortFinishS()] as Array<Float>;

        for (var i = 0; i < finishes.size(); i += 1) {
            var finish = finishes[i];

            // Both are measured against the same planned finish, so the two
            // standings read against each other: one is the time the race has
            // won or cost so far, the other where holding this effort carries
            // that to by the line.
            var off = finish - _course.planS;
            var colour = (off < 0.0)
                ? (dark ? AHEAD_ON_DARK : AHEAD_ON_LIGHT)
                : (dark ? BEHIND_ON_DARK : BEHIND_ON_LIGHT);

            var step = i * _layout.yProjPitch;
            dc.setColor(labelColour, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                w / 2, _layout.yProjLabel + step, Graphics.FONT_XTINY,
                _projLabels[i], centre
            );
            drawPair(
                dc, w, _layout.yProjValue + step,
                Fmt.duration(finish), _layout.figureFont, fg,
                Fmt.standing(off), _layout.figureFont, colour
            );
        }

        dc.drawBitmap(w / 2 - _train.getWidth() / 2, _layout.yTrain, _train);
    }

    //! Draw the race detail: the heart rate, the three paces, the course bar,
    //! and the waypoint being run towards with the distance still to it.
    private function drawDetail(
        dc as Dc, w as Number,
        fg as Number, labelColour as Number, nameColour as Number
    ) as Void {
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var segment = _race.segment();

        // Three digits and a short unit, high on the face where it is narrow:
        // still the row with the most room to spare at the shared size.
        var hr = _race.heartRate;
        drawPair(
            dc, w, _layout.yHr,
            (hr == null ? "---" : hr.format("%d")), _layout.figureFont, fg,
            "BPM", Graphics.FONT_XTINY, labelColour
        );

        // Three paces straddling the middle of the face, each label centred
        // over its value, the columns as far apart as they will go.
        var paces = [
            _course.paceS(segment), _race.segmentPaceS(), _race.currentPaceS()
        ] as Array<Float?>;

        for (var i = 0; i < paces.size(); i += 1) {
            var x = (w / 2 + (i - 1) * _layout.paceColumn).toNumber();
            dc.setColor(labelColour, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x, _layout.yPaceLabel, Graphics.FONT_XTINY, _paceLabels[i], centre
            );
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x, _layout.yPaceValue, _layout.figureFont,
                Fmt.pace(paces[i]), centre
            );
        }

        dc.setColor(nameColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2, _layout.yName, Graphics.FONT_TINY, _course.name(segment), centre
        );

        // The face is narrow this near the bottom, and this row is the widest
        // of the three: the value runs to five characters once the distance
        // goes negative on the approach to a gate, and "km" hangs off the end
        // of it. That, rather than the rows above, is what holds its size down.
        drawPair(
            dc, w, _layout.yRemaining,
            (_race.remainingM() / 1000.0).format("%.2f"), _layout.figureFont, fg,
            "km", Graphics.FONT_XTINY, labelColour
        );

        dc.setColor(labelColour, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        drawRule(dc, w, _layout.yRule);

        // Last, because it leaves the pen width and colour where it likes.
        drawBar(dc, w, _layout.yBar, fg);
    }

    //! Draw the field, into whichever part of the display it has been given.
    function onUpdate(dc as Dc) as Void {
        var bg = getBackgroundColor();
        var dark = (bg == Graphics.COLOR_BLACK);
        var fg = dark ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        var labelColour = dark ? LABEL_ON_DARK : LABEL_ON_LIGHT;
        var nameColour = dark ? NAME_ON_DARK : NAME_ON_LIGHT;

        dc.setColor(bg, bg);
        dc.clear();

        var w = dc.getWidth();

        // Past the last gate there is nothing left to pace, and the activity is
        // about to be stopped, so the word is the whole screen. Centred the
        // same way as the paces: on the ink, not on the line box.
        if (_race.finished()) {
            var font = _layout.figureFont;
            var capMid = dc.getHeight() / 2.0 + Roboto.capHeight(font) / 2.0;
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                w / 2, Roboto.yForBaseline(capMid, font), font,
                "Finished",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }

        // Half the display has no room for the race detail, so it carries where
        // the race is going instead.
        if (_layout.half) {
            drawProjections(dc, w, fg, labelColour, dark);
        } else {
            drawDetail(dc, w, fg, labelColour, nameColour);
        }
    }
}
