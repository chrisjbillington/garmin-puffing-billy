"""Process user config config.toml to locate the race-split waypoints on the course, and
calculate per-segment pacing.

Reads the segment endpoint, defined by their distance into the course, from config.toml,
and the course track from the .gpx file, and works out where along the track each
segment boundary falls. Writes out/segments.json with each waypoint's name, distance
into the course, coordinates, the heading of the course at that point, and the two ends
of the gate there: a line GATE_LENGTH metres long, centred on the course and normal to
the heading, which the runner passes through on entering the next segment. The ends are
given left first, then right, as seen by a runner running the course.

The heading is the tangent of a quadratic fit to the track within HEADING_WINDOW
metres of the waypoint. Fitting a curve over a window rather than taking the
bearing between the two adjacent track points keeps the heading from swinging
wildly where the course has a sharp kink in it.

Target pacing is either given per segment in config.toml, or calculated from a flat
pace and a split delta read from config.toml, with each segment's pace grade-adjusted
using Strava's grade-adjusted pace (GAP) curve. Either way it is saved in
segments.json.

Also writes out/resource.json, the subset of that which goes on the watch, in the shape
the data field wants it. See make_resource().

"""
from pathlib import Path
import json
import math
import itertools
import tomllib
import xml.etree.ElementTree as ET

import numpy as np
from scipy.interpolate import CubicSpline


km = 1000
percent = 0.01

THIS_DIR = Path(__file__).absolute().parent
OUT_DIR = THIS_DIR / 'out'
CONFIG_FILE = THIS_DIR / "config.toml"
GPX_FILE = THIS_DIR / "official-course-2026.gpx"
SEGMENTS_FILE = OUT_DIR / "segments.json"
RESOURCE_FILE = OUT_DIR / "resource.json"

R_EARTH = 6371008.8  # mean Earth radius, metres

# Garmin's native coordinate unit, as used in .fit files: a signed 32-bit integer
# with 2**31 semicircles to 180 degrees, i.e. a resolution of about 9 mm.
SEMICIRCLES_PER_DEGREE = 2**31 / 180

GATE_LENGTH = 200.0  # metres

# Length of course, either side of a waypoint, that the heading is fitted to:
HEADING_WINDOW = 50.0  # metres

# Spacing the track is re-interpolated to before fitting:
RESAMPLE_SPACING = 5.0  # metres


def parse_pace(pace_string):
    # Convert a string duration in minutes and seconds like "4:43" to seconds
    m, s = [float(x) for x in pace_string.split(':')]
    return 60 * m + s


def format_pace(pace):
    # Format a duration in seconds in minutes and seconds as a string like "4:43"
    m, s = divmod(pace, 60)
    return f"{m:.0f}:{s:02.0f}"


# Grade-adjusted pace curve used by Strava, reverse-engineered by Aaron Schroeder:
# https://aaron-schroeder.github.io/reverse-engineering/grade-adjusted-pace.html
# Grades in percent, factors as multiples of flat pace.
GAP_GRADES = [-45, -30, -25, -20, -15, -10, -8, -6, -4, -2, 0,
              2, 4, 6, 8, 10, 15, 20, 25, 30, 45]
GAP_FACTORS = [2.096, 1.495, 1.273, 1.081, 0.941, 0.876, 0.876, 0.891, 0.918, 0.960,
               1.0, 1.055, 1.135, 1.228, 1.337, 1.459, 1.846, 2.297, 2.727, 3.158,
               4.286]


def grade2pace(grade, flat_pace):
    # Given flat pace in seconds per km and a fractional grade, return grade-adjusted
    # pace from Strava's GAP curve
    grade_pct = np.clip(grade / percent, GAP_GRADES[0], GAP_GRADES[-1])
    return flat_pace * float(np.interp(grade_pct, GAP_GRADES, GAP_FACTORS))


