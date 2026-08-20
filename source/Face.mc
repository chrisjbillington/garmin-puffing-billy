import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

//! The round display, and the field's placement on it.
//!
//! A field given part of the display is off-centre, so the width available
//! at a row comes from the display size and this placement, not from the
//! field's own box. Every layout is full width, so only y is offset.
class Face {

    //! Clearance kept from the edge of the display. The watch periodically
    //! shifts the whole display by a few pixels to limit burn-in, which
    //! occludes regions close to the edge.
    private const SAFE_INSET = 8;

    //! The display, in pixels.
    var w as Number;
    var h as Number;

    //! Top and height of the field's box, in pixels.
    var offY as Number;
    var fieldH as Number;

    function initialize() {
        var settings = System.getDeviceSettings();
        w = settings.screenWidth;
        h = settings.screenHeight;
        offY = 0;
        fieldH = h;
    }

    //! Set the field's box.
    function place(top as Number, height as Number) as Void {
        offY = top;
        fieldH = height;
    }

    //! Half the width available at y down the field, within the display circle
    //! inset by SAFE_INSET. Zero above and below that circle.
    function halfWidthAt(y as Number) as Float {
        var r = w / 2 - SAFE_INSET;
        var dy = offY + y - h / 2;
        if (dy < 0) { dy = -dy; }
        if (dy >= r) {
            return 0.0;
        }
        // sqrt() is typed as Float or Double.
        return Math.sqrt(r * r - dy * dy).toFloat();
    }

    //! The inverse of halfWidthAt(): the maximum distance from the display's
    //! centre for a row of half-width `half`, within the inset circle.
    function reachFor(half as Float) as Float {
        var r = w / 2 - SAFE_INSET;
        if (half >= r) {
            return 0.0;
        }
        return Math.sqrt(r * r - half * half).toFloat();
    }

    //! Whether a row at y down the field is above the middle of the display.
    function aboveCentre(y as Number) as Boolean {
        return offY + y < h / 2;
    }

    //! Whether the field's centre is below the display's centre, and so whether
    //! the near end of its band — the wider end — is its top or its bottom.
    function belowCentre() as Boolean {
        return 2 * offY + fieldH > h;
    }

    //! The inset circle, for checking on the watch how far the bezel actually
    //! covers. Temporary — delete once SAFE_INSET is settled.
    function drawInset(dc as Dc) as Void {
        dc.drawCircle(w / 2, h / 2 - offY, w / 2 - SAFE_INSET);
    }

    //! Distance from the middle of the display to the near end of the field's
    //! band. Zero if the field contains the display's centre.
    function nearEdge() as Float {
        var d = belowCentre()
            ? offY - h / 2.0
            : h / 2.0 - (offY + fieldH);
        return d > 0.0 ? d : 0.0;
    }
}
