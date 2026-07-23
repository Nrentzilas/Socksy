#!/usr/bin/env bash
#
# socksy uninstaller that turns the proxy off and removes socksy's files.
# By default it KEEPS the downloaded gost binary and your saved profiles.
# Pass --purge to remove those too.
#
set -euo pipefail

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

# turn everything off first (ignore errors if already gone)
command -v socksy >/dev/null 2>&1 && socksy off || true
systemctl --user disable --now socksy-watchdog.timer >/dev/null 2>&1 || true
systemctl --user disable --now socksy-relay.service >/dev/null 2>&1 || true

rm -f "$HOME/.local/bin/socksy"
rm -f "$HOME/.config/systemd/user/socksy-relay.service"
rm -f "$HOME/.config/systemd/user/socksy-watchdog.service"
rm -f "$HOME/.config/systemd/user/socksy-watchdog.timer"
rm -f "$HOME/.local/share/bash-completion/completions/socksy"
rm -f "$HOME/.local/share/zsh/site-functions/_socksy"
rm -f "$HOME/.local/share/man/man1/socksy.1"
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
