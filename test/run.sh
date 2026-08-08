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

# --- parse_proxy: the 'host:port:user:pass' form providers export ---
parse_proxy 'host.example:1080:user:pass'
chk "colon-form user" "user"         "$PX_USER"
chk "colon-form pass" "pass"         "$PX_PASS"
chk "colon-form host" "host.example" "$PX_HOST"
chk "colon-form port" "1080"         "$PX_PORT"
chk "colon-form fwd"  "socks5://user:pass@host.example:1080" "$PX_FWD"
# a scheme in front still works, and a password may itself contain colons
parse_proxy 'http://host.example:8080:user:pa:ss'
chk "colon-form scheme" "http"  "$PX_TYPE"
chk "colon-form pass with colon" "pa:ss" "$PX_PASS"
# shapes that are NOT the colon form must be left alone
chk "colon-form ignores host:port"   "host:1080" "$(normalize_colon_form 'host:1080')"
chk "colon-form ignores non-numeric" "a:b:c:d"   "$(normalize_colon_form 'a:b:c:d')"
chk "colon-form ignores user@host"   "u:p@h:1"   "$(normalize_colon_form 'u:p@h:1')"

# --- strip_session: rotate needs a clean username before re-tagging ---
parse_proxy 'user:pass@host:1080'
apply_country GR >/dev/null
apply_session old1 >/dev/null
strip_session
chk "strip_session drops the tag"   "user-country-GR" "$PX_USER"
chk "strip_session keeps the rest"  "socks5://user-country-GR:pass@host:1080" "$PX_FWD"
apply_session new2 >/dev/null
chk "strip_session allows re-tag"   "user-country-GR-session-new2" "$PX_USER"
parse_proxy 'user:pass@host:1080'
strip_session
chk "strip_session is a no-op untagged" "user" "$PX_USER"

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

# A bypass entry is a pattern for the desktop to match hostnames against, not
# one for this shell to expand: splitting the list in a directory that contains
# a matching filename must leave the entry alone.
_bp_tmp="$(mktemp -d)"; touch "$_bp_tmp/printer.local" "$_bp_tmp/decoy.local"
chk "bypass entries are not globbed" "localhost *.local " \
  "$(cd "$_bp_tmp" && each_bypass_entry 'localhost,*.local' | tr '\n' ' ')"
IGNORE_HOSTS='*.local'
chk "gvariant does not glob" "['*.local']" "$(cd "$_bp_tmp" && gvariant_ignore_hosts)"
rm -rf "$_bp_tmp"

# --- detect_backend maps desktops to backends ---
chk "detect gnome"    "gnome" "$(XDG_CURRENT_DESKTOP=GNOME      DESKTOP_SESSION='' detect_backend)"
chk "detect kde"      "kde"   "$(XDG_CURRENT_DESKTOP=KDE        DESKTOP_SESSION='' detect_backend)"
chk "detect plasma"   "kde"   "$(XDG_CURRENT_DESKTOP=plasma     DESKTOP_SESSION='' detect_backend)"
chk "detect cinnamon" "gnome" "$(XDG_CURRENT_DESKTOP=X-Cinnamon DESKTOP_SESSION='' detect_backend)"

# --- env backend writes a sourceable on/off file ---
# CONF_DIR/LOCAL_PORT/IGNORE_HOSTS are consumed by _env_write in the sourced
# script, so shellcheck can't see the use; ENV_FILE is referenced below.
_bk_tmp="$(mktemp -d)"; ENV_FILE="$_bk_tmp/env.sh"
# shellcheck disable=SC2034
CONF_DIR="$_bk_tmp"
# shellcheck disable=SC2034
LOCAL_PORT=1081
# shellcheck disable=SC2034
IGNORE_HOSTS="localhost,127.0.0.0/8"
_env_write on
chk "env on is_on"  "on"                        "$(_env_is_on && echo on || echo off)"
chk "env on url"    "socks5h://127.0.0.1:1081"  "$(grep -o 'socks5h://127.0.0.1:1081' "$ENV_FILE" | head -1)"
# backend_socks must report what the file actually exports, not what LOCAL_PORT
# happens to be now: those drift apart when local_port changes without a
# re-apply, and that drift is the whole point of the desktop check.
# shellcheck disable=SC2034  # read by backend_socks in the sourced script
BACKEND="env"
chk "env socks from the file" "127.0.0.1:1081" "$(backend_socks)"
LOCAL_PORT=1099
chk "env socks ignores a changed port" "127.0.0.1:1081" "$(backend_socks)"
chk "env desktop check sees the drift" "fail" \
  "$(check_desktop_verdict "$(backend_mode)" "$(backend_socks)" "127.0.0.1:1099" up | cut -f1)"
