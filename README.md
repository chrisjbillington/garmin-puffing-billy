A data field for the Puffing Billy Great Train Race: a 13.6 km run on a fixed course,
split by named waypoints into segments, each with its own target pace worked out from
its grade (based on compile-time configuration).

Does not interact in any way with other activity configuration - segments and pace
targets as displayed by this data field are totally internally managed and have nothing
to do with activity laps or intervals or target paces.

The data field advances the display to the next segment based on the runner's GPS track
crossing a "gate" at each waypoint - a 200 m long line segment crossing the course,
defined by the GPS coordinates of its endpoints. In addition, if the GPS distance
accumulated in a segment is 200m longer than the expected length of the segment, the
next segment is triggered even if no gate is passed through. This allows for some
recovery if for some reason you run around a gate or have a very long GPS dropout.

Only tested on a Venu 4 41mm, and pace configuration is currently at compile-time, so
you're welcome to use this (or have your favourite chatbot adapt it to your use) but it
is substantially vibe-coded and not intended to be general.

the field
---------

![full screen](readme-images/screenshot.png)

What the field shows depends on how much of the display the activity's layout gives it.

It has a full-screen version, and two half-screen versions (top and bottom half). You
can include the full-screen version on one data screen and both half-screen versions on
another, to see everything.

### Given the whole face

Top to bottom:

- **Heart rate**, in bpm, with `---` until the watch has a reading.
- **target** - the current segment's target pace, in minutes per km.
- **segment** - average pace over the part of the current segment run so far
- **pace** - instantaneous pace, from the watch's current speed.
- **The bar** - the whole course, start at the left and finish at the right, one block
  per segment sized by its length and coloured by its target pace against the course
  average: green where the plan is fast, red where it's slow, amber in between. Course
  still to run is dimmed and course already run brighter, with a marker at the current
  position.
- **Next waypoint name** the waypoint being run towards, i.e. the end of the
  current segment.
- **Remaining segment distance** - how far is left to that waypoint, in km. It counts
  down, and can go negative if GPS distance (due to error or otherwise) in the segment
  grows larger than the expected segment length before reaching the next waypoint. If it
  reaches -200 m before the next waypoint is reached, the field gives up waiting for the
  gate and moves on to the next segment anyway.

Before the activity has been started, the waypoint name, progress bar, remaining
distance, and target pace will cycle through the different segments showing the entire
planned course. This can be used to verify paces and distances were configured correctly
before actually starting the race.

### Given half the face

One projected finish time, with how it stands against the planned finish - green and
negative for time in hand, red and positive for time lost. Which projection you get
depends on which half of the display the field has been given:

- **at target pace** (top half) - the finish time if everything still to come is run at
  its target pace.
- **at current perf. ratio** (bottom half) - the finish time if the rest of the race is
  run at the same fraction of target pace as an average over the last 500 m

So put the field on both halves of one data screen to see both, as in the screenshot.


Segment and pacing configuration
--------------------------------

The watch doesn't store the whole course, only pairs of GPS points straddling each
waypoint, which serve as "gates" - if you run across the line joining them, this
triggers the data field to move to the next segment.

It also stores a target pace for each segment, which you can specify manually or have
them computed from an equivalent flat-terrain target pace, grade penalty/bonus, and
desired split delta (i.e. positive or negative splits).

`segments/config.json` is the only file you edit to change the course or the target
pacing. Its default contents look like this:

```json
{
    "waypoints": {
        "Trestle Bridge Bend": 1.150,
        "Selby": 2.500,
        "Aura Rd Crossing": 3.250,
        "Old Menzies Ck Rd": 5.025,
        "Menzies Ck Crossing": 6.590,
        "Menzies Rd Crest": 7.350,
        "Clematis Crossing": 7.850,
        "Clematis Pub": 8.750,
        "Emerald Crossing": 10.260,
        "Lakeside": 13.613
    },
    "pacing": {
        "flat_pace": "4:45",
        "split_delta": -0.01,
        "uphill_penalty": 5,
        "downhill_bonus": 1.75
    }
}
```

It holds:

- `"waypoints"`: the segment endpoints, in order, as a list of names mapped to the
  distance in km into the course, at which the waypoint occurs. The last one is the
  finish.

