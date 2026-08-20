import Toybox.Graphics;
import Toybox.Lang;

//! The y coordinate of every row on the face.
//!
//! Each y is a draw position, not the top of the row's ink: we position rows by
//! baseline and by the ink above and below it, as measured by Roboto.
class Layout {

    //! Gap between a label's baseline and the top of the digits below it, as
    //! a fraction of the label font's height. Places the pace labels above
    //! the pace digits and the standing labels above the standings.
    private const LABEL_GAP = 0.55;

    //! The progress bar's thickness, as a divisor of the display width. Given
    //! 390px that is a 10px bar.
    private const BAR_PEN_DIV = 39;

    //! The font we use for all figures, as a height in pixels and a scalable
    //! face. The system fonts step from FONT_LARGE, with 37px digits, to
    //! FONT_NUMBER_MILD, with 49px digits. At 70px this face gives 43px digits.
    //!
    //! Condensed digits are a sixth narrower than Roboto proper, giving 27px
    //! between the three pace columns.
    private const FIGURE_FONT_PX = 70;
    private const FIGURE_FONT_FACE = "RobotoCondensedRegular";

    //! The BPM label's face, and its size as a fraction of the other
    //! labels' font height.
    private const BPM_FONT_FACE = "RobotoRegular";
    private const BPM_FONT_FRAC = 0.8;

    //! The gap between the heart rate's baseline and the top of BPM below
    //! it, in pixels.
    private const BPM_GAP = 10;

    private var _face as Face;

    //! The figure font. FONT_LARGE if the device cannot supply the scalable
    //! face.
    var figureFont as FontType;

    //! The progress bar's thickness, in pixels.
    var barPen as Number;

    //! The gap between a run of figures and the label at its side, in pixels.
    var labelPad as Number;

    //! Distance from the centre of the face to the centre of an outer pace
    //! column.
    var paceColumn as Float;

    //! The rows of the face. Each standing and its label are centred on one
    //! of the two standing columns, the label the label gap above the
    //! standing.
    var yHr as Number;
    var yStandingLabel as Number;
    var yStanding as Number;
    var yPaceLabel as Number;
    var yPaceValue as Number;
    var yBar as Number;
    var yName as Number;
    var yRemaining as Number;

    //! Draw positions of the BPM and km labels, below the heart rate and
    //! beside the remaining distance, and BPM's reduced font. FONT_XTINY if
    //! the device cannot supply the scalable face.
    var yBpm as Number;
    var yKm as Number;
    var bpmFont as FontType;

    //! Centres of the standings' columns: the midpoints of the two halves of
    //! the chord at the standings' mid-ink height. Each standing and its
    //! label are centred on one of these.
    var xPlan as Number;
    var xPerf as Number;

    //! The rule between the standings row and the pace row: its y, and the
    //! y at which the rules between the pace columns end.
    var yRule as Number;
    var yPaceRuleEnd as Number;

    //! The rule curved around the heart rate: the parabola
    //! y = yHrRule - hrRuleK * dx^2, where dx is the horizontal distance
    //! from the centre of the face. Its vertex is midway between BPM's
    //! baseline and the standings' ink top, and where it meets the inset
    //! circle its tangents pass through the junction of the vertical and
    //! horizontal rules, at yRule on the centreline.
    var yHrRule as Number;
    var hrRuleK as Float;

    function initialize(face as Face) {
        _face = face;

        figureFont = Graphics.FONT_LARGE;
        barPen = 1;
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
        yRule = 0;
        yPaceRuleEnd = 0;
        yHrRule = 0;
        hrRuleK = 0.0;
    }

