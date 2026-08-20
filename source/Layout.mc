import Toybox.Graphics;
import Toybox.Lang;

//! The y coordinate of every row on the face.
//!
//! Each y is a draw position, not the top of the row's ink: we position rows by
//! baseline and by the ink above and below it, as measured by Roboto.
class Layout {

    //! Gap between a projection label and the figures below it on the
    //! half-height field, as a fraction of the gap from the figures to the
    //! near end of the band.
    private const LABEL_GAP_RATIO = 0.6;

    //! Gap between a label's baseline and the top of the digits below it on
    //! the whole face, as a fraction of the label font's height. Places the
    //! pace labels above the pace digits and the standing labels above the
    //! standings.
    private const LABEL_GAP = 0.4;

    //! The progress bar's thickness, as a divisor of the display width. Given
    //! 390px that is a 10px bar.
    private const BAR_PEN_DIV = 39;

    //! The gap between the two runs of text that share a line, as a divisor of
    //! the display width.
    private const PAIR_GAP_DIV = 40;

    //! The font we use for all figures, as a height in pixels and a scalable
    //! face. The system fonts step from FONT_LARGE, with 37px digits, to
    //! FONT_NUMBER_MILD, with 49px digits. At 70px this face gives 43px digits.
    //!
    //! Condensed digits are a sixth narrower than Roboto proper, giving 27px
    //! between the three pace columns.
    private const FIGURE_FONT_PX = 70;
    private const FIGURE_FONT_FACE = "RobotoCondensedRegular";

    //! The face for the BPM label, which is drawn as small caps: capitals at
    //! the x-height of the other labels.
    private const SMALL_CAPS_FACE = "RobotoRegular";

    //! The same face, sized for a half-screen field. A finish time and its
    //! standing share a line, so the font size sets both the width of that line
    //! and its height. At 60px the line clears the inset with a standing of two
    //! digits of minutes.
    private const FIGURE_FONT_HALF_PX = 60;

    private var _face as Face;

    //! Whether the field has half the screen.
    var half as Boolean;

    //! The figure font, which is either the full-screen or half-screen size.
    //! FONT_LARGE if the device cannot supply the scalable face.
    var figureFont as FontType;

    //! The progress bar's thickness, and the gap between two runs of text that
    //! share a line, both in pixels.
    var barPen as Number;
    var pairGap as Number;

    //! The gap between a run of figures and the label at its side, in pixels.
    var labelPad as Number;

    //! Distance from the centre of the face to the centre of an outer pace
    //! column.
    var paceColumn as Float;

    //! The rows of the whole face. Each standing and its label are centred
    //! on one of the two standing columns, the label the label gap above the
    //! standing.
    var yHr as Number;
    var yStandingLabel as Number;
    var yStanding as Number;
    var yPaceLabel as Number;
    var yPaceValue as Number;
    var yBar as Number;
    var yName as Number;
    var yRemaining as Number;

    //! Draw positions of the BPM and km labels, beside the heart rate and
    //! the remaining distance, and BPM's small-caps font. FONT_XTINY if the
    //! device cannot supply the scalable face.
    var yBpm as Number;
    var yKm as Number;
    var bpmFont as FontType;

    //! Centres of the standings' columns: the midpoints of the two halves of
    //! the chord at the standings' mid-ink height. Each standing and its
    //! label are centred on one of these.
    var xPlan as Number;
    var xPerf as Number;

    //! The rows of the half-height field: the line naming its projection, the
    //! line of figures under it, and the train drawn in the rest of the band
    //! when the field has the top half of the display.
    var yProjLabel as Number;
    var yProjValue as Number;
    var yTrain as Number;

    function initialize(face as Face) {
        _face = face;

        half = false;
        figureFont = Graphics.FONT_LARGE;
        barPen = 1;
        pairGap = 1;
        labelPad = 3;
        paceColumn = 0.0;
        yHr = 0;
        yStandingLabel = 0;
        yStanding = 0;
        yPaceLabel = 0;
        yPaceValue = 0;
        yBar = 0;
        yName = 0;
        yRemaining = 0;
        yBpm = 0;
        yKm = 0;
        bpmFont = Graphics.FONT_XTINY;
        xPlan = 0;
        xPerf = 0;
        yProjLabel = 0;
        yProjValue = 0;
        yTrain = 0;
    }

    //! Solve the layout for the field's box. The half-height layout is sized
    //! from the projection labels `labels` and the image `train`.
    function solve(
        dc as Dc, labels as Array<String>, train as Graphics.BitmapReference
    ) as Void {
        barPen = dc.getWidth() / BAR_PEN_DIV;
        pairGap = dc.getWidth() / PAIR_GAP_DIV;
        half = dc.getHeight() < 0.75 * _face.h;

        figureFont = Graphics.FONT_LARGE;
        var scalable = Graphics.getVectorFont({
            :face => FIGURE_FONT_FACE,
            :size => half ? FIGURE_FONT_HALF_PX : FIGURE_FONT_PX
        });
        if (scalable != null) {
            figureFont = scalable;
        }

        if (half) {
            solveHalf(dc, labels, train);
        } else {
            solveFull(dc);
        }
    }

