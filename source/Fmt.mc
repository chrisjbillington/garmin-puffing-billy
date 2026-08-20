import Toybox.Lang;

//! The figures on the face, as strings. Each takes a duration in seconds and
//! rounds it to the nearest whole one before splitting it, so that the parts
//! either side of a colon always belong to the same second.
module Fmt {

    //! A pace in seconds per km as m:ss, or a placeholder before the runner has
    //! moved or if pace is above 10 minutes per km. The minutes are always a 
    //! single digit, so the string is always four characters wide.
    function pace(paceS as Float?) as String {
        if (paceS == null || paceS <= 0.0) {
            return "-:--";
        }
        var whole = (paceS + 0.5).toNumber();
        if (whole > 599) {
            return "-:--";
        }
        return (whole / 60).format("%d") + ":" + (whole % 60).format("%02d");
    }

    //! Whether aheadBehind() draws this offset with a minus sign, i.e. time in
    //! hand by the same rounded figure the string shows. Colour aheadBehind()'s
    //! output by this, not by the raw offset, so the colour and the sign always
    //! agree.
    function ahead(offS as Float) as Boolean {
        return offS < 0.0 && (-offS + 0.5).toNumber() > 0;
    }

    //! The difference between a finishing time and the target finishing
    //! time, as a signed m:ss. Negative is time in hand. The sign
    //! comes from the rounded figure, so the half second either side of the
    //! plan reads as +0:00.
    function aheadBehind(offS as Float) as String {
        var magnitude = (offS < 0.0) ? -offS : offS;
        var whole = (magnitude + 0.5).toNumber();
        var sign = ahead(offS) ? "-" : "+";
        return sign
            + (whole / 60).format("%d") + ":" + (whole % 60).format("%02d");
    }
}
