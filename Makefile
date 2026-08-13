# Puffing Billy data field
#
# Override any of these on the command line, e.g.
#   make run DEVICE=venu445mm
#   make build TYPECHECK=0

SDK_ROOT  ?= $(HOME)/.Garmin/ConnectIQ/Sdks
SDK       ?= $(lastword $(sort $(wildcard $(SDK_ROOT)/connectiq-sdk-lin-*)))
BIN       := $(SDK)/bin

DEVICE    ?= venu441mm
KEY       ?= developer_key.der
NAME      ?= PuffingBilly
TYPECHECK ?= 3

OUT := bin
PRG := $(OUT)/$(NAME)-$(DEVICE).prg
IQ  := $(OUT)/$(NAME).iq

SOURCES := manifest.xml monkey.jungle \
           $(shell find source resources -type f 2>/dev/null)

MONKEYC := $(BIN)/monkeyc -f monkey.jungle -y $(KEY) -w -l $(TYPECHECK)

.PHONY: all build run sim deploy package clean check segments

all: build

check:
	@test -n "$(SDK)"   || { echo "No SDK under $(SDK_ROOT)"; exit 1; }
	@test -x "$(BIN)/monkeyc" || { echo "No monkeyc in $(BIN)"; exit 1; }
	@test -f "$(KEY)"   || { echo "No developer key at $(KEY) (override with KEY=)"; exit 1; }

segments:
	python segments/make_segments.py

build: check segments $(PRG)

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
package: check | $(OUT)
	$(MONKEYC) -e -o $(IQ)

# Sideload over MTP. Plug the watch in and let gvfs mount it first.
# The glob is expanded by the shell rather than by $(wildcard), because make
# splits variable values on the space in "Internal Storage" with no way to quote
# it back together.
deploy: build
	@apps=$$(echo /run/user/$$(id -u)/gvfs/mtp:host=*/"Internal Storage/GARMIN/Apps"); \
	test -d "$$apps" || { echo "Watch not mounted at $$apps"; exit 1; }; \
	gio copy "$(PRG)" "$$apps/$(notdir $(PRG))" && echo "-> $$apps/$(notdir $(PRG))"

clean:
	rm -rf $(OUT)