    //! Total ink height of a run of rows: the sum of their ink extents above
    //! and below their baselines.
    private function inkHeight(
        up as Array<Float>, down as Array<Float>
    ) as Float {
        var ink = 0.0;
        for (var i = 0; i < up.size(); i += 1) {
            ink += up[i] + down[i];
        }
        return ink;
    }

    //! One share of the space left in a span once the ink is subtracted.
    //! `weights` gives the shares before each row, plus one closing the span.
    private function unitGap(
        span as Float, up as Array<Float>, down as Array<Float>,
        weights as Array<Float>
    ) as Float {
        var shares = 0.0;
        for (var i = 0; i < weights.size(); i += 1) {
            shares += weights[i];
        }
        var gap = (span - inkHeight(up, down)) / shares;
        return gap > 0.0 ? gap : 0.0;
    }

    //! The baselines of a run of rows stacked down from `top`, each preceded by
    //! weights[i] * gap.
    private function stack(
        top as Float, gap as Float, up as Array<Float>, down as Array<Float>,
        weights as Array<Float>
    ) as Array<Float> {
        var baselines = [] as Array<Float>;
        var y = top;
        for (var i = 0; i < up.size(); i += 1) {
            y += weights[i] * gap + up[i];
            baselines.add(y);
            y += down[i];
        }
        return baselines;
    }

    //! Solve the vertical rhythm of the whole face: six rows separated by a
    //! uniform gap.
    //!
    //!     A  heart rate, digit ink top to baseline, with BPM at its right
    //!     B  standings and their labels, label x-height top to digit
    //!        baseline; label ascenders extend above the row
    //!     C  paces and their labels, the same extents
    //!     D  the bar, excluding the position marker
    //!     E  waypoint name, cap top to baseline
    //!     F  remaining-distance figures, ink top to baseline, with km at
    //!        their right
    //!
    //! The top of A, for a three-digit heart rate, is on the inset circle,
    //! and so is the bottom of F for its widest figures; A is lowered, and F
    //! raised, where BPM or km would cross the circle. The five gaps between
    //! the rows are equal. BPM shares the heart rate's baseline, and km the
    //! distance figures' ink top.
    private function solveFull(dc as Dc) as Void {
        var h = dc.getHeight();

        var figCap = Roboto.capHeight(figureFont);
        var labelX = Roboto.xHeight(Graphics.FONT_XTINY);
        var labelUp = Roboto.inkUp(Graphics.FONT_XTINY);
        var nameCap = Roboto.capHeight(Graphics.FONT_TINY);
        var labelGap =
            LABEL_GAP * Graphics.getFontHeight(Graphics.FONT_XTINY);
        var bearing = Roboto.digitBearing(figureFont);

        bpmFont = Graphics.FONT_XTINY;
        var smallCaps = Graphics.getVectorFont({
            :face => SMALL_CAPS_FACE,
            :size => (Graphics.getFontHeight(Graphics.FONT_XTINY)
                * Roboto.X_HEIGHT / Roboto.CAP).toNumber()
        });
        if (smallCaps != null) { bpmFont = smallCaps; }
        var bpmCap = Roboto.capHeight(bpmFont);

        // Row A.
        var hrW = dc.getTextWidthInPixels("888", figureFont).toFloat();
        var hrTop = h / 2.0 - _face.reachFor(hrW / 2.0 - bearing);
        var bpmRight = hrW / 2.0 + labelPad
            + dc.getTextWidthInPixels("BPM", bpmFont);
        var bpmMin = h / 2.0 - _face.reachFor(bpmRight);
        if (hrTop + figCap - bpmCap < bpmMin) {
            hrTop = bpmMin + bpmCap - figCap;
        }
        var hrBase = hrTop + figCap;
        yHr = Roboto.yForBaseline(hrBase, figureFont);
        yBpm = Roboto.yForBaseline(hrBase, bpmFont);

        // Row F. The figures' widest form is five characters with a leading
        // minus. km's ink has no descender, so its ink bottom is its
        // baseline.
        var remW = dc.getTextWidthInPixels("-8.88", figureFont).toFloat();
        var remBase = h / 2.0 + _face.reachFor(remW / 2.0 - bearing);
        var kmRight = remW / 2.0 + labelPad
            + dc.getTextWidthInPixels("km", Graphics.FONT_XTINY);
        var kmMax = h / 2.0 + _face.reachFor(kmRight);
        if (remBase - figCap + labelUp > kmMax) {
            remBase = kmMax - labelUp + figCap;
        }
        yRemaining = Roboto.yForBaseline(remBase, figureFont);
        yKm = Roboto.yForBaseline(
            remBase - figCap + labelUp, Graphics.FONT_XTINY
        );

        // Rows B to E, spaced by the uniform gap.
        var labelled = labelX + labelGap + figCap;
        var gap = (remBase - hrTop - 2.0 * figCap - 2.0 * labelled
            - barPen - nameCap) / 5.0;
        if (gap < 0.0) { gap = 0.0; }

        var standingBase = hrBase + gap + labelled;
        var paceBase = standingBase + gap + labelled;
        var barTop = paceBase + gap;
        var nameBase = barTop + barPen + gap + nameCap;

        yStanding = Roboto.yForBaseline(standingBase, figureFont);
        yStandingLabel = Roboto.yForBaseline(
            standingBase - figCap - labelGap, Graphics.FONT_XTINY
        );
        yPaceValue = Roboto.yForBaseline(paceBase, figureFont);
        yPaceLabel = Roboto.yForBaseline(
            paceBase - figCap - labelGap, Graphics.FONT_XTINY
        );
        yBar = (barTop + barPen / 2.0 + 0.5).toNumber();
        yName = Roboto.yForBaseline(nameBase, Graphics.FONT_TINY);

        var chordHalf = _face.halfWidthAt(
            (standingBase - figCap / 2.0 + 0.5).toNumber()
        );
        var mid = dc.getWidth() / 2.0;
        xPlan = (mid - chordHalf / 2.0 + 0.5).toNumber();
        xPerf = (mid + chordHalf / 2.0 + 0.5).toNumber();

        paceColumn = paceColumnOffset(dc, paceBase);
    }