LOCAL_PORT=1081
_env_write off
chk "env off is_on" "off"                        "$(_env_is_on && echo on || echo off)"
chk "env socks when off" ":" "$(backend_socks)"
rm -rf "$_bk_tmp"

# --- json_esc ---
chk "json_esc quote" 'a\"b' "$(json_esc 'a"b')"

# --- resolve_gost precedence ---
# Order: SOCKSY_GOST > gost_path config > self-downloaded copy > PATH > download
# target. The self-downloaded copy is checked before PATH so that upgrading
# socksy never silently moves an existing user off their own gost binary.
_g_tmp="$(mktemp -d)"
printf '#!/bin/sh\necho fake\n' > "$_g_tmp/sysgost"; chmod 755 "$_g_tmp/sysgost"
printf '#!/bin/sh\necho fake\n' > "$_g_tmp/mygost";  chmod 755 "$_g_tmp/mygost"

GOST_DOWNLOAD="$_g_tmp/absent"; cfg_gost_path=""
SOCKSY_GOST="$_g_tmp/sysgost" resolve_gost
chk "gost env override" "$_g_tmp/sysgost" "$GOST"

unset SOCKSY_GOST
cfg_gost_path="$_g_tmp/sysgost"; resolve_gost
chk "gost config key" "$_g_tmp/sysgost" "$GOST"

# A self-downloaded copy wins over one merely on PATH.
# shellcheck disable=SC2034  # read by resolve_gost in the sourced script
cfg_gost_path=""; GOST_DOWNLOAD="$_g_tmp/mygost"
PATH="$_g_tmp:$PATH" resolve_gost
chk "gost download copy first" "$_g_tmp/mygost" "$GOST"

# With no local copy, a gost on PATH is adopted, resolved to an absolute path.
GOST_DOWNLOAD="$_g_tmp/absent"
( cd "$_g_tmp" && ln -sf sysgost gost )
PATH="$_g_tmp:$PATH" resolve_gost
chk "gost from PATH" "$_g_tmp/sysgost" "$GOST"

# Nothing anywhere: fall back to the download target so ensure_gost can fetch it.
# shellcheck disable=SC2034  # read by resolve_gost in the sourced script
GOST_DOWNLOAD="$_g_tmp/absent"
PATH="/nonexistent-dir-for-test" resolve_gost
chk "gost download fallback" "$_g_tmp/absent" "$GOST"
rm -rf "$_g_tmp"

# --- _ff_remove_block: strip socksy's block, delete a file it created ---
_ff_tmp="$(mktemp -d)"
# shellcheck disable=SC2034  # read by _ff_profiles in the sourced script
FF_DIR="$_ff_tmp"
mkdir -p "$_ff_tmp/aaa.default" "$_ff_tmp/bbb.default-release"
# a user.js socksy created: nothing but the managed block
{ echo "$FF_MARK_BEGIN"
  echo 'user_pref("network.proxy.socks_remote_dns", true);'
  echo "$FF_MARK_END"; } > "$_ff_tmp/aaa.default/user.js"
# a user.js the user already had: our block plus their own prefs
{ echo 'user_pref("browser.startup.homepage", "about:blank");'
  echo "$FF_MARK_BEGIN"
  echo 'user_pref("network.proxy.socks_remote_dns", true);'
  echo "$FF_MARK_END"
  echo 'user_pref("general.smoothScroll", false);'; } > "$_ff_tmp/bbb.default-release/user.js"

_ff_remove_block >/dev/null 2>&1
chk "ff removes socksy-only user.js" "gone" \
  "$([ -f "$_ff_tmp/aaa.default/user.js" ] && echo present || echo gone)"
chk "ff keeps user's own user.js" "present" \
  "$([ -f "$_ff_tmp/bbb.default-release/user.js" ] && echo present || echo gone)"
# grep -c prints its own 0 and exits non-zero, so swallow the status, don't add
# a fallback echo (that would print 0 twice).
chk "ff block stripped" "0" \
  "$(grep -cF "$FF_MARK_BEGIN" "$_ff_tmp/bbb.default-release/user.js" 2>/dev/null || true)"
chk "ff user prefs preserved" "2" \
  "$(grep -c 'user_pref' "$_ff_tmp/bbb.default-release/user.js" 2>/dev/null || true)"
rm -rf "$_ff_tmp"

# --- snapshot_desktop / restore_desktop ---
_ds_tmp="$(mktemp -d)"
# shellcheck disable=SC2034  # read by snapshot_desktop in the sourced script
CONF_DIR="$_ds_tmp"
DESKTOP_SNAPSHOT="$_ds_tmp/desktop.orig"

# The env backend owns its whole file, so there is nothing to snapshot.
BACKEND="env"
snapshot_desktop
chk "snapshot skips env backend" "absent" \
  "$([ -e "$DESKTOP_SNAPSHOT" ] && echo present || echo absent)"