def split2pace(distance, course_length, flat_pace, split_delta):
    """Flat pace the given distance in metres into a course of the given length.

    Pace ramps linearly with distance from flat_pace * (1 - split_delta) at the start to
    flat_pace * (1 + split_delta) at the finish, so that it averages flat_pace over the
    course. split_delta is the difference between the times for the second and first
    halves of the course, as a fraction of the mean half time:

        split_delta = (t2 - t1) / (T / 2)

    with the halves taken by distance and T the total time. So split_delta = -0.02 is a
    2% negative split in the usual sense: t1 / t2 = 1.0202, the first half run 2% slower
    than the second, and swapping the halves flips the sign and nothing else.

    Since pace is linear in distance, a segment's mean pace is its pace at its midpoint,
    so pass a segment's midpoint to pace that segment.
    """
    return flat_pace * (1 + 2 * split_delta * (distance / course_length - 0.5))


def segment_pace(pacing, index, midpoint, course_length, grade):
    """Target pace in seconds per km for one segment, from config.toml's [pacing].

    That is either the segment's own "m:ss" pace from `paces`, used as it stands, or
    the parameters to calculate a pace from: the flat pace the split delta calls for
    at `midpoint`, the middle of the segment in metres into the course, adjusted for
    the segment's average `grade`.
    """
    if "paces" in pacing:
        return parse_pace(pacing["paces"][index])
    flat_pace = split2pace(
        midpoint,
        course_length,
        parse_pace(pacing["flat_pace"]),
        pacing["split_delta"],
    )
    return grade2pace(grade, flat_pace)


def read_track(gpx_file):
    """Return the list of (lat, lon, ele) track points in the gpx file."""
    root = ET.parse(gpx_file).getroot()
    # Strip the namespace so we don't have to care which gpx version it is:
    ns = root.tag.split("}")[0] + "}" if "}" in root.tag else ""
    points = []
    for trkpt in root.iter(f"{ns}trkpt"):
        ele = trkpt.find(f"{ns}ele")
        points.append(
            (
                float(trkpt.get("lat")),
                float(trkpt.get("lon")),
                float(ele.text) if ele is not None else float("nan"),
            )
        )
    return points


def offset(lat0, lon0, lat1, lon1):
    """East, north offset in metres from one lat/lon to another.

    Equirectangular approximation - good to well under a metre over the
    distances we use it for.
    """
    mean_lat = np.radians((lat0 + lat1) / 2)
    east = np.radians(lon1 - lon0) * R_EARTH * np.cos(mean_lat)
    north = np.radians(lat1 - lat0) * R_EARTH
    return east, north


def destination(lat, lon, east, north):
    """The lat/lon the given east and north offset in metres from a lat/lon.

    The inverse of offset().
    """
    dlat = math.degrees(north / R_EARTH)
    mean_lat = math.radians(lat + dlat / 2)
    dlon = math.degrees(east / (R_EARTH * math.cos(mean_lat)))
    return lat + dlat, lon + dlon


def gate_ends(lat, lon, heading):
    """The left and right ends of the gate at a waypoint, as (lat, lon).

    The gate is centred on the waypoint, normal to the given heading, and
    GATE_LENGTH long. Left and right are as seen by a runner running the course,
    i.e. the ends lie 90 degrees anticlockwise and clockwise of the heading.
    """
    ends = []
    for bearing in heading - 90, heading + 90:
        east = math.sin(math.radians(bearing)) * GATE_LENGTH / 2
        north = math.cos(math.radians(bearing)) * GATE_LENGTH / 2
        ends.append(destination(lat, lon, east, north))
    return ends


def cumulative_distances(points):
    """Distance in metres along the track to each track point."""
    distances = [0.0]
    for (lat0, lon0, _), (lat1, lon1, _) in itertools.pairwise(points):
        east, north = offset(lat0, lon0, lat1, lon1)
        distances.append(distances[-1] + math.hypot(east, north))
    return distances


