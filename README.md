setup
-----

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
`.gpx` track. `make` does this for you before every build, so you only need it on
its own to see the pacing table it prints:

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


course data
-----------

The watch doesn't know the course; it's compiled in as a JSON resource. The chain
from the course definition to the data field is:

```
segments/config.json           waypoint distances and pacing parameters - edit this
segments/official-course-2026.gpx    the recorded course track
             |
             |  segments/make_segments.py  (make segments)
             v
segments/out/segments.json     everything the calculation produced
             |
             |  make_resource(), in the same script
             v
segments/out/resource.json     the subset that goes on the watch
             |
             |  resources/jsonData/segments.xml
             v
$.Rez.JsonData.Segments        loaded in PuffingBillyField.initialize()
```

`segments/config.json` is the only file you edit to change the course or the
target pace. It holds:

- `waypoints`: the segment endpoints, as a name mapped to its distance in km
  into the course, in order. The last one is the finish.
- `pacing.flat_pace`: target pace on flat ground, `"m:ss"` per km.
- `pacing.uphill_penalty` and `pacing.downhill_bonus`: fractional slowdown and
  speedup per unit of grade, used to turn each segment's average grade into its
  target pace.

`make_segments.py` locates each waypoint along the `.gpx` track, fits the course
heading there, and builds the 200 m "gate" normal to that heading which the
runner passes through - see the waypoint crossing section below. It also
computes each segment's average grade from the track elevation and grade-adjusts
the flat pace to get a per-segment target pace. All of that lands in
`segments.json`, along with the working (heading, elevation, coordinates), and it
prints a per-segment pacing table plus the predicted total time.

`resource.json` is the part of that the data field actually needs - names,
lengths, paces and gates - as parallel arrays, with coordinates in integer
semicircles. It's trimmed and reshaped deliberately, to keep both heap and
floating point precision under control on the watch; `make_resource()`'s
docstring explains why.

`resources/jsonData/segments.xml` points the Connect IQ resource compiler at
`resource.json`, which is what makes it `$.Rez.JsonData.Segments` in the app.

`segments/out/` is gitignored, so it isn't in a fresh clone. Nothing needs doing
about that: `make build` depends on the `segments` target, which is phony and so
regenerates both files on every build - an edit to `config.json` can't be left
out of the `.prg`.

`segments/plot_segments.py` has no make target; run it by hand after
`make segments` to draw the course with the gates overlaid and the elevation
profile, into `segments/out/*.png`:

```bash
python segments/plot_segments.py
```


Waypoint crossing detection
---------------------------

Detecting when runner crosses a waypoint defined as a line segment

Waypoint "gate" defined as line segment AB (in practice, straddling the course, 100m either side)

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

Cross product cross(a, b, c) here means (b-a)×(c-a) which is:
```python
def cross(ax, ay, bx, by, cx, cy):
    return (bx - ax)*(cy - ay) - (by - ay)*(cx - ax)
```