# restore_desktop is a no-op without a snapshot, and must not fail.
restore_desktop
chk "restore without snapshot" "0" "$?"

# Stub gsettings so restore's writes can be observed without a real dconf.
_gs_log="$_ds_tmp/gs.log"
# shellcheck disable=SC2317,SC2329  # called indirectly, by restore_desktop
gsettings() { printf '%s\n' "$*" >> "$_gs_log"; }
# shellcheck disable=SC2034  # read by restore_desktop in the sourced script
BACKEND="gnome"
printf "ignore_hosts=['localhost', '::1']\nsocks_host=''\nsocks_port=0\n" > "$DESKTOP_SNAPSHOT"
restore_desktop
chk "restore writes ignore-hosts verbatim" \
  "set org.gnome.system.proxy ignore-hosts ['localhost', '::1']" \
  "$(grep 'ignore-hosts' "$_gs_log")"
chk "restore writes socks host" \
  "set org.gnome.system.proxy.socks host ''" \
  "$(grep 'socks host' "$_gs_log")"
chk "restore clears the snapshot" "absent" \
  "$([ -e "$DESKTOP_SNAPSHOT" ] && echo present || echo absent)"
unset -f gsettings
rm -rf "$_ds_tmp"

# --- cmd_run injects the proxy environment and runs the command ---
# relay_is_active is stubbed, so this needs neither systemd nor a live relay.
# shellcheck disable=SC2317,SC2329  # called indirectly, by cmd_run
relay_is_active() { return 0; }
LOCAL_PORT=1081
# shellcheck disable=SC2034  # read by cmd_run in the sourced script
IGNORE_HOSTS="localhost,127.0.0.0/8, ::1"
# Read the variables back out of the child's own environment rather than through
# a quoted 'sh -c', so the expansion belongs to env(1) and not to a nested shell.
chk "run exports all_proxy"   "socks5h://127.0.0.1:1081" "$(cmd_run env | sed -n 's/^all_proxy=//p')"
chk "run exports HTTPS_PROXY" "socks5h://127.0.0.1:1081" "$(cmd_run env | sed -n 's/^HTTPS_PROXY=//p')"
chk "run trims no_proxy"      "localhost,127.0.0.0/8,::1" "$(cmd_run env | sed -n 's/^no_proxy=//p')"
chk "run passes args verbatim" "a|b c|--flag" "$(cmd_run printf '%s|%s|%s' a 'b c' --flag)"
# Sourcing bin/socksy turned on errexit, so a non-zero result has to be caught
# in an AND-OR list; die() exits outright, so that case also needs a subshell.
_rc=0; cmd_run sh -c 'exit 42' >/dev/null 2>&1 || _rc=$?
chk "run propagates the exit code" "42" "$_rc"
_rc=0; ( cmd_run --profile '' true ) >/dev/null 2>&1 || _rc=$?
chk "run rejects an empty --profile" "1" "$_rc"

# free_port must land above the relay's own port and be unused.
LOCAL_PORT=49500
_fp="$(free_port)"
chk "free_port is above the relay port" "yes" \
  "$({ [ -n "$_fp" ] && [ "$_fp" -gt 49500 ]; } && echo yes || echo no)"
# shellcheck disable=SC2034  # restored for any test appended after this one
LOCAL_PORT=1081

# --- check: pure verdicts (no network, no desktop, no systemd) ---
# check_desktop_verdict: the dangerous case is a manual mode aimed elsewhere.
chk "desktop points at the relay" \
  "pass	system proxy points at the relay (127.0.0.1:1081)" \
  "$(check_desktop_verdict manual '127.0.0.1:1081' '127.0.0.1:1081' up)"
chk "desktop points elsewhere is a failure" \
  "fail	system proxy points at 10.0.0.9:8080, not at the relay (127.0.0.1:1081)" \
  "$(check_desktop_verdict manual '10.0.0.9:8080' '127.0.0.1:1081' up)"
chk "desktop unset is a failure" \
  "fail	system proxy points at nothing, not at the relay (127.0.0.1:1081)" \
  "$(check_desktop_verdict manual '' '127.0.0.1:1081' up)"
chk "desktop direct with a live relay warns" "warn" \
  "$(check_desktop_verdict none ':' '127.0.0.1:1081' up | cut -f1)"
chk "desktop on a PAC warns" "warn" \
  "$(check_desktop_verdict auto ':' '127.0.0.1:1081' up | cut -f1)"

