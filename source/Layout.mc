import Toybox.Graphics;
import Toybox.Lang;

//! Where every row on the face is drawn. Solved once, when the watch tells the
//! field how much of the display it has been given, and read on every draw.
//!
//! Each y is where a row is drawn, not the top of its ink: rows are placed by
//! their baselines and the ink standing either side of them, which is what
//! Roboto measures.
class Layout {

    //! The share of the display a field must be given before it is drawn with
    //! the race detail. Below that there is no room for seven rows, and the
    //! projections are drawn in their place.
    private const DETAIL_MIN_SHARE = 0.75;

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

    //! Whether the field has been given so little of the display that the
    //! projections are drawn in place of the race detail.
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

    //! The rows of the half-height field: one block of a label line over a
    //! figure, and the step down to the next block.
    var yProjLabel as Number;
    var yProjValue as Number;
    var yProjPitch as Number;
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
        yProjPitch = 0;
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
        half = dc.getHeight() < DETAIL_MIN_SHARE * _face.h;

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
    //! the whole top group solves at once — D and C are both multiples of the
    //! same gap, so the space above the digits divides into 3 + LABEL_GAP_RATIO
    //! of it — and that gap places the bar, which in turn places the two rows
    //! under it.
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

        // A + B + C + D spans the display top to the pace digits, less the two
        // rows of ink standing in it. Three of those gaps are the group's, the
        // fourth is D at its own fraction of one.
        var above = (paceTop - labelX - figCap) / (3.0 + LABEL_GAP_RATIO);
        var labelBase = paceTop - above * LABEL_GAP_RATIO;
        var labelTop = labelBase - labelX;
        yPaceLabel = Roboto.yForBaseline(labelBase, Graphics.FONT_XTINY);

        yRule = (labelTop - above + 0.5).toNumber();
        yHr = Roboto.yForBaseline(labelTop - 2.0 * above, figureFont);

        // E closes the top group, and the bar hangs its own half width below.
        yBar = (paceBase + above + barPen / 2.0 + 0.5).toNumber();

        // F + G + H likewise, over the two rows of ink below the bar.
        var barBottom = yBar + barPen / 2;
        var below = (h - barBottom - nameCap - figCap) / 3.0;
        yName = Roboto.yForBaseline(
            barBottom + below + nameCap, Graphics.FONT_TINY
        );
        yRemaining = Roboto.yForBaseline(
            barBottom + 2.0 * below + nameCap + figCap, figureFont
        );

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
        var nameUp = Roboto.inkUp(Graphics.FONT_XTINY);
        var nameDown = Roboto.inkDown(Graphics.FONT_XTINY);
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

        // Four rows of ink, and between and before them two full gaps and two
        // at the label ratio, so that each label reads as belonging to the
        // figures under it rather than to the block above.
        var ink = 2.0 * (nameUp + nameDown + figCap);
        var gaps = 2.0 + 2.0 * LABEL_GAP_RATIO;
        var gap = (span - ink) / gaps;
        if (gap < 0.0) { gap = 0.0; }
        var inner = gap * LABEL_GAP_RATIO;

        var lower = _face.belowCentre();
        var top = lower ? gap : h - (ink + gaps * gap);
        yProjLabel = Roboto.yForBaseline(top + nameUp, Graphics.FONT_XTINY);
        yProjValue = Roboto.yForBaseline(
            top + nameUp + nameDown + inner + figCap, figureFont
        );
        yProjPitch = (nameUp + nameDown + inner + figCap + gap + 0.5).toNumber();

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