def resample(points, distances, spacing=RESAMPLE_SPACING):
    """The track re-interpolated at even spacing, as (distance, lat, lon).

    The track points themselves are spaced anywhere from 1 to 80 metres apart;
    resampling means the heading fit weights each metre of course equally
    instead of favouring the densely recorded parts of it.
    """
    s = np.linspace(0, distances[-1], int(distances[-1] / spacing) + 1)
    lats = np.interp(s, distances, [lat for lat, _, _ in points])
    lons = np.interp(s, distances, [lon for _, lon, _ in points])
    return s, lats, lons


def elevation_spline(points, distances):
    """Cubic spline of elevation as a function of distance along the track."""
    return CubicSpline(distances, [ele for _, _, ele in points])


def position_at(points, distances, target):
    """Lat, lon and elevation the given distance in metres into the course.

    Lat and lon are interpolated linearly between track points, and elevation with a
    cubic spline. A target beyond the end of the track gives the final track point.
    """
    lat, lon = (
        np.interp(target, distances, [point[i] for point in points]) for i in range(2)
    )
    ele = elevation_spline(points, distances)(np.clip(target, 0, distances[-1]))
    return lat, lon, float(ele)


def heading_at(s, lats, lons, target):
    """Compass bearing of the course the given distance into it.

    Fits east and north position as quadratics in along-track distance, over
    the stretch of course within HEADING_WINDOW metres of the target, and takes
    the tangent to the fit at the target. Following the local curvature this way
    means a bend near the waypoint doesn't drag the heading towards the chord
    across it, the way a straight-line fit would.
    """
    lat0 = np.interp(target, s, lats)
    lon0 = np.interp(target, s, lons)

    window = np.abs(s - target) <= HEADING_WINDOW
    ds = s[window] - target
    east, north = offset(lat0, lon0, lats[window], lons[window])

    # Tricube weights, so the course nearest the waypoint dominates the fit.
    # np.polyfit weights multiply the residuals, so pass the square root:
    weights = np.sqrt((1 - np.abs(ds / HEADING_WINDOW) ** 3) ** 3)

    # Index 1 of a quadratic fit is the linear coefficient, i.e. the derivative
    # with respect to along-track distance at the waypoint:
    d_east = np.polyfit(ds, east, 2, w=weights)[1]
    d_north = np.polyfit(ds, north, 2, w=weights)[1]

    return 180 / np.pi * math.atan2(d_east, d_north)


def load_config():
    """The user config, as read from config.toml."""
    return tomllib.loads(CONFIG_FILE.read_text('utf8'))


