"""Plot the course with the split gates overlaid, and its elevation profile.

Reads the course track from the .gpx file and the waypoints from segments.json
(written by make_segments.py), and draws each gate as the line between the two
endpoints given there.

The map is plotted in km east/north of the start line. The elevation profile is plotted
against distance along the course, with a cubic spline through the elevations recorded
in the .gpx file alongside the straight line between each pair of waypoints, the slope
of which is the average grade of that segment - so the two can be compared by eye.
"""

import json

import numpy as np
import matplotlib.pyplot as plt

from make_segments import (
    OUT_DIR,
    SEGMENTS_FILE,
    GATE_LENGTH,
    GPX_FILE,
    km,
    percent,
    cumulative_distances,
    elevation_spline,
    offset,
    read_track,
)

COURSE_PLOT_FILE = OUT_DIR / "course_gates.png"
ELEVATION_PLOT_FILE = OUT_DIR / "course_elevation.png"

FIGSIZE = (11, 4.75)

# Labels are drawn on one of these, so that they can be read where they overlap
# the course or the elevation trace:
LABEL_BBOX = {"facecolor": "white", "edgecolor": "none", "alpha": 0.8, "pad": 1}

LABEL_FONTSIZE = 9
GRADE_FONTSIZE = 8

# Gap between a waypoint marker and the start of its name, in metres of elevation:
NAME_CLEARANCE = 10.0

# The line joining a label to the waypoint it names. shrinkB is the gap it leaves
# at the marker end, in points:
LABEL_ARROW = {
    "arrowstyle": "-",
    "color": "black",
    "linewidth": 0.5,
    "shrinkA": 2,
    "shrinkB": 8,
    "alpha": 0.5,
}


def plot_course():
    points = read_track(GPX_FILE)
    segments = json.loads(SEGMENTS_FILE.read_text('utf8'))

    # Everything in km relative to the start of the course:
    lat0, lon0, _ = points[0]

    def km_offset(lat, lon):
        east, north = offset(lat0, lon0, lat, lon)
        return east / km, north / km

    track = [km_offset(lat, lon) for lat, lon, _ in points]

    fig, ax = plt.subplots(figsize=FIGSIZE)
    ax.plot(*zip(*track), color="0.45", linewidth=1.5, zorder=1, label="Course")
    ax.plot(
        *track[0], marker="o", color="darkgreen", markersize=7, zorder=4, label="Start"
    )

    for i, (name, waypoint) in enumerate(segments.items()):
        east, north = km_offset(waypoint["lat"], waypoint["lon"])
        left = km_offset(waypoint["gate_left_lat"], waypoint["gate_left_lon"])
        right = km_offset(waypoint["gate_right_lat"], waypoint["gate_right_lon"])

        ax.plot(*zip(left, right), color="crimson", linewidth=2, zorder=3)
        ax.plot(east, north, marker="o", color="crimson", markersize=4, zorder=4)
        # Alternate the labels above and below the course so they don't collide. The
        # finish takes an above label regardless of the alternation, since the course
        # runs beneath it and a label below would overlap the track:
        above = i % 2 == 0 or i == len(segments) - 1
        ax.annotate(
            f"{name}\n{waypoint['distance'] / km} km",
            (east, north),
            textcoords="offset points",
            xytext=(0, 35 if above else -55),
            ha="center",
            fontsize=LABEL_FONTSIZE,
            color="black",
            arrowprops=LABEL_ARROW,
        )

    # Label only the first gate, so the legend doesn't repeat it:
    ax.plot([], [], color="crimson", linewidth=2, label=f"{GATE_LENGTH:.0f} m gates")

    ax.set_aspect("equal")
    ax.margins(0.10)
    ax.set_xlabel("East of start (km)")
    ax.set_ylabel("North of start (km)")
    ax.grid(True, color="k", linestyle=":", alpha=0.5)
    ax.set_axisbelow(True)
    for spine in "top", "right":
        ax.spines[spine].set_visible(False)
    ax.legend(loc="lower left", frameon=False)
    fig.tight_layout()
    fig.savefig(COURSE_PLOT_FILE)
    print(f"Wrote {COURSE_PLOT_FILE}")


