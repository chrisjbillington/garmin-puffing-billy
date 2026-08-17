import Toybox.Activity;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Math;

//! The race in progress: which segment is being run, how far and how long into
//! it, and how hard it is being run against the plan. Before the activity is
//! started, the segment it reports cycles through the course instead.
class Race {

    //! Distances are in metres and activity times in milliseconds, whereas
    //! paces are per km and every projection is in seconds.
    private const M_PER_KM = 1000.0;
    private const MS_PER_S = 1000.0;

    //! Distance at initial target pace with which the performance ratio exponential
    //! moving average is seeded. This is just to prevent division by zero, and doesn't
    //! meaningfully affect early performance estimates which are still dominated by
    //! actual data
    private const PACE_SEED_M = 1.0;

    private var _course as Course;

    //! Index of the gate being watched for, so equal to the segment count once
    //! the last one has been crossed. Gates are tested one at a time and in
    //! order — this is a race on a known course, and testing only the next one
    //! is both cheaper and immune to a doubling-back section triggering a later
    //! gate.
    private var _next as Number;

    //! Whether the activity is yet to be started, and, while it is, which
    //! segment is reported as though it were at the start of it. The index
    //! steps on by one with each reading, so every segment of the course is
    //! shown in turn.
    //!
    //! Readings come once a second however often the face is drawn, so that is
    //! the shortest a segment is on screen for. The index starts on the last
    //! segment, so the first step comes round to the first.
    private var _previewing as Boolean;
    private var _preview as Number;

    //! The most recent fix, in degrees. Held from the last reading that had
    //! one, not simply the last second, so that a GPS dropout leaves a longer
    //! line to test against rather than a hole detection can fall through.
    private var _lastLat as Double?;
    private var _lastLon as Double?;

    private var _distanceM as Float;

    //! Odometer reading at the start of the current segment, so that the
    //! distance still to run is measured from the last gate rather than from
    //! the start of the race. The odometer drifts against the course — about
    //! 1-2% on a real watch, far more under simulated GPS — and measuring each
    //! segment fresh keeps that drift from compounding over thirteen km.
    private var _segmentStartM as Float;

    //! Elapsed time, in milliseconds, and its reading at the start of the
    //! current segment.
    private var _elapsedMs as Number;
    private var _segmentStartMs as Number;

    //! Actual time taken, and time taken at target pace, decayed by the distance
    //! run. Their ratio is a smoothed measure of actual speed as a fraction of
    //! target speed, with a smoothing length scale of perfRatioScaleM.
    //!
    //! Both start at PACE_SEED_M worth of time at the initial target pace, to
    //! prevent division by zero.
    private var _takenS as Float;
    private var _allowedS as Float;

    //! Current speed in metres per second and heart rate in bpm, straight from
    //! Activity.Info. Null when the watch has nothing to report yet.
    var speedMps as Float?;
    var heartRate as Number?;

    function initialize(course as Course) {
        _course = course;
        _next = 0;
        _previewing = false;
        _preview = _course.size() - 1;
        _lastLat = null;
        _lastLon = null;
        _distanceM = 0.0;
        _segmentStartM = 0.0;
        _elapsedMs = 0;
        _segmentStartMs = 0;
        speedMps = null;
        heartRate = null;

        // Equal totals, so the race opens reading its target rather than
        // whatever the first stride happened to measure.
        var seeded = _course.paceS(0) * PACE_SEED_M / M_PER_KM;
        _takenS = seeded;
        _allowedS = seeded;
    }

    //! Update performance ratio EMAs with a distance increment of `ds` metres
    //! and time increment of `dt` seconds
    private function accumulate(ds as Float, dt as Float) as Void {
        var decay = Math.pow(Math.E, -ds / _course.perfRatioScaleM).toFloat();
        _takenS = decay * _takenS + dt;
        _allowedS = decay * _allowedS + ds / M_PER_KM * _course.paceS(_next);
    }

