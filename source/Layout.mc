import Toybox.Graphics;
import Toybox.Lang;

//! The y coordinate of every row on the face.
//!
//! Each y is a draw position, not the top of the row's ink: we position rows by
//! baseline and by the ink above and below it, as measured by Roboto.
class Layout {

    //! Gap D, between a pace label and the digits below it, as a fraction of
    //! the gap A = B = C used higher up the face. At 1 the label is centred
    //! between the rule and the digits.
    private const LABEL_GAP_RATIO = 0.6;

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

    //! Distance from the centre of the face to the centre of an outer pace
    //! column.
    var paceColumn as Float;

    //! The rows of the whole face.
    var yHr as Number;
    var yRule as Number;
    var yPaceLabel as Number;
    var yPaceValue as Number;
    var yBar as Number;
    var yName as Number;
    var yRemaining as Number;

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
        paceColumn = 0.0;
        yHr = 0;
        yRule = 0;
        yPaceLabel = 0;
        yPaceValue = 0;
        yBar = 0;
        yName = 0;
        yRemaining = 0;
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

    //! Solve the vertical rhythm of the whole face.
    //!
    //! The gaps are
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
    //! The constraints are A = B = C = E and F = G = H, with D a set fraction
    //! of C and the pace digits centred on the face. That is seven equations
    //! for the seven rows, solved top down: centring places the paces, the
    //! group above them fills the span down to the pace digits, its gap sets
    //! the bar position, and the bar spans the group below.
    private function solveFull(dc as Dc) as Void {
        var h = dc.getHeight();

        var figCap = Roboto.capHeight(figureFont);
        var labelX = Roboto.xHeight(Graphics.FONT_XTINY);
        var nameCap = Roboto.capHeight(Graphics.FONT_TINY);

        var paceTop = h / 2.0 - figCap / 2.0;
        var paceBase = h / 2.0 + figCap / 2.0;
        yPaceValue = Roboto.yForBaseline(paceBase, figureFont);

        // The heart rate, the rule and the pace label, spanning the display top
        // to the pace digits: gaps A, B and C before them and D closing on the
        // digits. The rule has no ink.
        var topUp = [figCap, 0.0, labelX] as Array<Float>;
        var topDown = [0.0, 0.0, 0.0] as Array<Float>;
        var topGaps = [1.0, 1.0, 1.0, LABEL_GAP_RATIO] as Array<Float>;
        var above = unitGap(paceTop, topUp, topDown, topGaps);
        var upperRows = stack(0.0, above, topUp, topDown, topGaps);
        yHr = Roboto.yForBaseline(upperRows[0], figureFont);
        yRule = (upperRows[1] + 0.5).toNumber();
        yPaceLabel = Roboto.yForBaseline(upperRows[2], Graphics.FONT_XTINY);

        // E closes the top group; yBar is the bar's centre, half a pen below
        // its top edge.
        yBar = (paceBase + above + barPen / 2.0 + 0.5).toNumber();

        // The waypoint name and the distance to it, spanning the bar to the
        // bottom of the display: F and G before them and H closing.
        var barBottom = (yBar + barPen / 2).toFloat();
        var lowUp = [nameCap, figCap] as Array<Float>;
        var lowDown = [0.0, 0.0] as Array<Float>;
        var lowGaps = [1.0, 1.0, 1.0] as Array<Float>;
        var below = unitGap(h - barBottom, lowUp, lowDown, lowGaps);
        var lowerRows = stack(barBottom, below, lowUp, lowDown, lowGaps);
        yName = Roboto.yForBaseline(lowerRows[0], Graphics.FONT_TINY);
        yRemaining = Roboto.yForBaseline(lowerRows[1], figureFont);

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
    //! baseline. The ink is centred on the face, so the top of the digits is as
    //! far above the middle as the baseline is below it.
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
