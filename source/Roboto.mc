import Toybox.Graphics;
import Toybox.Lang;

//! Glyph metrics within the line box, as fractions of the requested font
//! height. Every font on this face is a Roboto — the system text fonts and the
//! scalable one alike — and they share these: in a line of 2400 units, an
//! ascent of 1900, a cap height of 1456 and an x-height of 1082.
//! Graphics.getFontAscent() reports the ascent; the API does not report the
//! rest, so we take them from the font itself.
//!
//! We position rows by these rather than by their line boxes, since the figures
//! and descenderless names on this face have no ink below the baseline while
//! the line box includes the font's full descent.
module Roboto {

    const CAP = 1456.0 / 2400.0;
    const X_HEIGHT = 1082.0 / 2400.0;

    //! Ink extent of a line of lowercase label text above and below its
    //! baseline, on the same scale: a stem 1557 up, a tail 426 down.
    const INK_UP = 1557.0 / 2400.0;
    const INK_DOWN = 426.0 / 2400.0;

    //! The narrowest side bearing of any digit, on the same scale. Glyphs are
    //! spaced by their advance, which includes the side bearing, so
    //! getTextWidthInPixels() reads wider than the ink drawn. We take the
    //! smallest, 60 units on a 4; the largest is 115 on a 0. A pace can begin
    //! or end on any digit.
    const DIGIT_BEARING = 60.0 / 2400.0;

    //! The height of a capital, and of a lowercase letter with neither stem nor
    //! descender.
    function capHeight(font as FontType) as Float {
        return Graphics.getFontHeight(font) * CAP;
    }

    function xHeight(font as FontType) as Float {
        return Graphics.getFontHeight(font) * X_HEIGHT;
    }

    //! Ink extent of a line of label text in this font above and below its
    //! baseline.
    function inkUp(font as FontType) as Float {
        return Graphics.getFontHeight(font) * INK_UP;
    }

    function inkDown(font as FontType) as Float {
        return Graphics.getFontHeight(font) * INK_DOWN;
    }

    //! Side bearing at either end of a row of digits in this font.
    function digitBearing(font as FontType) as Float {
        return Graphics.getFontHeight(font) * DIGIT_BEARING;
    }

    //! The draw position y that puts a row's baseline on `baseline`.
    //! TEXT_JUSTIFY_VCENTER centres the line box, which extends farther below
    //! the baseline than the ink.
    function yForBaseline(baseline as Float, font as FontType) as Number {
        return (baseline + Graphics.getFontHeight(font) / 2.0
                - Graphics.getFontAscent(font) + 0.5).toNumber();
    }

    //! The baseline of a row drawn at y. The inverse of yForBaseline().
    function baselineAt(y as Number, font as FontType) as Float {
        return y - Graphics.getFontHeight(font) / 2.0
            + Graphics.getFontAscent(font);
    }
}
