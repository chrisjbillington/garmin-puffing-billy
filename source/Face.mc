import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

//! The round display, and where on it the field has been placed.
//!
//! A field given only part of the display sits off the middle of the circle, so
//! it is the display and this placing, not the field's own box, that say how
//! much width a row has. Every data field layout on this face is full width, so
//! the field's horizontal middle is the circle's and only y is offset.
class Face {

    //! Clearance kept from the edge of the display. The watch shifts the whole
    //! display by a few pixels every so often to spare the panel from burn-in,
    //! and whatever it shifts towards goes under the bezel — so nothing may be
    //! drawn hard against the edge.
    private const SAFE_INSET = 10;

    //! The display, in pixels.
    var w as Number;
    var h as Number;

    //! The field's box: how far down the display its top sits, and how tall it
    //! is. Set by place() and read-only thereafter.
    var offY as Number;
    var fieldH as Number;

    function initialize() {
        var settings = System.getDeviceSettings();
        w = settings.screenWidth;
        h = settings.screenHeight;
        offY = 0;
        fieldH = h;
    }

    //! Record the box the watch has given the field.
    function place(top as Number, height as Number) as Void {
        offY = top;
        fieldH = height;
    }

    //! Half the width available at height y down the field, inside the circle
    //! the display leaves once SAFE_INSET is taken off it. Zero past that
    //! circle's top and bottom.
    function halfWidthAt(y as Number) as Float {
        var r = w / 2 - SAFE_INSET;
        var dy = offY + y - h / 2;
        if (dy < 0) { dy = -dy; }
        if (dy >= r) {
            return 0.0;
        }
        // toFloat() because sqrt() is typed as Float-or-Double, and a chord on
        // a display this size has no need of the extra precision.
        return Math.sqrt(r * r - dy * dy).toFloat();
    }

    //! The same circle read the other way: how far from the middle of the
    //! display a row reaching `half` pixels either side of centre may be drawn
    //! and still clear the inset.
    function reachFor(half as Float) as Float {
        var r = w / 2 - SAFE_INSET;
        if (half >= r) {
            return 0.0;
        }
        return Math.sqrt(r * r - half * half).toFloat();
    }

    //! Whether a row at y down the field sits above the middle of the display.
    function aboveCentre(y as Number) as Boolean {
        return offY + y < h / 2;
    }

    //! Whether the field as a whole sits below the middle of the display, and
    //! so whether the near end of its band — the end with width in it — is its
    //! top or its bottom.
    function belowCentre() as Boolean {
        return 2 * offY + fieldH > h;
    }

    //! How far that near end already stands from the middle of the display.
    //! Zero for a field that straddles the middle, which has its widest point
    //! inside it rather than at an edge.
    function nearEdge() as Float {
        var d = belowCentre()
            ? offY - h / 2.0
            : h / 2.0 - (offY + fieldH);
        return d > 0.0 ? d : 0.0;
    }
}
