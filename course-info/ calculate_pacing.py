# script to extrapolate from flat 13.5km pace to course, per segment, based on grade.
# reads processed-waypoints.json to get length and grade of each segment

from pathlib import Path
import json

THIS_DIR = Path(__file__).absolute().parent
PROCESSED_WAYPOINTS_FILE = THIS_DIR / "processed-waypoints.json"
TARGET_PACES_FILE = THIS_DIR / "target-paces.json"

km = 1000
percent = 0.01

def ms2s(pace_string):
    # convert a string duration in minutes and seconds like "4:43" to seconds
    m, s = [float(x) for x in pace_string.split(':')]
    return 60 * m + s

def s2ms(pace):
    # Format a duration in seconds in minutes and seconds as a string like "4:43"
    m, s = divmod(pace, 60)
    return f"{m:.0f}:{s:02.0f}"


def grade2pace(g, flat_pace):
    if g > 0:
        k = UPHILL_PENALTY
    else:
        k = DOWNHILL_BONUS
    return flat_pace * (1 + k * g)


# Configure your per-unit-grade penalty and bonus:
UPHILL_PENALTY = 5 # 5 percent slower per percentage point of grade
DOWNHILL_BONUS = 1.75 # 1.15 percent speed bonus per percentage point of grade

# Set your flat 13.5km pace here:
FLAT_PACE = "4:45"

flat_pace_sec = ms2s(FLAT_PACE)

segments = json.loads(PROCESSED_WAYPOINTS_FILE.read_text('utf8'))

out = {}
print()
print(f"Flat pace: {FLAT_PACE}/km")
print()
print("             Segment      dist:  (length @ grade):    pace")
print("----------------------------------------------------------")
cumulative_time = 0
for name, segment in segments.items():
    d = segment['distance']
    l = segment['length']
    g = segment['grade']
    pace = grade2pace(g, flat_pace_sec)
    cumulative_time += pace * (l / km)
    out[name] = pace
    print(f"{name:>20} {d/km:6.3f} km: ({l / km:.2f} km @ {g / percent:+.1f}%): {s2ms(pace)}/km")

TARGET_PACES_FILE.write_text(json.dumps(out, indent=4), 'utf8')

avg_pace = cumulative_time / (d / km)

print()
print(f"   Total distance: {d/km:.3f}km")
print(f"       Total time: {s2ms(cumulative_time)}")
print(f"     Average pace: {s2ms(avg_pace)}/km")
print(f"Difficulty factor: {avg_pace/flat_pace_sec:.3f}")
