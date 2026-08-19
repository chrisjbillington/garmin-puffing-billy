import Toybox.Activity;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Math;

//! The race in progress: the current segment, distance and time into it, and
//! actual pace as a fraction of target pace. Before the activity starts, the
//! reported segment cycles through the course.
class Race {

    //! Distances are in metres, activity times in milliseconds, paces in
    //! seconds per km, and projections in seconds.
    private const M_PER_KM = 1000.0;
    private const MS_PER_S = 1000.0;

    //! Seed distance for the performance ratio exponential moving averages, at
    //! the initial target pace. Prevents division by zero.
    private const PACE_SEED_M = 1.0;

    //! Slowest speed counted toward the performance ratio: 10 minutes per km,
    //! matching the bound past which Fmt.pace() shows a placeholder.
    private const MIN_RACING_SPEED_MPS = M_PER_KM / 600.0;

    private var _course as Course;

    //! Index of the next gate to test, equal to the segment count once the last
    //! gate has been crossed. Only this gate is tested each step.
    private var _next as Number;

    //! Whether the activity has yet to start, and the segment displayed until
    //! it does. The index advances by one per reading, so each segment shows
    //! for one second in turn. It starts on the last segment, so the first
    //! reading shows the first.
    private var _previewing as Boolean;
    private var _preview as Number;

    //! The most recent valid GPS fix, in degrees. After a dropout, the gate
    //! crossing test spans from this fix to the new one.
    private var _lastLat as Double?;
    private var _lastLon as Double?;

    private var _distanceM as Float;

    //! Odometer reading at the start of the current segment, so distance
    //! remaining is measured from the last gate. The odometer differs from
    //! course distance by 1-2% on a real watch and more under simulated GPS.
    private var _segmentStartM as Float;

    //! Elapsed time, in milliseconds, and its reading at the start of the
    //! current segment.
    private var _elapsedMs as Number;
    private var _segmentStartMs as Number;

    //! Actual time taken, and time taken at target pace, decayed by the
    //! distance run. Their ratio is a smoothed measure of actual speed as a
    //! fraction of target speed, with a smoothing length scale of
    //! perfRatioScaleM.
    private var _takenS as Float;
    private var _allowedS as Float;

    //! Current speed in metres per second and heart rate in bpm, straight from
    //! Activity.Info. Null when Activity.Info has no value.
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

        // Equal totals, so the ratio starts at 1.
        var seeded = _course.paceS(0) * PACE_SEED_M / M_PER_KM;
        _takenS = seeded;
        _allowedS = seeded;
    }

    //! Update performance ratio EMAs with a distance increment of `ds` metres
    //! and time increment of `dt` seconds.
    private function accumulate(ds as Float, dt as Float) as Void {
        var decay = Math.pow(Math.E, -ds / _course.perfRatioScaleM).toFloat();
        _takenS = decay * _takenS + dt;
        _allowedS = decay * _allowedS + ds / M_PER_KM * _course.paceS(_next);
    }

    //! Announce a new segment with a tone and vibration pattern, if the watch
    //! supports them.
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

    //! Advance to the next segment, recording the current odometer and elapsed
    //! time as its starting values.
    private function advance() as Void {
        _segmentStartM = _distanceM;
        _segmentStartMs = _elapsedMs;
        _next += 1;
        alertNewSegment();
    }

    //! Update the race state from an Activity.Info reading.
    function update(info as Activity.Info) as Void {
        speedMps = info.currentSpeed;
        heartRate = info.currentHeartRate;

        if (finished()) {
            return;
        }

        // During preview, advance the displayed segment and return.
        _previewing = info.timerState == Activity.TIMER_STATE_OFF;
        if (_previewing) {
            _preview = (_preview + 1) % _course.size();
            return;
        }

        var t = info.elapsedTime;
        var d = info.elapsedDistance;

        if (t != null && d != null) {
            var v = speedMps;
            if (v != null && v >= MIN_RACING_SPEED_MPS) {
                // Update the performance ratio before testing the gate, so a
                // step that crosses one is counted at the previous segment's
                // target pace.
                var dt = (t - _elapsedMs) / MS_PER_S;
                accumulate(v * dt, dt);
            }
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

    //! The displayed segment, as an index into the course: the one being run,
    //! or the previewed one while the race is yet to start.
    function segment() as Number {
        return _previewing ? _preview : _next;
    }

    //! Distance run in this segment so far, in metres.
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

    //! Distance still to run in segment i, in metres. Negative once the runner
    //! is past the segment's nominal length without having crossed its gate,
    //! which is normal for a metre or two.
    private function remainingInM(i as Number) as Float {
        return _course.lengthM(i) - ranInSegmentM();
    }

    //! Distance still to run in the displayed segment. A previewed segment uses
    //! its full length.
    function remainingM() as Float {
        return remainingInM(segment());
    }

    //! Average pace over the part of the current segment run so far, in seconds
    //! per km. Null until the distance run in the segment is positive.
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
    //! at its target pace, plus every later segment at theirs. Uses the segment
    //! being run, not the displayed one.
    private function planRemainingS() as Float {
        return remainingInM(_next) / M_PER_KM * _course.paceS(_next)
            + _course.planAfterS(_next);
    }

    //! The projected finish time in seconds, with every remaining segment run
    //! at its target pace.
    function targetFinishS() as Float {
        return _elapsedMs / MS_PER_S + planRemainingS();
    }

    //! The projected finish time in seconds, with every remaining segment run
    //! at the current performance ratio.
    function perfRatioFinishS() as Float {
        return _elapsedMs / MS_PER_S + _takenS / _allowedS * planRemainingS();
    }
}
