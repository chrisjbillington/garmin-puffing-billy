m = 60
s = 1

# Aug 11th actual 5k pace: 4:41
# Aug 12th Garmin 5k pace estimate: 4:38

FIVE_K_PACE = 4 * m + 28 * s

# Aug 12th Garmin estimate of train race pace: 5:00
# Aug 12th Garmin forecast of train race pace: 4:51

# FLAT_PACE = FIVE_K_PACE * (13.65 / 5) ** (0.06)

m = 60
s = 1

FLAT_PACE = 4 * m + 45 * s  # 4:45/ km

def grad2pace(g):
    if g > 0:
        k = 0.05
    else:
        k = 0.0175
    return FLAT_PACE * (1 + k * g)

def tfmt(s):
    # Format a time in seconds as MM:SS
    m, s = divmod(s, 60)
    return f"{m:.0f}:{s:02.0f}"

# End waypoint name: (length, grade)
segments = {
    "Trestle Bridge": (1.15, -3.5),
    "Selby": (1.35, +4.6),
    "Aura Rd crossing": (0.75, 0.0),
    "Old Menzies Ck Rd": (1.75, -2.4),
    "Menzies Crossing": (1.60, +6.0),
    "Menzies Rd Crest": (0.75, +2.1),
    "Clematis Crossing": (0.50, -9.2),
    "Clematis Pub": (0.90, +0.4),
    "Emerald Crossing": (1.50, +3.0),
    "Lakeside": (3.40, -2.2),
}

print()
print(f"Flat pace: {tfmt(FLAT_PACE)}/km")
print()
print("Segment target paces")
print("-----------------------------")
cumulative_dist = 0
cumulative_time = 0
for segment, (d, g) in segments.items():
    cumulative_dist += d
    pace = grad2pace(g)
    cumulative_time += d * pace
    print(f"{segment:>20} ({d:.2f}km @ {g:+.1f}%): {tfmt(pace)}/km")

avg_pace = cumulative_time/cumulative_dist

print()
print(f"   Total distance: {cumulative_dist}km")
print(f"       Total time: {tfmt(cumulative_time)}")
print(f"     Average pace: {tfmt(avg_pace)}/km")
print(f"Difficulty factor: {avg_pace/FLAT_PACE:.3f}")