# check_bind_verdict: a relay off loopback is an open proxy for the LAN.
chk "bind loopback"      "pass" "$(check_bind_verdict '127.0.0.1:1081' | cut -f1)"
chk "bind v6 loopback"   "pass" "$(check_bind_verdict '[::1]:1081'     | cut -f1)"
chk "bind wildcard"      "fail" "$(check_bind_verdict '0.0.0.0:1081'   | cut -f1)"
chk "bind v6 wildcard"   "fail" "$(check_bind_verdict '[::]:1081'      | cut -f1)"
chk "bind lan address"   "warn" "$(check_bind_verdict '192.168.1.5:1081' | cut -f1)"
chk "bind unreadable"    "skip" "$(check_bind_verdict ''               | cut -f1)"

# check_leak_verdict: same address proxied and direct means nothing is proxied.
chk "leak same ip fails"   "fail" "$(check_leak_verdict 1.2.3.4 1.2.3.4 | cut -f1)"
chk "leak differing ips"   "pass" "$(check_leak_verdict 1.2.3.4 5.6.7.8 | cut -f1)"
chk "leak no direct route" \
  "pass	no direct route to the internet; nothing can slip past the relay" \
  "$(check_leak_verdict 1.2.3.4 '')"

# geo_expected_country: read the tag back out of a username.
chk "geo from country tag" "GR" "$(geo_expected_country 'user-country-GR')"
chk "geo stops at the next tag" "GR" "$(geo_expected_country 'user-country-GR-session-abc')"
chk "geo upcases" "US" "$(geo_expected_country 'user-country-us')"
chk "geo empty when untagged" "" "$(geo_expected_country 'user-session-abc')"
_ck_saved_kw="$COUNTRY_KEYWORD"
COUNTRY_KEYWORD="_country_"
chk "geo honours the keyword" "GR" "$(geo_expected_country 'user_country_GR_session_abc')"
COUNTRY_KEYWORD="$_ck_saved_kw"

# bypass_public_entries: only entries that really route around the relay.
chk "bypass defaults are all private" "" \
  "$(bypass_public_entries "$DEFAULT_IGNORE_HOSTS")"
chk "bypass flags a public host" "example.com" \
  "$(bypass_public_entries 'localhost,127.0.0.0/8,example.com,192.168.0.0/16')"
chk "bypass flags a wildcard" "*" "$(bypass_public_entries 'localhost,*')"
chk "bypass keeps 172.16/12 private" "" "$(bypass_public_entries '172.16.0.0/12,172.31.5.5')"
chk "bypass treats 172.32 as public" "172.32.0.1" "$(bypass_public_entries '172.32.0.1')"
chk "bypass ignores whitespace" "" "$(bypass_public_entries ' localhost , ::1 , *.local ')"

# check_row tallies and builds one JSON object per row.
_chk_pass=0; _chk_warn=0; _chk_fail=0; _chk_json=""; _chk_quiet=1
check_row relay pass "listening"
check_row ipv6  warn "reachable directly"
check_row geo   fail "wrong country"
check_row bind  skip "not listening"
chk "check_row counts passes"   "1" "$_chk_pass"
chk "check_row counts warnings" "1" "$_chk_warn"
chk "check_row counts failures" "1" "$_chk_fail"
chk "check_row skips are untallied" "3" "$((_chk_pass + _chk_warn + _chk_fail))"
chk "check_row joins rows with a comma" "4" "$(printf '%s' "$_chk_json" | grep -o '{' | wc -l)"
_chk_json=""
check_row relay pass 'listening on "1081"'
chk "check_row emits json" '{"name":"relay","status":"pass","detail":"listening on \"1081\""}' \
  "$_chk_json"

# check_summary decides the exit status: failures always, warnings with --strict.
_chk_pass=2; _chk_warn=0; _chk_fail=0
_cs=0; check_summary "" "" >/dev/null || _cs=$?
chk "summary clean exits 0" "0" "$_cs"
_chk_warn=1
_cs=0; check_summary "" "" >/dev/null || _cs=$?
chk "summary warning exits 0" "0" "$_cs"
_cs=0; check_summary "" 1 >/dev/null || _cs=$?
chk "summary warning exits 1 under --strict" "1" "$_cs"
_chk_warn=0; _chk_fail=1
_cs=0; check_summary "" "" >/dev/null || _cs=$?
chk "summary failure exits 1" "1" "$_cs"
_chk_json='{"name":"relay","status":"pass","detail":"listening"}'
chk "summary --json is one document" \
  '{"version":"'"$VERSION"'","pass":0,"warn":0,"fail":1,"checks":[{"name":"relay","status":"pass","detail":"listening"}]}' \
  "$(_chk_pass=0; check_summary 1 "" || true)"
_chk_quiet=""

# --- bad port must error ---
( parse_proxy 'host:notaport' ) 2>/dev/null \
  && { echo "FAIL bad-port did not error"; fail=$((fail+1)); } \
  || { echo "ok   bad-port errors"; pass=$((pass+1)); }

echo
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
