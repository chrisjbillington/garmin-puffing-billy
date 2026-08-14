import Toybox.Graphics;
import Toybox.Lang;

//! Where every row on the face is drawn. Solved once, when the watch tells the
//! field how much of the display it has been given, and read on every draw.
//!
//! Each y is where a row is drawn, not the top of its ink: rows are placed by
//! their baselines and the ink standing either side of them, which is what
//! Roboto measures.
class Layout {

    //! Where a pace label sits between the rule above it and the digits below,
    //! as the fraction D/C of the gap the rest of the top of the face is spaced
    //! by. At 1 the label is centred between the two; the lower it goes the
    //! more it belongs to the column under it rather than to the rule, which is
    //! the whole reason a label is nearer its value than its neighbours.
    private const LABEL_GAP_RATIO = 0.6;

    //! The progress bar's thickness, as a divisor of the display width. Given
    //! 390px that is a 10px bar.
    private const BAR_PEN_DIV = 39;

    //! The gap between the two runs of text that share a line, as a divisor of
    //! the display width.
    private const PAIR_GAP_DIV = 40;

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

    //! The same face at the size half the display can carry, which is a good
    //! deal less than the whole one. A finish time and its standing share a
    //! line, and two of those have to stack inside a band whose far end tapers
    //! away into the bezel — so the size pays twice over, once in the width
    //! that pushes the line in towards the middle of the face and again in the
    //! depth it takes out of the stack. At 48px both lines clear the inset with
    //! a standing run out to two digits of minutes, and the figures still hang
    //! clear of the tails of the name over them.
    private const FIGURE_FONT_HALF_PX = 48;

    private var _face as Face;

    //! Whether the field has been given a half-screen
    var half as Boolean;

    //! The figure font, at whichever size the field has the room for. Falls
    //! back to FONT_LARGE on a device that cannot supply the face at the size
    //! asked for.
    var figureFont as FontType;

    //! The progress bar's thickness, and the gap between two runs of text that
    //! share a line, both in pixels.
    var barPen as Number;
    var pairGap as Number;

    //! How far either side of centre the outer pace columns sit.
    var paceColumn as Float;

    //! The rows of the whole face.
    var yHr as Number;
    var yRule as Number;
    var yPaceLabel as Number;
    var yPaceValue as Number;
    var yBar as Number;
    var yName as Number;
    var yRemaining as Number;

