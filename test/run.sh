#!/usr/bin/env bash
#
# Dependency-free unit tests for socksy's pure functions.
# Loads the script as a library (SOCKSY_LIB=1) so nothing touches GNOME,
# systemd, or the network. Run: bash test/run.sh
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/socksy"

pass=0; fail=0
chk() { # chk "label" "expected" "actual"
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"
  else fail=$((fail+1)); printf 'FAIL %s\n       expected: [%s]\n       actual:   [%s]\n' "$1" "$2" "$3"; fi
}

export SOCKSY_LIB=1
# shellcheck disable=SC1090
source "$SCRIPT"

# --- parse_proxy: authenticated socks5 ---
parse_proxy 'user:pass@host.example:1080'
chk "auth user"  "user"          "$PX_USER"
chk "auth pass"  "pass"          "$PX_PASS"
chk "auth host"  "host.example"  "$PX_HOST"
chk "auth port"  "1080"          "$PX_PORT"
chk "auth type"  "socks5"        "$PX_TYPE"
chk "auth fwd"   "socks5://user:pass@host.example:1080" "$PX_FWD"

# --- parse_proxy: bare host:port (no auth) ---
parse_proxy 'host.example:1080'
chk "noauth user empty" "" "$PX_USER"
chk "noauth fwd" "socks5://host.example:1080" "$PX_FWD"

# --- parse_proxy: scheme handling ---
parse_proxy 'socks5h://u:p@h:1'
chk "socks5h type" "socks5" "$PX_TYPE"
chk "socks5h fwd"  "socks5://u:p@h:1" "$PX_FWD"
parse_proxy 'http://u:p@h:8080'
chk "http type" "http" "$PX_TYPE"
chk "http fwd"  "http://u:p@h:8080" "$PX_FWD"
parse_proxy 'https://u:p@h:8443'
chk "https type" "https" "$PX_TYPE"
chk "https fwd"  "https://u:p@h:8443" "$PX_FWD"

# --- effective_proxy_string always carries a scheme ---
parse_proxy 'user:pass@host:1080'
chk "effective socks5" "socks5://user:pass@host:1080" "$(effective_proxy_string)"
parse_proxy 'http://user:pass@host:8080'
chk "effective http"   "http://user:pass@host:8080"   "$(effective_proxy_string)"

# --- apply_country ---
parse_proxy 'user:pass@host:1080'
apply_country gr >/dev/null
chk "country upcased+appended" "user-country-GR" "$PX_USER"
chk "country in fwd" "socks5://user-country-GR:pass@host:1080" "$PX_FWD"
apply_country US >/dev/null 2>&1   # idempotent: keyword already present
chk "country idempotent" "user-country-GR" "$PX_USER"

# --- apply_session ---
parse_proxy 'user:pass@host:1080'
apply_session mytoken >/dev/null
chk "session appended" "user-session-mytoken" "$PX_USER"

# --- ordering: country then session ---
parse_proxy 'user:pass@host:1080'
apply_country GR >/dev/null
apply_session foo >/dev/null
chk "country before session" "user-country-GR-session-foo" "$PX_USER"

# --- mask: scheme-aware ---
chk "mask auth"          "user:***@host:1080"        "$(mask 'user:pass@host:1080')"
chk "mask scheme+auth"   "http://user:***@host:8080" "$(mask 'http://user:pass@host:8080')"
chk "mask noauth"        "host:1080"                 "$(mask 'host:1080')"
chk "mask scheme noauth" "socks5://host:1080"        "$(mask 'socks5://host:1080')"

# --- gvariant_ignore_hosts formatting ---
# shellcheck disable=SC2034  # read by gvariant_ignore_hosts (sourced from bin/socksy)
IGNORE_HOSTS="localhost,127.0.0.0/8, ::1"
chk "gvariant array" "['localhost', '127.0.0.0/8', '::1']" "$(gvariant_ignore_hosts)"

# --- json_esc ---
chk "json_esc quote" 'a\"b' "$(json_esc 'a"b')"

# --- bad port must error ---
( parse_proxy 'host:notaport' ) 2>/dev/null \
  && { echo "FAIL bad-port did not error"; fail=$((fail+1)); } \
  || { echo "ok   bad-port errors"; pass=$((pass+1)); }

echo
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