    //! Announce a new segment with a tone and vibration pattern, if watch
    //! supports tones/vibration
    private function alertNewSegment() as Void {
        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_LAP);
        }
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(100, 250),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(100, 250)
            ]);
        }
    }

    //! Move on to the next segment, taking the current odometer and clock
    //! readings as the boundary.
    private function advance() as Void {
        _segmentStartM = _distanceM;
        _segmentStartMs = _elapsedMs;
        _next += 1;
        alertNewSegment();
    }

    //! Take a second's worth of fresh activity data.
    function update(info as Activity.Info) as Void {
        speedMps = info.currentSpeed;
        heartRate = info.currentHeartRate;

        if (finished()) {
            return;
        }

        // Not started: step the preview on and take nothing else from the
        // reading.
        _previewing = info.timerState == Activity.TIMER_STATE_OFF;
        if (_previewing) {
            _preview = (_preview + 1) % _course.size();
            return;
        }

        var t = info.elapsedTime;
        var d = info.elapsedDistance;

        // Before the odometer and the clock are moved on, and before any gate
        // is crossed, so that the step just taken is charged to the segment it
        // was run in. A second the watch has no reading for leaves both where
        // they are, and the step it belonged to is folded into the next one.
        if (t != null && d != null) {
            accumulate(d - _distanceM, (t - _elapsedMs) / MS_PER_S);
            _distanceM = d;
            _elapsedMs = t;
        }

        var crossedGate = false;
        var loc = info.currentLocation;
        if (loc != null) {
            var deg = loc.toDegrees();
            var lat = deg[0].toDouble();
            var lon = deg[1].toDouble();
            if (_lastLat != null && _lastLon != null) {
                crossedGate = _course.crossedGate(
                    _next, _lastLat, _lastLon, lat, lon
                );
            }
            _lastLat = lat;
            _lastLon = lon;
        }
        if (crossedGate || remainingM() < -_course.overdistanceM) {
            advance();
        }
    }

    //! Whether the last gate has been crossed.
    function finished() as Boolean {
        return _next >= _course.size();
    }

    //! The segment on show, as an index into the course: the one being run, or
    //! the one being previewed while the race is yet to start.
    function segment() as Number {
        return _previewing ? _preview : _next;
    }

    //! Ground covered in this segment so far, in metres.
    function ranInSegmentM() as Float {
        return _distanceM - _segmentStartM;
    }

    //! Time since the start of the current segment, in seconds. Null while
    //! previewing.
    function segmentAgeS() as Float? {
        if (_previewing) {
            return null;
        }
        return (_elapsedMs - _segmentStartMs) / MS_PER_S;
    }

    //! Distance still to run in segment i, in metres. Goes negative once the
    //! runner is past where the gate should have been but has not yet crossed
    //! it — which is the normal case for a metre or two, since the odometer and
    //! the course never agree exactly.
    private function remainingInM(i as Number) as Float {
        return _course.lengthM(i) - ranInSegmentM();
    }

    //! Distance still to run in the segment on show. Nothing has been run in a
    //! previewed one, so that is the whole of it.
    function remainingM() as Float {
        return remainingInM(segment());
    }

    //! Average pace over the part of the current segment run so far, in seconds
    //! per km. Null until far enough into the segment to divide by.
    function segmentPaceS() as Float? {
        var km = ranInSegmentM() / M_PER_KM;
        if (km <= 0.0) {
            return null;
        }
        return ((_elapsedMs - _segmentStartMs) / MS_PER_S) / km;
    }

    //! Instantaneous pace, in seconds per km.
    function currentPaceS() as Float? {
        var speed = speedMps;
        if (speed == null || speed <= 0.0) {
            return null;
        }
        return M_PER_KM / speed;
    }

    //! Plan time still to run, in seconds: what is left of the current segment
    //! at its own target pace, and every segment after it at theirs. Measured
    //! against the segment being run rather than the one on show, so that a
    //! preview leaves the projections reading the whole plan.
    private function planRemainingS() as Float {
        return remainingInM(_next) / M_PER_KM * _course.paceS(_next)
            + _course.planAfterS(_next);
    }

    //! The finish time the race is on for if the rest of it is run to plan, in
    //! seconds of elapsed time. Its standing against the plan is just the time
    //! won or lost so far, since everything ahead is being counted at its
    //! target.
    function targetFinishS() as Float {
        return _elapsedMs / MS_PER_S + planRemainingS();
    }

    //! The finish time the race is on for if the rest of it is run at the
    //! fraction of target pace the last PACE_WINDOW_M has been run at, applied
    //! to every segment still to come.
    function perfRatioFinishS() as Float {
        return _elapsedMs / MS_PER_S + _takenS / _allowedS * planRemainingS();
    }
}
