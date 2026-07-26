#!/usr/bin/env bash
#
# socksy uninstaller that turns the proxy off and removes socksy's files.
# By default it KEEPS the downloaded gost binary and your saved profiles.
# Pass --purge to remove those too.
#
# Mirrors install.sh: --prefix selects the install root that was used.
# Per-user state (~/.config/socksy, systemd user units) is always per-user,
# regardless of prefix, so it is removed from $HOME either way.
#
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
PURGE=0

usage() {
  cat <<'EOF'
usage: uninstall.sh [--prefix DIR] [--purge] [-h|--help]

  --prefix DIR   install root to remove from (default: ~/.local)
  --purge        also remove the gost binary and ~/.config/socksy
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --purge)   PURGE=1; shift ;;
    --prefix)  PREFIX="${2:?--prefix needs a directory}"; shift 2 ;;
    --prefix=*) PREFIX="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

# Turn everything off and undo the desktop changes while the command still
# exists (ignore errors if it is already gone). 'off' hands back the no-proxy
# list and SOCKS host, 'dns reset' strips the managed block from Firefox.
if command -v socksy >/dev/null 2>&1; then
  socksy off || true
  socksy dns reset || true
fi
systemctl --user disable --now socksy-watchdog.timer >/dev/null 2>&1 || true
systemctl --user disable --now socksy-relay.service >/dev/null 2>&1 || true

rm -f "$PREFIX/bin/socksy"
rm -f "$PREFIX/share/bash-completion/completions/socksy"
rm -f "$PREFIX/share/zsh/site-functions/_socksy"
rm -f "$PREFIX/share/man/man1/socksy.1"
rm -f "$HOME/.config/systemd/user/socksy-relay.service"
rm -f "$HOME/.config/systemd/user/socksy-watchdog.service"
rm -f "$HOME/.config/systemd/user/socksy-watchdog.timer"
systemctl --user daemon-reload >/dev/null 2>&1 || true
echo "removed: socksy command + systemd units + completions + man page"

if [ "$PURGE" -eq 1 ]; then
  rm -f "$HOME/.local/bin/gost"
  rm -rf "$HOME/.config/socksy"
  echo "purged: gost binary + saved profiles"
else
  echo "kept: gost binary and ~/.config/socksy (use --purge to remove them)"
fi
echo "done."
