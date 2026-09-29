#!/usr/bin/env bash
# Smoke test of the real Linux build on Hyprland: launch against a demo data
# dir, screenshot, send keystrokes, close, relaunch, screenshot again.
set -uo pipefail
BIN=${BIN:-apps/desktop/build/linux/x64/release/bundle/local-board}
export LOCAL_BOARD_DATA_DIR=${LOCAL_BOARD_DATA_DIR:-/tmp/lb-demo}
OUT=${OUT:-/tmp}

win() { hyprctl clients -j | python3 -c "import json,sys; c=[c for c in json.load(sys.stdin) if c['class']=='dev.fcastro.LocalBoard']; print(c[0]['address'] if c else '')"; }
geom() { hyprctl clients -j | python3 -c "import json,sys; c=[c for c in json.load(sys.stdin) if c['class']=='dev.fcastro.LocalBoard'][0]; print(f\"{c['at'][0]},{c['at'][1]} {c['size'][0]}x{c['size'][1]}\")"; }
shot() { focus; sleep 0.8; grim -g "$(geom)" "$OUT/$1.png"; echo "$OUT/$1.png"; }
key() { focus; sleep 0.3; wtype "$@"; sleep 0.5; }

count() { sleep 1.2; python3 -c "import json,glob,sys; f=glob.glob(sys.argv[1]+'/boards/*.whiteboard'); print('$1: objects on disk =', len(json.load(open(f[0]))['objects']) if f else 'no board')" "$LOCAL_BOARD_DATA_DIR"; }
# Hyprland >= 0.50 takes Lua dispatchers.
focus() { hyprctl dispatch "hl.dsp.focus({ window = \"address:$(win)\" })" >/dev/null || true; }
close() { hyprctl dispatch "hl.dsp.window.close({ window = \"address:$(win)\" })" >/dev/null || true; }
gone() { for _ in $(seq 40); do [ -z "$(win)" ] && return; sleep 0.25; done; }
launch() { gone; "$BIN" >/dev/null 2>&1 & for _ in $(seq 40); do [ -n "$(win)" ] && break; sleep 0.25; done; sleep 1.5; }

launch
shot lb-1-open
count open

key -M ctrl a -m ctrl          # select all
shot lb-2-selected
key -k Delete                  # delete
shot lb-3-deleted
count deleted
key -M ctrl z -m ctrl          # undo
key -k Escape
shot lb-4-undone
count undone

close
launch
sleep 1.5
shot lb-5-reopened
count reopened
key -M ctrl w -m ctrl          # back to the board list
sleep 1.5
shot lb-6-home
close