    //! Solve the vertical rhythm of the half-height field: a projection label
    //! above its finish time, with the standing beside that time. The
    //! label-to-figures gap is LABEL_GAP_RATIO times the gap from the figures
    //! to the near end of the band.
    //!
    //! The block starts at the wider end of the band and extends as far as its
    //! widest row requires, so the top-half and bottom-half fields are mirror
    //! images. Both projection labels contribute to that width.
    private function solveHalf(
        dc as Dc, labels as Array<String>, train as Graphics.BitmapReference
    ) as Void {
        var h = dc.getHeight();
        var labelUp = Roboto.inkUp(Graphics.FONT_XTINY);
        var labelDown = Roboto.inkDown(Graphics.FONT_XTINY);
        var figCap = Roboto.capHeight(figureFont);

        // The figure line is wider than the labels. Its longest form is an
        // h:mm:ss finish and a standing with two digits of minutes. The label
        // widths are included too.
        var widest = dc.getTextWidthInPixels("0:00:00", figureFont)
            + pairGap
            + dc.getTextWidthInPixels("+00:00", figureFont);
        for (var i = 0; i < labels.size(); i += 1) {
            var named = dc.getTextWidthInPixels(labels[i], Graphics.FONT_XTINY);
            if (named > widest) {
                widest = named;
            }
        }

        var span = _face.reachFor(widest / 2.0) - _face.nearEdge();
        if (span > h) { span = h.toFloat(); }

        // Two rows of ink: a label at the ratio above its figures, and a full
        // gap at the near end of the band.
        var lower = _face.belowCentre();
        var r = LABEL_GAP_RATIO;
        var up = [labelUp, figCap] as Array<Float>;
        var down = [labelDown, 0.0] as Array<Float>;
        var gaps = lower
            ? ([1.0, r, 0.0] as Array<Float>)
            : ([0.0, r, 1.0] as Array<Float>);

        // If the span is smaller than the ink height, use the ink height. The
        // excess extends into the zero-width end of the band.
        var ink = inkHeight(up, down);
        if (span < ink) { span = ink; }

        var gap = unitGap(span, up, down, gaps);
        var rows = stack(lower ? 0.0 : h - span, gap, up, down, gaps);
        yProjLabel = Roboto.yForBaseline(rows[0], Graphics.FONT_XTINY);
        yProjValue = Roboto.yForBaseline(rows[1], figureFont);

        // The train is centred in the free space at the top of the band, and
        // moved down far enough to clear the safe inset. We measure the inset
        // at the bitmap's top corners, so the whole rectangle clears it.
        var imageHalfW = train.getWidth() / 2.0;
        var imageHalfH = train.getHeight() / 2.0;
        var imageReach = _face.reachFor(imageHalfW) - imageHalfH;
        var imageCentre = _face.h / 2.0 - imageReach - _face.offY;
        var freeCentre = (h - span) / 2.0;
        if (freeCentre > imageCentre) { imageCentre = freeCentre; }
        yTrain = (imageCentre - imageHalfH + 0.5).toNumber();
    }

    //! Distance from the centre of the face to the centre of an outer pace
    //! column. The outer edge of that column's ink lands on the inset circle.
    //!
    //! Measured at the digits' baseline. Fmt.pace() emits only digits, a colon
    //! and a dash, none of which descend, so the row's ink ends at the
    //! baseline. The row is below the middle of the display, so the baseline
    //! is where the circle is narrowest for it.
    //!
    //! The pace row sets the column offset, since it is wider than the label
    //! row centred on the same columns.
    private function paceColumnOffset(dc as Dc, baseline as Float) as Float {
        // Every digit in this face has the same advance, so any four-character
        // pace has the maximum row width. The advance includes a side bearing
        // at each end, outside the ink.
        var half = dc.getTextWidthInPixels("0:00", figureFont) / 2.0
            - Roboto.digitBearing(figureFont);
        return _face.halfWidthAt((baseline + 0.5).toNumber()) - half;
    }
}
