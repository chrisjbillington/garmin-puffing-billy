"""Process user config config.json to locate the race-split waypoints on the course, and
calculate per-segment pacing.

Reads the segment endpoint, defined by their distance into the course, from config.json,
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

Target pacing is calculated based on a flat pace and uphill/downhill pace penalty/bonus
factor read from config.json and saved in segments.json

"""
from pathlib import Path
import json
import math
import itertools
import xml.etree.ElementTree as ET

import numpy as np


km = 1000
percent = 0.01

THIS_DIR = Path(__file__).absolute().parent
OUT_DIR = THIS_DIR / 'out'
CONFIG_FILE = THIS_DIR / "config.json"
GPX_FILE = THIS_DIR / "official-course-2026.gpx"
SEGMENTS_FILE = OUT_DIR / "segments.json"

R_EARTH = 6371008.8  # mean Earth radius, metres

GATE_LENGTH = 200.0  # metres

# Length of course, either side of a waypoint, that the heading is fitted to:
HEADING_WINDOW = 50.0  # metres

# Spacing the track is re-interpolated to before fitting:
RESAMPLE_SPACING = 5.0  # metres


def ms2s(pace_string):
    # convert a string duration in minutes and seconds like "4:43" to seconds
    m, s = [float(x) for x in pace_string.split(':')]
    return 60 * m + s


def s2ms(pace):
    # Format a duration in seconds in minutes and seconds as a string like "4:43"
    m, s = divmod(pace, 60)
    return f"{m:.0f}:{s:02.0f}"


def grade2pace(grade, flat_pace, uphill_penalty, downhill_bonus):
    # Given flat pace in seconds per km and a fractional uphill/downhill penalty/bonus
    # (percent slowdown/speedup per percent grade), return grade-adjusted pace
    if grade > 0:
        k = uphill_penalty
    else:
        k = downhill_bonus
    return flat_pace * (1 + k * grade)


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


def position_at(points, distances, target):
    """Lat, lon and elevation the given distance in metres into the course.

    A target beyond the end of the track gives the final track point.
    """
    return tuple(
        np.interp(target, distances, [point[i] for point in points])
        for i in range(3)
    )


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


def make_segments():
    config = json.loads(CONFIG_FILE.read_text('utf8'))
    waypoints = config['waypoints']
    flat_pace = ms2s(config["pacing"]["flat_pace"])
    uphill_penalty = config["pacing"]["uphill_penalty"]
    downhill_bonus = config["pacing"]["downhill_bonus"]

    points = read_track(GPX_FILE)
    distances = cumulative_distances(points)
    track_length = distances[-1]
    s, lats, lons = resample(points, distances)

    print(f"Track: {len(points)} points, {track_length / km:.3f} km")
    # print(f"Gates: {GATE_LENGTH:.0f} m long, heading fitted over +/-{HEADING_WINDOW:.0f} m")
    print(f"Splits: {len(waypoints)} segments, {list(waypoints.values())[-1]:.3f} km")
    print()

    segments = {}
    distance_prev = 0
    _, _, ele_prev = position_at(points, distances, 0)
    for name, distance_km in waypoints.items():
        distance = distance_km * km
        length = distance - distance_prev
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
        pace = grade2pace(grade, flat_pace, uphill_penalty, downhill_bonus)
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
            f"{row['grade'] / percent:+.1f}%  {s2ms(row['pace'])}"
        )

    print()
    total_time = sum(seg['pace'] * (seg['length'] / km) for seg in segments.values())
    avg_pace = total_time / (track_length / km)

    print(f"       Total time: {s2ms(total_time)}")
    print(f"     Average pace: {s2ms(avg_pace)}/km")
    print(f"Difficulty factor: {avg_pace/flat_pace:.3f}")

    print()
    SEGMENTS_FILE.write_text(json.dumps(segments, indent=4), 'utf8')
    print(f"Wrote {SEGMENTS_FILE}")


if __name__ == "__main__":
    OUT_DIR.mkdir(exist_ok=True)
    make_segments()
