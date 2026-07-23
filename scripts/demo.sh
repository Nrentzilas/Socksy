#!/usr/bin/env bash
#
# scripts/demo.sh opens a fresh terminal and runs a start-to-finish socksy
# demo for screen recording: install → apply a proxy → live IP → health
# watchdog → off. Waits SOCKSY_DEMO_INTRO seconds up front so you can start
# your recorder.
#
#   bash scripts/demo.sh                 # opens a new terminal and runs the demo
#   SOCKSY_DEMO_INNER=1 bash scripts/demo.sh   # run in the CURRENT terminal
#
# Config (env vars):
#   SOCKSY_DEMO_PROFILE   saved profile to demo with   (default: demo)
#   SOCKSY_DEMO_INTRO     seconds to wait up front      (default: 20)
#
# The proxy string is read from your saved profile at runtime, so no
# credentials are stored in this script.
#
set -uo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
REPO="$(cd "$(dirname "$SELF")/.." && pwd)"
PROFILE="${SOCKSY_DEMO_PROFILE:-demo}"
INTRO="${SOCKSY_DEMO_INTRO:-20}"
PROFILES="$HOME/.config/socksy/profiles"

# ---- launcher: open a new terminal, then run the inner demo -----------------
if [ "${SOCKSY_DEMO_INNER:-}" != 1 ]; then
  # Preflight (fails here, before you ever hit record):
  [ -f "$REPO/install.sh" ] || { echo "Run this from the socksy repo (install.sh not found)."; exit 1; }
  grep -qP "^${PROFILE}\t" "$PROFILES" 2>/dev/null || {
    echo "No saved profile '${PROFILE}'. Create one first (off-camera):"
    echo "    socksy save ${PROFILE} 'user:pass@host:port'"
    echo "or pick another with:  SOCKSY_DEMO_PROFILE=<name> bash scripts/demo.sh"
    exit 1
  }

  inner="SOCKSY_DEMO_INNER=1 SOCKSY_DEMO_PROFILE='${PROFILE}' SOCKSY_DEMO_INTRO='${INTRO}' bash '${SELF}'"
  echo "Opening a new terminal for the demo… start your recorder within ${INTRO}s."
  if   command -v ptyxis         >/dev/null 2>&1; then ptyxis --new-window -d "$REPO" -T "socksy demo" -- bash -lc "$inner"
  elif command -v gnome-terminal >/dev/null 2>&1; then gnome-terminal --window --working-directory="$REPO" -- bash -lc "$inner"
  elif command -v kgx           >/dev/null 2>&1; then kgx --working-directory="$REPO" -- bash -lc "$inner"
  elif command -v konsole        >/dev/null 2>&1; then konsole --workdir "$REPO" -e bash -lc "$inner"
  elif command -v xterm          >/dev/null 2>&1; then xterm -e bash -lc "$inner"
  else echo "No known terminal emulator found, running inline instead."; SOCKSY_DEMO_INNER=1 exec bash "$SELF"
  fi
  exit 0
fi

# ---- inner: the actual demo -------------------------------------------------
cd "$REPO" || exit 1

if [ -t 1 ]; then
  B=$'\e[1m'; DIM=$'\e[2m'; C=$'\e[36m'; G=$'\e[32m'; Y=$'\e[33m'; X=$'\e[0m'
else B=""; DIM=""; C=""; G=""; Y=""; X=""; fi

# best-effort: give the recording a consistent window size
printf '\e[8;32;110t' 2>/dev/null || true

type_cmd() {                       # echo a command with a typewriter effect
  printf '%s$%s ' "$C" "$X"
  local c="$1" i
  for ((i=0; i<${#c}; i++)); do printf '%s' "${c:i:1}"; sleep 0.028; done
  printf '\n'
}
comment() { printf '\n%s# %s%s\n' "$DIM" "$1" "$X"; sleep 0.9; }
run()     { type_cmd "$1"; sleep 0.35; eval "$1"; sleep "${2:-2.5}"; }

# read the real proxy from the saved profile (strip any scheme for a clean look)
PROXY_RAW="$(grep -P "^${PROFILE}\t" "$PROFILES" 2>/dev/null | head -1 | cut -f2- || true)"
PROXY="${PROXY_RAW#*://}"
[ -n "$PROXY" ] || { echo "could not read proxy from profile '${PROFILE}'"; exit 1; }

# restore a clean state on exit (also covers Ctrl-C mid-demo)
cleanup() {
  socksy off >/dev/null 2>&1 || true
  systemctl --user disable --now socksy-watchdog.timer >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ---- intro countdown --------------------------------------------------------
clear
printf '\n\n  %s▶ socksy demo%s\n\n  Position your screen recorder now.\n\n' "$B" "$X"
for ((s=INTRO; s>0; s--)); do
  printf '\r  %s● recording starts in %2ds …%s' "$Y" "$s" "$X"
  sleep 1
done
printf '\r\033[K'
clear

# ---- the walkthrough --------------------------------------------------------
printf '%s  socksy: authenticated SOCKS5, system-wide on GNOME, in one command.%s\n' "$B" "$X"
sleep 1.5

comment "1. install with no root; everything lives under ~/.local"
run "./install.sh" 2.5

comment "2. apply an authenticated SOCKS5 proxy (auto-installs gost, auto-tests the exit IP)"
type_cmd "socksy set '${PROXY}'"; sleep 0.35; socksy set "$PROXY"; sleep 3.5

comment "3. what's active right now"
run "socksy status" 3.5

comment "4. watch the live exit IP"
type_cmd "socksy watch 3"; sleep 0.35; timeout 9 socksy watch 3 || true; sleep 1.5

comment "5. health watchdog auto-reconnects the relay when an exit goes bad"
run "socksy watchdog on" 2.5
run "socksy watchdog status" 3.5

comment "6. one clean switch back to a direct connection"
run "socksy off" 2.5

printf '\n  %s✔ that'\''s socksy: one command in, one command out.%s\n\n' "$G" "$X"
read -rp "  (press Enter to close) " _ || true