    //! The rows of the half-height field: for each projection, the line naming
    //! it and the line of figures under that.
    var yProjLabel as Array<Number>;
    var yProjValue as Array<Number>;
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
        yProjLabel = [0, 0] as Array<Number>;
        yProjValue = [0, 0] as Array<Number>;
        yTrain = 0;
    }

    //! Solve the layout for the box the watch has given the field. `labels` are
    //! the projection labels and `train` the image drawn beside them, both of
    //! which the half-height layout is measured against.
    function solve(
        dc as Dc, labels as Array<String>, train as Graphics.BitmapReference
    ) as Void {
        barPen = dc.getWidth() / BAR_PEN_DIV;
        pairGap = dc.getWidth() / PAIR_GAP_DIV;
        // Treat as half screen if field is less than 75% of display height
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

    //! How much of a span a run of rows fills with ink: what each reaches above
    //! its baseline plus what it reaches below.
    private function inkHeight(
        up as Array<Float>, down as Array<Float>
    ) as Float {
        var ink = 0.0;
        for (var i = 0; i < up.size(); i += 1) {
            ink += up[i] + down[i];
        }
        return ink;
    }

    //! The gap that fills what is left of a span once that ink is taken out.
    //! Each weight is a share of it: one for the gap before each row, and one
    //! more to close the span.
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
    //! its weight's worth of the gap.
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
    //! Reading down it, the gaps are
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
    //! the group above them solves against that, and its gap places the bar,
    //! which in turn spans the group below.
    //!
    //! The pace digits sit on the middle of the face because that is where the
    //! chord is longest, which is what lets their columns stand furthest apart.
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
        // digits. The rule is a row of no ink at all.
        var topUp = [figCap, 0.0, labelX] as Array<Float>;
        var topDown = [0.0, 0.0, 0.0] as Array<Float>;
        var topGaps = [1.0, 1.0, 1.0, LABEL_GAP_RATIO] as Array<Float>;
        var above = unitGap(paceTop, topUp, topDown, topGaps);
        var upperRows = stack(0.0, above, topUp, topDown, topGaps);
        yHr = Roboto.yForBaseline(upperRows[0], figureFont);
        yRule = (upperRows[1] + 0.5).toNumber();
        yPaceLabel = Roboto.yForBaseline(upperRows[2], Graphics.FONT_XTINY);

        // E closes the top group, and the bar hangs its own half width below.
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

    //! Solve the vertical rhythm of the half-height field: two blocks, each a
    //! line naming a projection over the finish time it is heading for and the
    //! standing beside it, with the label nearer its own figures than the block
    //! above by the same LABEL_GAP_RATIO the whole face is spaced by.
    //!
    //! Both blocks are built out from whichever end of the band is nearer the
    //! middle of the face, since that is the end with width in it; the other
    //! tapers into the bezel and is left empty. How far they may run is set by
    //! the widest of the four rows, and the block is spaced to reach exactly
    //! that far — so the same solve gives the same layout whether the field has
    //! been put above the middle of the face or below it.
    private function solveHalf(
        dc as Dc, labels as Array<String>, train as Graphics.BitmapReference
    ) as Void {
        var h = dc.getHeight();
        var labelUp = Roboto.inkUp(Graphics.FONT_XTINY);
        var labelDown = Roboto.inkDown(Graphics.FONT_XTINY);
        var figCap = Roboto.capHeight(figureFont);

        // The figure lines are the wide ones, measured on the longest they get:
        // a finish over the hour, and a standing run out to two digits of
        // minutes. The labels are shorter than that but are checked anyway,
        // since it is the figure size rather than they that is tuned.
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

        // Four rows of ink: a label at the ratio above its own figures, a full
        // gap between the blocks, and a full gap at the near end of the band.
        // The far end is simply where the block stops, so the whole thing
        // mirrors about the near end whichever way up the field has been put.
        var lower = _face.belowCentre();
        var r = LABEL_GAP_RATIO;
        var up = [labelUp, figCap, labelUp, figCap] as Array<Float>;
        var down = [labelDown, 0.0, labelDown, 0.0] as Array<Float>;
        var gaps = lower
            ? ([1.0, r, 1.0, r, 0.0] as Array<Float>)
            : ([0.0, r, 1.0, r, 1.0] as Array<Float>);

        // A band too shallow for its own ink is filled from the near end and
        // allowed to run off the far one, where there was no width to draw in
        // anyway.
        var ink = inkHeight(up, down);
        if (span < ink) { span = ink; }

        var gap = unitGap(span, up, down, gaps);
        var rows = stack(lower ? 0.0 : h - span, gap, up, down, gaps);
        yProjLabel = [
            Roboto.yForBaseline(rows[0], Graphics.FONT_XTINY),
            Roboto.yForBaseline(rows[2], Graphics.FONT_XTINY)
        ] as Array<Number>;
        yProjValue = [
            Roboto.yForBaseline(rows[1], figureFont),
            Roboto.yForBaseline(rows[3], figureFont)
        ] as Array<Number>;

        // Put the image as far towards the outer edge as the circular safe
        // inset permits. The reach is measured at its top corners, not merely
        // at its centre, so the whole rectangular bitmap clears the bezel.
        var imageHalfW = train.getWidth() / 2.0;
        var imageHalfH = train.getHeight() / 2.0;
        var imageReach = _face.reachFor(imageHalfW) - imageHalfH;
        var imageCentre = _face.h / 2.0 + (lower ? imageReach : -imageReach);
        yTrain = (imageCentre - imageHalfH - _face.offY + 0.5).toNumber();
    }

    //! How far either side of centre the outer pace columns sit, so that they
    //! stand as far apart as the face allows: the ink of an outer pace lands on
    //! the circle the safe inset leaves.
    //!
    //! Taken at the digits' baseline. Fmt.pace() only ever emits digits, a
    //! colon and a dash, none of which descend, so the row's ink stops there
    //! rather than at the bottom of the line box. The pace ink is centred on
    //! the face, which leaves the top of the digits as far above the middle as
    //! the baseline is below it — so either edge answers the same question.
    //!
    //! The labels are centred on the same columns and are the shorter row, so
    //! they follow the paces out without needing to be measured themselves.
    private function paceColumnOffset(dc as Dc, baseline as Float) as Float {
        // Every digit in this face is one width, so any four-character pace is
        // as wide as the row ever gets — measured in advances, off which the
        // ink stops short by a side bearing at each end.
        var half = dc.getTextWidthInPixels("0:00", figureFont) / 2.0
            - Roboto.digitBearing(figureFont);
        return _face.halfWidthAt((baseline + 0.5).toNumber()) - half;
    }
}
