# Puffing Billy data field
#
# Override any of these on the command line, e.g.
#   make run DEVICE=venu445mm
#   make build TYPECHECK=0

SDK_ROOT  ?= $(HOME)/.Garmin/ConnectIQ/Sdks
SDK       ?= $(lastword $(sort $(wildcard $(SDK_ROOT)/connectiq-sdk-lin-*)))
BIN       := $(SDK)/bin

DEVICE    ?= venu441mm
KEY       ?= .secrets/developer_key.der
NAME      ?= PuffingBilly
TYPECHECK ?= 3
PYTHON    ?= python3

OUT := bin
PRG := $(OUT)/$(NAME)-$(DEVICE).prg
IQ  := $(OUT)/$(NAME).iq

# The course data compiled into the app, and what it is built from. Every build
# depends on this file, so an edit to config.toml cannot be left out of a .prg.
RESOURCE := out/resource.json
COURSE   := make_segments.py config.toml official-course-2026.gpx

SOURCES := manifest.xml monkey.jungle $(RESOURCE) \
           $(shell find source resources -type f 2>/dev/null)

MONKEYC := $(BIN)/monkeyc -f monkey.jungle -y $(KEY) -w -l $(TYPECHECK)

.PHONY: all build run sim deploy package clean check segments plots

all: build

check:
	@test -n "$(SDK)"   || { echo "No SDK under $(SDK_ROOT)"; exit 1; }
	@test -x "$(BIN)/monkeyc" || { echo "No monkeyc in $(BIN)"; exit 1; }
	@test -f "$(KEY)"   || { echo "No developer key at $(KEY) (override with KEY=)"; exit 1; }

# make_segments.py writes segments.json alongside resource.json; the one named
# here stands for both.
$(RESOURCE): $(COURSE)
	$(PYTHON) make_segments.py

segments: $(RESOURCE)

# Regenerate the course plots in out/ and refresh the copies of them embedded
# in README.md. MPLBACKEND=Agg so no plot window opens.
plots: $(RESOURCE)
	MPLBACKEND=Agg $(PYTHON) plot_segments.py
	cp out/course_gates.png out/course_elevation.png readme_images/

build: check $(PRG)

$(PRG): $(SOURCES) | $(OUT)
	$(MONKEYC) -d $(DEVICE) -o $@

$(OUT):
	@mkdir -p $(OUT)

# Blocks. Run it in its own terminal and leave it there; `run` will not start
# the simulator for you, and will not shut it down.
sim:
	$(BIN)/connectiq

run: build
	@pgrep -x simulator >/dev/null || { echo "Simulator not running - start it with 'make sim' in another terminal"; exit 1; }
	$(BIN)/monkeydo $(PRG) $(DEVICE)

# Store-ready .iq bundle (all products in the manifest, signed).
package: check $(RESOURCE) | $(OUT)
	$(MONKEYC) -e -o $(IQ)

# Sideload over MTP. Plug the watch in and let gvfs mount it first.
# The glob is expanded by the shell rather than by $(wildcard), because make
# splits variable values on the space in "Internal Storage" with no way to quote
# it back together.
deploy: build
	@apps=$$(echo /run/user/$$(id -u)/gvfs/mtp:host=*/"Internal Storage/GARMIN/Apps"); \
	test -d "$$apps" || { echo "Watch not mounted at $$apps"; exit 1; }; \
	gio copy "$(PRG)" "$$apps/$(notdir $(PRG))" && echo "-> $$apps/$(notdir $(PRG))"

# Delete bin/ and the generated course data in out/.
clean:
	rm -rf $(OUT) out
