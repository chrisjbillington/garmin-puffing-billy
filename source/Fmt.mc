import Toybox.Lang;

//! The figures on the face, as strings. Each takes a duration in seconds and
//! rounds it to the nearest whole one before breaking it up, so that the parts
//! either side of a colon always belong to the same second.
module Fmt {

    //! A pace in seconds per km as m:ss, or a placeholder when there is no
    //! sensible pace to show — before the runner has moved, or so slow that the
    //! number would be meaningless anyway. The minutes are always a single
    //! digit, so the string is always four characters wide.
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

    //! A duration as h:mm:ss, or m:ss under the hour.
    function duration(s as Float) as String {
        var whole = (s + 0.5).toNumber();
        var seconds = (whole % 60).format("%02d");
        if (whole < 3600) {
            return (whole / 60).format("%d") + ":" + seconds;
        }
        return (whole / 3600).format("%d") + ":"
            + (whole / 60 % 60).format("%02d") + ":" + seconds;
    }

    //! Where a projection stands against the plan, as a signed m:ss. Negative
    //! is time in hand.
    function standing(offS as Float) as String {
        var ahead = offS < 0.0;
        var whole = ((ahead ? -offS : offS) + 0.5).toNumber();
        return (ahead ? "-" : "+")
            + (whole / 60).format("%d") + ":" + (whole % 60).format("%02d");
    }
}
