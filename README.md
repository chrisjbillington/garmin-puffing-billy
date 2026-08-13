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
