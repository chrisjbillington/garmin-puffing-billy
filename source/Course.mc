import Toybox.Application;
import Toybox.Lang;

//! The course we're running: segment names, lengths, target paces, GPS "gates" defining
//! the end of each segment, and other course-related configuration
//! 
//! The watch knows nothing of the course beyond this. It is compiled in as a
//! JSON resource built by make_segments.py; see README.md for that pipeline.
class Course {

    //! Segment lengths are in metres, target paces per km.
    private const M_PER_KM = 1000.0;

    //! 2**31 semicircles to 180 degrees. Gate coordinates are held as integer
    //! semicircles because Monkey C loads JSON reals as 32-bit Float, whose
    //! steps span 1.3 m of longitude at this course. Integers are exact, at
    //! about a centimetre each, so it is the fix that is converted into their
    //! space, in Double, when a gate is tested.
    private const DEG_TO_SEMI = 2147483648.0d / 180.0d;

    private var _names as Array<String>;
    private var _lengths as Array<Number>;
    private var _paces as Array<Float>;
    private var _gates as Array<Number>;

    //! Total course length in metres, the time the whole plan comes to in
    //! seconds, and the distance-weighted average of the segment target paces
    //! in seconds per km. All fixed for the race, so worked out once rather
    //! than on every draw.
    var totalM as Float;
    var planS as Float;
    var meanPaceS as Float;

    //! How far past a gate the runner may get before the segment is advanced despite
    //! not encountering the gate, and the length scale over which the performance ratio
    //! exponential moving average is computed, both in metres. Set in config.toml.
    var overdistanceM as Float;
    var perfRatioScaleM as Float;

    //! Plan time still to come once each segment has been finished, in seconds, for use
    //! projecting finishing time
    private var _planAfter as Array<Float>;

    function initialize() {
        var data =
            Application.loadResource($.Rez.JsonData.Segments) as
            Dictionary<String, Object>;
        _names = data["names"] as Array<String>;
        _lengths = data["lengths"] as Array<Number>;
        _paces = data["paces"] as Array<Float>;
        _gates = data["gates"] as Array<Number>;

        overdistanceM = (data["overdistance"] as Number).toFloat();
        perfRatioScaleM = (data["perf_ratio_scale"] as Number).toFloat();

        totalM = 0.0;
        planS = 0.0;
        for (var i = 0; i < _lengths.size(); i += 1) {
            totalM += _lengths[i];
            planS += _lengths[i] / M_PER_KM * _paces[i];
        }
        meanPaceS = planS / (totalM / M_PER_KM);

        _planAfter = [] as Array<Float>;
        var done = 0.0;
        for (var i = 0; i < _lengths.size(); i += 1) {
            done += _lengths[i] / M_PER_KM * _paces[i];
            _planAfter.add(planS - done);
        }
    }

    function size() as Number {
        return _lengths.size();
    }

    //! The waypoint segment i is run towards.
    function name(i as Number) as String {
        return _names[i];
    }

    function lengthM(i as Number) as Number {
        return _lengths[i];
    }

    //! Segment i's target pace, in seconds per km.
    function paceS(i as Number) as Float {
        return _paces[i];
    }

    //! Plan time left once segment i has been finished, in seconds.
    function planAfterS(i as Number) as Float {
        return _planAfter[i];
    }

    //! Twice the signed area of the triangle abc, which is positive when c lies
    //! left of the directed line ab, negative when it lies right, and zero when
    //! the three are collinear. Only the sign is ever read.
    private function cross(
        ax as Double, ay as Double,
        bx as Double, by as Double,
        cx as Double, cy as Double
    ) as Double {
        return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    }

    //! Whether the step from (lat0, lon0) to (lat1, lon1), in degrees, passed
    //! through gate i.
    //!
    //! Two segments cross exactly when each separates the other's endpoints,
    //! which is four cross products and a comparison of their signs. Working in
    //! semicircles rather than metres is fine and saves projecting: scaling an
    //! axis by a positive constant scales all four cross products by that same
    //! constant, leaving every sign — and so the result — untouched.
    function crossedGate(
        i as Number,
        lat0 as Double, lon0 as Double,
        lat1 as Double, lon1 as Double
    ) as Boolean {
        // Four values per gate, left end then right end, each lat before lon.
        var ay = _gates[4 * i].toDouble();
        var ax = _gates[4 * i + 1].toDouble();
        var by = _gates[4 * i + 2].toDouble();
        var bx = _gates[4 * i + 3].toDouble();

        var cy = lat0 * DEG_TO_SEMI;
        var cx = lon0 * DEG_TO_SEMI;
        var dy = lat1 * DEG_TO_SEMI;
        var dx = lon1 * DEG_TO_SEMI;

        var d1 = cross(ax, ay, bx, by, cx, cy);
        var d2 = cross(ax, ay, bx, by, dx, dy);
        var d3 = cross(cx, cy, dx, dy, ax, ay);
        var d4 = cross(cx, cy, dx, dy, bx, by);

        return (d1 > 0) != (d2 > 0) && (d3 > 0) != (d4 > 0);
    }
}