- `"pacing"`: either a list of per-segment paces, or parameters from which those paces
  will be generated programmatically. If a list of per-segment paces, it should be the
  same length as the list of waypoints, and contain paces as strings in minutes and
  seconds per kilometer, for the segment ending at the corresponding waypoint, e.g.:

  ```json
      "pacing": [
          "4:27",
          "5:50",
          "4:46",
          "4:33",
          "6:12",
          "5:16",
          "4:03",
          "4:44",
          "5:30",
          "4:34"
      ]
    ```

  Otherwise, `"pacing"` should contain the following parameters as in the default
  example above:

  ```json
      "pacing": {
        "flat_pace": "4:45",
        "split_delta": -0.01,
        "uphill_penalty": 5,
        "downhill_bonus": 1.75
    }
    ```

  - `"flat_pace"` the target average pace at which you would run the course if it were
    flat, as a string in minutes and seconds per km, eg. `"4:45"`

  - `"split_delta"`: the target fractional difference in pace of the second half of the
    course with respect to the first, describing a linear ramp in pace at which you
    would run the course if it were flat. e.g. `-0.01` means you would run the second
    half of a flat course 1% faster than the first (what is typically meant by "1%
    negative splits").

  - `"uphill_penalty"` and `"downhill_bonus"`: the fractional slowdown and speedup, from
    flat pace, per unit of average grade (equivalently, percent change in pace per
    percent grade) to apply to each segment.

  Note that this doesn't involve specifying your actual target race time - this goes the
  other way around and calculates your target race time. You can see the result by
  running `python segments/make_segments.py`, which will print a table of paces and the
  resulting total time.

The official course `.gpx` for 2026 is in this repo as
`segments/official-course-2026.gpx`, and is used to extract segment grades. The default
segmentation results in the below segments:

![course elevation](readme-images/course_elevation.png)

![course gates](readme-images/course_gates.png)

If you change the waypoints, you will want to verify that the waypoint gates (red line
segments in the image above) don't intersect the course at any point earlier than the
waypoint itself, otherwise they'll be triggered early.

Going through the pipeline, which `make` runs for you whenever it is out of date:

`make_segments.py` locates each waypoint along the `.gpx` track, fits the course
heading there, and builds the 200 m "gate" normal to that heading which the
runner passes through - see the waypoint crossing section below. It also
computes each segment's average grade from the track elevation, and, unless the
paces are given per segment, grade-adjusts the flat pace the split delta calls
for at that point in the course to get the segment's target pace. All of that
lands in `segments.json`, along with the working (heading, elevation,
coordinates), and it prints a per-segment pacing table plus the predicted total
time.

`resource.json` is the part of that the data field actually needs - names,
lengths, paces and gates - as parallel arrays, with coordinates in integer
semicircles. It's trimmed and reshaped deliberately, to keep both heap and
floating point precision under control on the watch; `make_resource()`'s
docstring explains why.

`resources/jsonData/segments.xml` points the Connect IQ resource compiler at
`resource.json`, which is what makes it `$.Rez.JsonData.Segments` in the app.

`segments/out/` is gitignored, so it isn't in a fresh clone. Nothing needs doing
about that: the `.prg` depends on `resource.json`, which in turn depends on
`config.json`, the `.gpx` and `make_segments.py`, so a build regenerates it
whenever it is missing or out of date - an edit to `config.json` can't be left
out of the `.prg`.

`segments/plot_segments.py` has no make target; run it by hand after
`make segments` to draw the course with the gates overlaid and the elevation
profile, into `segments/out/*.png`:

```bash
python segments/plot_segments.py
```

source
------

One class or module per job, all under `source/`:

- `PuffingBillyApp.mc` - the app shell, which returns the field as its only view.
- `PuffingBillyField.mc` - the data field itself: the three callbacks, the colours and
  all of the drawing.
- `Course.mc` - the segments, their target paces and their gates, read from the
  compiled-in JSON resource, plus the line-crossing test against a gate.
- `Race.mc` - the race in progress: which segment is being run, how far and how long
  into it, how hard it is being run against the plan, and the two projected finishes.
- `Layout.mc` - the vertical rhythm, solved once per `onLayout()` and read on every
  draw.
- `Face.mc` - the round display, where the field has been placed on it, and the circle
  left once the bezel clearance is taken off.
- `Roboto.mc` - the glyph metrics the Graphics API doesn't report.
- `Fmt.mc` - paces, durations and standings as strings.

setup bits and bobs
-------------------

You'll need to install Garmin's Connect IQ SDK manager, make a developer account, and
use the SDK manager to install the SDK for your device.

Make developer key:

```bash
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
```

Get exact device ID for device from device folder name:

```bash
$ ls ~/.Garmin/ConnectIQ/Devices/
venu441mm
```

Memory and resolution limits etc are in
`~/.Garmin/ConnectIQ/Devices/venu441mm/compiler.json`

patchelf to force simulator to use newer libs:
```bash
cd ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2/bin/
patchelf --replace-needed libwebkit2gtk-4.0.so.37 libwebkit2gtk-4.1.so.0 simulator
patchelf --replace-needed libjavascriptcoregtk-4.0.so.18 libjavascriptcoregtk-4.1.so.0 simulator
patchelf --replace-needed libsoup-2.4.so.1 libsoup-3.0.so.0 simulator
```

build commands
--------------

Build, writing `bin/PuffingBilly-venu441mm.prg`:

```bash
make
```

Regenerate the course data in `segments/out/` from `segments/config.json` and the
`.gpx` track, without building. A build does this for you when it needs to, so
you only need it on its own for the pacing table it prints, or before
`plot_segments.py`:

```bash
make segments
```

Run the simulator. Blocks, so give it its own terminal:

```bash
make sim
```

Build and load into the already-running simulator. Errors out if the simulator
isn't up:

```bash
make run
```

Sideload to the watch. Plug it in over USB and let gvfs mount it (MTP) first:

```bash
make deploy
```

Build a signed `.iq` bundle for the store, covering every product in the
manifest rather than just one:

```bash
make package
```

Delete `bin/`:

```bash
make clean
```

`DEVICE`, `KEY`, `TYPECHECK` (monkeyc `-l`, 0-3) and `SDK_ROOT` can be
overridden per invocation:

```bash
make run DEVICE=venu445mm
make build TYPECHECK=0
```

Waypoint crossing detection
---------------------------

Detecting when runner crosses a waypoint "gate" defined as a line segment AB (straddling
the course, 100m either side)

Runner's position from one update to the next is the line segment CD

To check these line segments intersect is four cross products:

```
Segments AB and CD. Compute four:

  d1 = cross(A, B, C)      // is C left or right of AB?
  d2 = cross(A, B, D)      // is D left or right of AB?
  d3 = cross(C, D, A)      // is A left or right of CD?
  d4 = cross(C, D, B)      // is B left or right of CD?

  They intersect (properly, i.e. crossing at interior points) iff each segment separates the other's endpoints:

  (d1 > 0) != (d2 > 0)  &&  (d3 > 0) != (d4 > 0)
```

Cross product cross(a, b, c) here means (b-a)×(c-a) which is `(bx - ax)*(cy - ay) - (by - ay)*(cx - ax)`