    //! Solve the layout for the field's box: six rows separated by a uniform
    //! gap.
    //!
    //!     A  heart rate digits, ink top to baseline
    //!     B  standings and their labels, label x-height top to digit
    //!        baseline; label ascenders extend above the row
    //!     C  paces and their labels, the same extents
    //!     D  the bar, excluding the position marker
    //!     E  waypoint name, cap top to baseline
    //!     F  remaining-distance figures, ink top to baseline, with km at
    //!        their right
    //!
    //! The top of A, for a three-digit heart rate, is on the inset circle,
    //! and so is the bottom of F for its widest figures; F is raised where
    //! km would cross the circle. The five gaps between the rows are equal.
    //! km shares the distance figures' ink top. BPM is centred below the
    //! heart rate, BPM_GAP under its baseline, and takes no part in the
    //! spacing.
    function solve(dc as Dc) as Void {
        barPen = dc.getWidth() / BAR_PEN_DIV;

        figureFont = Graphics.FONT_LARGE;
        var scalable = Graphics.getVectorFont({
            :face => FIGURE_FONT_FACE,
            :size => FIGURE_FONT_PX
        });
        if (scalable != null) { figureFont = scalable; }

        var h = dc.getHeight();

        var figCap = Roboto.capHeight(figureFont);
        var labelX = Roboto.xHeight(Graphics.FONT_XTINY);
        var labelUp = Roboto.inkUp(Graphics.FONT_XTINY);
        var nameCap = Roboto.capHeight(Graphics.FONT_TINY);
        var labelGap =
            LABEL_GAP * Graphics.getFontHeight(Graphics.FONT_XTINY);
        var bearing = Roboto.digitBearing(figureFont);

        bpmFont = Graphics.FONT_XTINY;
        var bpmScaled = Graphics.getVectorFont({
            :face => BPM_FONT_FACE,
            :size => (BPM_FONT_FRAC
                * Graphics.getFontHeight(Graphics.FONT_XTINY)).toNumber()
        });
        if (bpmScaled != null) { bpmFont = bpmScaled; }
        var bpmCap = Roboto.capHeight(bpmFont);

        // Row A, with BPM below its baseline.
        var hrW = dc.getTextWidthInPixels("888", figureFont).toFloat();
        var hrTop = h / 2.0 - _face.reachFor(hrW / 2.0 - bearing);
        var hrBase = hrTop + figCap;
        var bpmBase = hrBase + BPM_GAP + bpmCap;
        yHr = Roboto.yForBaseline(hrBase, figureFont);
        yBpm = Roboto.yForBaseline(bpmBase, bpmFont);

        // Row F. The figures are centred without their sign, which hangs to
        // their left when the distance is negative, so the geometry uses the
        // unsigned four-character form. km's ink has no descender, so its
        // ink bottom is its baseline.
        var remW = dc.getTextWidthInPixels("8.88", figureFont).toFloat();
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

        // The horizontal rule is midway between the standings' baseline and
        // the pace labels' ink top; the pace-column rules end at the pace
        // digits' baseline.
        yRule = (standingBase + gap / 2.0 + 0.5).toNumber();
        yPaceRuleEnd = (paceBase + 0.5).toNumber();

        // The curved rule's vertex, midway between BPM's baseline and the
        // standings' ink top. A tangent to the parabola at dx has
        // y-intercept yHrRule + hrRuleK * dx^2, so tangents through the rule
        // junction at yRule force the parabola to meet the inset circle at
        // yRing, as high above the vertex as the junction is below it.
        yHrRule =
            ((bpmBase + standingBase - figCap) / 2.0 + 0.5).toNumber();
        var yRing = 2 * yHrRule - yRule;
        var ringHalf = _face.halfWidthAt(yRing);
        hrRuleK = 0.0;
        if (ringHalf > 0.0) {
            hrRuleK = (yRule - yHrRule) / (ringHalf * ringHalf);
        }

        var chordHalf = _face.halfWidthAt(
            (standingBase - figCap / 2.0 + 0.5).toNumber()
        );
        var mid = dc.getWidth() / 2.0;
        xPlan = (mid - chordHalf / 2.0 + 0.5).toNumber();
        xPerf = (mid + chordHalf / 2.0 + 0.5).toNumber();

        paceColumn = paceColumnOffset(dc, paceBase);
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