def plot_elevation():
    points = read_track(GPX_FILE)
    segments = json.loads(SEGMENTS_FILE.read_text('utf8'))

    distances = cumulative_distances(points)

    # The cubic spline through the track point elevations, evaluated every metre:
    spline = elevation_spline(points, distances)
    distance = np.linspace(0, distances[-1], round(distances[-1]) + 1)
    elevation = spline(distance)

    # The straight lines run from waypoint to waypoint, starting at the start of
    # the course. Their slope is the average grade of the segment they span:
    segment_distance = np.array([0.0] + [w["distance"] for w in segments.values()])
    segment_ele = np.array([elevation[0]] + [w["elevation"] for w in segments.values()])
    segment_grade = np.array([w["grade"] for w in segments.values()])

    fig, ax = plt.subplots(figsize=FIGSIZE)
    ax.plot(
        distance / km,
        elevation,
        color="0.45",
        linewidth=1.5,
        zorder=2,
        label="Elevation (gpx)",
    )
    ax.plot(
        segment_distance / km,
        segment_ele,
        color="crimson",
        linewidth=1.5,
        zorder=3,
        label="Segment avg. grade",
        alpha=0.5,
    )
    ax.plot(
        segment_distance[1:] / km,
        segment_ele[1:],
        marker="o",
        linestyle="none",
        color="crimson",
        markersize=5,
        zorder=4,
        label="Waypoints",
    )
    ax.plot(
        0,
        elevation[0],
        marker="o",
        color="darkgreen",
        markersize=7,
        zorder=5,
        label="Start",
    )

    low, high = elevation.min(), elevation.max()

    for name, d, ele in zip(segments, segment_distance[1:], segment_ele[1:]):
        # The names are written vertically so that they fit above the shorter
        # segments. They go below the course where it is high and above it where it
        # is low, so that each is in the empty space beside the trace:
        below = ele > (low + high) / 2
        ax.annotate(
            name,
            (d / km, ele),
            textcoords="data",
            xytext=(d / km, ele - NAME_CLEARANCE if below else ele + NAME_CLEARANCE),
            rotation=90,
            # The names read bottom to top, so each starts at the waypoint end of
            # its arrow and runs away from the course:
            ha="center",
            va="top" if below else "bottom",
            fontsize=LABEL_FONTSIZE,
            color="black",
            bbox=LABEL_BBOX,
            arrowprops=LABEL_ARROW | {"shrinkB": 4},
        )

    label_grades(ax, segment_distance, segment_ele, segment_grade)

    ax.margins(x=0.01, y=0.04)
    ax.set_xlabel("Distance along course (km)")
    ax.set_ylabel("Elevation (m)")
    ax.grid(True, color="k", linestyle=":", alpha=0.5)
    ax.set_axisbelow(True)
    for spine in "top", "right":
        ax.spines[spine].set_visible(False)
    ax.legend(loc="lower right", frameon=False)
    fig.tight_layout()
    fig.savefig(ELEVATION_PLOT_FILE)
    print(f"Wrote {ELEVATION_PLOT_FILE}")


def label_grades(ax, segment_distance, segment_ele, segment_grade):
    """Label each straight line between waypoints with its grade.

    The label sits at the midpoint of its line, centred on it and written along
    it, so that its baseline is the grade it gives - its background masks the
    stretch of line behind the text. The rotation is given as the slope in data
    units and transformed to the page by matplotlib, which means it is worked out
    afresh at each draw and so survives the figure being resized.
    """
    for x0, x1, y0, y1, g in zip(
        segment_distance,
        segment_distance[1:],
        segment_ele,
        segment_ele[1:],
        segment_grade,
    ):
        if round(g / percent) == 0:
            # Don't label flat segments
            continue
        ax.text(
            (x0 + x1) / 2 / km,
            (y0 + y1) / 2,
            f"{g / percent:+.1f}%".replace('-', '−'),
            rotation=np.arctan2(y1 - y0, (x1 - x0) / km) * 180 / np.pi,
            transform_rotates_text=True,
            rotation_mode="anchor",
            ha="center",
            va="center",
            fontsize=GRADE_FONTSIZE,
            color="crimson",
            bbox=LABEL_BBOX,
        )


def plot():
    plot_course()
    plot_elevation()
    plt.show()


if __name__ == "__main__":
    OUT_DIR.mkdir(exist_ok=True)
    plot()
