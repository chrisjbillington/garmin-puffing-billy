import Toybox.Graphics;
import Toybox.Lang;

//! Where a glyph stands in its line box, as fractions of the height the font
//! was asked for. Every font on this face is a Roboto — the system text fonts
//! and the scalable one alike — and they share these: in a line of 2400 units,
//! an ascent of 1900, a cap height of 1456 and an x-height of 1082. Ascent
//! comes from Graphics.getFontAscent(); the rest the API does not report, so
//! they are taken from the font itself.
//!
//! Rows are placed by these rather than by their line boxes, since the fonts
//! carry descent that the strings on this face — figures, and names without
//! descenders — never use.
module Roboto {

    const CAP = 1456.0 / 2400.0;
    const X_HEIGHT = 1082.0 / 2400.0;

    //! How far a line of lowercase label text reaches either side of its
    //! baseline, on the same scale: from a stem 1557 up to a tail 426 down.
    const INK_UP = 1557.0 / 2400.0;
    const INK_DOWN = 426.0 / 2400.0;

    //! The narrowest blank a digit carries beside its ink, on the same scale.
    //! Glyphs are spaced by their advance, which includes that blank, so a row
    //! measured with getTextWidthInPixels() reads wider than what is drawn.
    //! Taken as the smallest any digit has — 60 units, on a 4, against 115 on a
    //! 0 — because a pace can begin or end on any of them, and it is the
    //! tightest one that has to clear the margin.
    const DIGIT_BEARING = 60.0 / 2400.0;

    //! The height of a capital, and of a lowercase letter with neither stem nor
    //! descender.
    function capHeight(font as FontType) as Float {
        return Graphics.getFontHeight(font) * CAP;
    }

    function xHeight(font as FontType) as Float {
        return Graphics.getFontHeight(font) * X_HEIGHT;
    }

    //! How far a line of label text in this font reaches above and below its
    //! baseline.
    function inkUp(font as FontType) as Float {
        return Graphics.getFontHeight(font) * INK_UP;
    }

    function inkDown(font as FontType) as Float {
        return Graphics.getFontHeight(font) * INK_DOWN;
    }

    //! The blank beside the ink at either end of a row of digits in this font.
    function digitBearing(font as FontType) as Float {
        return Graphics.getFontHeight(font) * DIGIT_BEARING;
    }

    //! The y a row must be drawn at for its baseline to fall on `baseline`.
    //! TEXT_JUSTIFY_VCENTER centres the line box, which reaches further below
    //! the baseline than anything drawn here actually goes.
    function yForBaseline(baseline as Float, font as FontType) as Number {
        return (baseline + Graphics.getFontHeight(font) / 2.0
                - Graphics.getFontAscent(font) + 0.5).toNumber();
    }

    //! Where the baseline of a row drawn at y falls. The inverse of
    //! yForBaseline().
    function baselineAt(y as Number, font as FontType) as Float {
        return y - Graphics.getFontHeight(font) / 2.0
            + Graphics.getFontAscent(font);
    }
}