def make_segments(config):
    """Locate each waypoint on the track, pace its segment, and write segments.json.

    Returns the segments, keyed by waypoint name and in course order.
    """
    waypoints = config['waypoints']
    pacing = config['pacing']
    course_length = list(waypoints.values())[-1] * km

    if "paces" in pacing and len(pacing["paces"]) != len(waypoints):
        raise ValueError(
            f"config.toml gives {len(pacing['paces'])} paces "
            f"for {len(waypoints)} segments"
        )

    points = read_track(GPX_FILE)
    distances = cumulative_distances(points)
    track_length = distances[-1]
    s, lats, lons = resample(points, distances)

    print(f"Track: {len(points)} points, {track_length / km:.3f} km")
    print(f"Splits: {len(waypoints)} segments, {list(waypoints.values())[-1]:.3f} km")
    print()

    segments = {}
    distance_prev = 0
    _, _, ele_prev = position_at(points, distances, 0)
    for i, (name, distance_km) in enumerate(waypoints.items()):
        distance = distance_km * km
        length = distance - distance_prev
        if length <= 0:
            raise ValueError(
                f"config.toml waypoint distances must be increasing: {name} at "
                f"{distance / km:.3f} km is not past {distance_prev / km:.3f} km"
            )
        distance_prev = distance
        if round(distance) > round(track_length):
            print(
                f"Note: {name} at {distance / km:.3f} km is "
                f"{distance - track_length:.0f} m past the end of the track - "
                f"using the finish line"
            )
        target = min(distance, track_length)
        lat, lon, ele = position_at(points, distances, target)
        heading = heading_at(s, lats, lons, target)
        (left_lat, left_lon), (right_lat, right_lon) = gate_ends(lat, lon, heading)
        grade = (ele - ele_prev) / length
        ele_prev = ele
        pace = segment_pace(pacing, i, distance - length / 2, course_length, grade)
        segments[name] = {
            "distance": distance,
            "length": length,
            "grade": grade,
            "pace": pace,
            "lat": lat,
            "lon": lon,
            "elevation": ele,
            "heading": heading,
            "gate_left_lat": left_lat,
            "gate_left_lon": left_lon,
            "gate_right_lat": right_lat,
            "gate_right_lon": right_lon,
        }

    print(
        f"{'segment endpoint':>20}  {'dist':>6}  {'len':>6}  {'grade'}  {'pace'}"
    )
    print("-" * 49)
    for name, row in segments.items():
        print(
            f"{name:>20}  {row['distance'] / km:>6.3f}  {row['length'] / km:>6.3f}  "
            f"{row['grade'] / percent:+.1f}%  {format_pace(row['pace'])}"
        )

    print()
    total_time = sum(seg['pace'] * (seg['length'] / km) for seg in segments.values())
    avg_pace = total_time / (course_length / km)

    print(f"       Total time: {format_pace(total_time)}")
    print(f"     Average pace: {format_pace(avg_pace)}/km")
    if "paces" not in pacing:
        flat_pace = parse_pace(pacing["flat_pace"])
        print(f"Difficulty factor: {avg_pace/flat_pace:.3f}")

    print()
    # allow_nan=False so that a gpx file with missing elevations fails here,
    # rather than NaN grades and paces being written out as invalid JSON.
    SEGMENTS_FILE.write_text(json.dumps(segments, indent=4, allow_nan=False), 'utf8')
    print(f"Wrote {SEGMENTS_FILE}")
    return segments


def semicircles(degrees):
    """Convert a coordinate in degrees to an integer number of semicircles."""
    return round(degrees * SEMICIRCLES_PER_DEGREE)


def make_resource(segments, tracking):
    """Write out/resource.json, the part of the segments that goes on the watch.

    The data field only has access at runtime to the segment names, their lengths, their
    target paces, the gates, and the overdistance and performance ratio averaging scale
    config parameters. The rest of segments.json is for convenience plotting the results
    with plot_segments.py, and is not needed on the watch.

    Gate coordinates are stored in units of integer semicircles rather than degrees, as
    the latter are stored as 32-bit floats which can have quantisation error > 1 m."""
    resource = {
        "names": list(segments),
        "lengths": [round(seg["length"]) for seg in segments.values()],
        "paces": [round(seg["pace"], 2) for seg in segments.values()],
        # Four values per gate - left end then right end, as seen by a runner
        # running the course - so segment i's gate is gates[4 * i : 4 * i + 4],
        # as lat, lon, lat, lon.
        "gates": [
            semicircles(seg[end + coord])
            for seg in segments.values()
            for end in ("gate_left_", "gate_right_")
            for coord in ("lat", "lon")
        ],
        # Whole metres, for the same reason the lengths are.
        "overdistance": round(tracking["overdistance"]),
        "perf_ratio_scale": round(tracking["perf_ratio_scale"]),
    }

    RESOURCE_FILE.write_text(json.dumps(resource, indent=4, allow_nan=False), 'utf8')
    print(f"Wrote {RESOURCE_FILE}")


if __name__ == "__main__":
    OUT_DIR.mkdir(exist_ok=True)
    config = load_config()
    make_resource(make_segments(config), config["tracking"])
