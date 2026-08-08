#!/usr/bin/env bats
#
# bats test suite for socksy's pure functions.
# Install bats-core (https://github.com/bats-core/bats-core), then:  bats test/
# No GNOME/systemd/network needed, since the script is sourced as a library.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SOCKSY_LIB=1
  # shellcheck disable=SC1090
  source "$ROOT/bin/socksy"
}

@test "parse_proxy: authenticated socks5" {
  parse_proxy 'user:pass@host.example:1080'
  [ "$PX_USER" = user ]
  [ "$PX_PASS" = pass ]
  [ "$PX_HOST" = host.example ]
  [ "$PX_PORT" = 1080 ]
  [ "$PX_TYPE" = socks5 ]
  [ "$PX_FWD" = "socks5://user:pass@host.example:1080" ]
}

@test "parse_proxy: bare host:port (no auth)" {
  parse_proxy 'host.example:1080'
  [ -z "$PX_USER" ]
  [ "$PX_FWD" = "socks5://host.example:1080" ]
}

@test "parse_proxy: socks5h:// stays socks5" {
  parse_proxy 'socks5h://u:p@h:1'
  [ "$PX_TYPE" = socks5 ]
  [ "$PX_FWD" = "socks5://u:p@h:1" ]
}

@test "parse_proxy: http:// scheme detected" {
  parse_proxy 'http://u:p@h:8080'
  [ "$PX_TYPE" = http ]
  [ "$PX_FWD" = "http://u:p@h:8080" ]
}

@test "parse_proxy: https:// scheme detected" {
  parse_proxy 'https://u:p@h:8443'
  [ "$PX_TYPE" = https ]
  [ "$PX_FWD" = "https://u:p@h:8443" ]
}

@test "parse_proxy: 'host:port:user:pass' provider form" {
  parse_proxy 'host.example:1080:user:pass'
  [ "$PX_USER" = user ]
  [ "$PX_PASS" = pass ]
  [ "$PX_HOST" = host.example ]
  [ "$PX_PORT" = 1080 ]
  [ "$PX_FWD" = "socks5://user:pass@host.example:1080" ]
}

@test "parse_proxy: colon form keeps a scheme and a colon-bearing password" {
  parse_proxy 'http://host.example:8080:user:pa:ss'
  [ "$PX_TYPE" = http ]
  [ "$PX_PASS" = "pa:ss" ]
}

@test "normalize_colon_form leaves other shapes alone" {
  [ "$(normalize_colon_form 'host:1080')" = 'host:1080' ]
  [ "$(normalize_colon_form 'a:b:c:d')"   = 'a:b:c:d' ]
  [ "$(normalize_colon_form 'u:p@h:1')"   = 'u:p@h:1' ]
}

@test "strip_session removes a session tag and allows re-tagging" {
  parse_proxy 'user:pass@host:1080'
  apply_country GR
  apply_session old1
  strip_session
  [ "$PX_USER" = "user-country-GR" ]
  apply_session new2
  [ "$PX_USER" = "user-country-GR-session-new2" ]
}

@test "strip_session is a no-op on an untagged username" {
  parse_proxy 'user:pass@host:1080'
  strip_session
  [ "$PX_USER" = user ]
}

@test "effective_proxy_string always carries a scheme" {
  parse_proxy 'user:pass@host:1080'
  [ "$(effective_proxy_string)" = "socks5://user:pass@host:1080" ]
  parse_proxy 'http://user:pass@host:8080'
  [ "$(effective_proxy_string)" = "http://user:pass@host:8080" ]
}

@test "apply_country uppercases, appends, and is idempotent" {
  parse_proxy 'user:pass@host:1080'
  apply_country gr
  [ "$PX_USER" = "user-country-GR" ]
  [ "$PX_FWD" = "socks5://user-country-GR:pass@host:1080" ]
  apply_country US || true
  [ "$PX_USER" = "user-country-GR" ]
}

@test "apply_session appends a session tag" {
  parse_proxy 'user:pass@host:1080'
  apply_session mytoken
  [ "$PX_USER" = "user-session-mytoken" ]
}

@test "tag ordering is country then session" {
  parse_proxy 'user:pass@host:1080'
  apply_country GR
  apply_session foo
  [ "$PX_USER" = "user-country-GR-session-foo" ]
}

@test "mask is scheme-aware" {
  [ "$(mask 'user:pass@host:1080')" = "user:***@host:1080" ]
  [ "$(mask 'http://user:pass@host:8080')" = "http://user:***@host:8080" ]
  [ "$(mask 'host:1080')" = "host:1080" ]
  [ "$(mask 'socks5://host:1080')" = "socks5://host:1080" ]
}

@test "gvariant_ignore_hosts builds a GVariant array" {
  IGNORE_HOSTS="localhost,127.0.0.0/8, ::1"
  [ "$(gvariant_ignore_hosts)" = "['localhost', '127.0.0.0/8', '::1']" ]
}

# A bypass entry is a pattern for the desktop, not for this shell: splitting the
# list in a directory that happens to contain a matching name must not expand it.
@test "bypass entries are never glob-expanded" {
  local d; d="$(mktemp -d)"
  touch "$d/printer.local" "$d/decoy.local"
  cd "$d"
  [ "$(each_bypass_entry 'localhost,*.local' | tr '\n' ' ')" = "localhost *.local " ]
  IGNORE_HOSTS='*.local'
  [ "$(gvariant_ignore_hosts)" = "['*.local']" ]
  cd "$ROOT"
  rm -rf "$d"
}

@test "check_desktop_verdict flags a system proxy aimed elsewhere" {
  [ "$(check_desktop_verdict manual '127.0.0.1:1081' '127.0.0.1:1081' up | cut -f1)" = pass ]
  [ "$(check_desktop_verdict manual '10.0.0.9:8080' '127.0.0.1:1081' up | cut -f1)" = fail ]
  [ "$(check_desktop_verdict manual '' '127.0.0.1:1081' up | cut -f1)" = fail ]
  [ "$(check_desktop_verdict none ':' '127.0.0.1:1081' up | cut -f1)" = warn ]
  [ "$(check_desktop_verdict auto ':' '127.0.0.1:1081' up | cut -f1)" = warn ]
}

@test "check_bind_verdict flags a relay that is not loopback-only" {
  [ "$(check_bind_verdict '127.0.0.1:1081' | cut -f1)" = pass ]
  [ "$(check_bind_verdict '[::1]:1081'     | cut -f1)" = pass ]
  [ "$(check_bind_verdict '0.0.0.0:1081'   | cut -f1)" = fail ]
  [ "$(check_bind_verdict '[::]:1081'      | cut -f1)" = fail ]
  [ "$(check_bind_verdict '192.168.1.5:1081' | cut -f1)" = warn ]
  [ "$(check_bind_verdict ''               | cut -f1)" = skip ]
}

@test "check_leak_verdict fails when proxied and direct share an address" {
  [ "$(check_leak_verdict 1.2.3.4 1.2.3.4 | cut -f1)" = fail ]
  [ "$(check_leak_verdict 1.2.3.4 5.6.7.8 | cut -f1)" = pass ]
  [ "$(check_leak_verdict 1.2.3.4 ''      | cut -f1)" = pass ]
}

@test "geo_expected_country reads the tag back out of a username" {
  [ "$(geo_expected_country 'user-country-GR')" = GR ]
  [ "$(geo_expected_country 'user-country-GR-session-abc')" = GR ]
  [ "$(geo_expected_country 'user-country-us')" = US ]
  [ -z "$(geo_expected_country 'user-session-abc')" ]
}

@test "bypass_public_entries lists only what routes around the relay" {
  [ -z "$(bypass_public_entries "$DEFAULT_IGNORE_HOSTS")" ]
  [ "$(bypass_public_entries 'localhost,example.com,192.168.0.0/16')" = "example.com" ]
  [ "$(bypass_public_entries 'localhost,*')" = "*" ]
  [ -z "$(bypass_public_entries '172.16.0.0/12,172.31.5.5')" ]
  [ "$(bypass_public_entries '172.32.0.1')" = "172.32.0.1" ]
}

@test "check_summary exits non-zero on a failure, and on a warning with --strict" {
  _chk_pass=2; _chk_warn=0; _chk_fail=0
  run check_summary "" ""
  [ "$status" -eq 0 ]
  _chk_warn=1
  run check_summary "" ""
  [ "$status" -eq 0 ]
  run check_summary "" 1
  [ "$status" -eq 1 ]
  _chk_warn=0; _chk_fail=1
  run check_summary "" ""
  [ "$status" -eq 1 ]
}

@test "json_esc escapes quotes" {
  [ "$(json_esc 'a"b')" = 'a\"b' ]
}

@test "detect_backend maps desktops to backends" {
  [ "$(XDG_CURRENT_DESKTOP=GNOME      DESKTOP_SESSION='' detect_backend)" = gnome ]
  [ "$(XDG_CURRENT_DESKTOP=KDE        DESKTOP_SESSION='' detect_backend)" = kde ]
  [ "$(XDG_CURRENT_DESKTOP=plasma     DESKTOP_SESSION='' detect_backend)" = kde ]
  [ "$(XDG_CURRENT_DESKTOP=X-Cinnamon DESKTOP_SESSION='' detect_backend)" = gnome ]
}

@test "env backend writes a sourceable on/off file" {
  local d; d="$(mktemp -d)"
  CONF_DIR="$d"; ENV_FILE="$d/env.sh"; LOCAL_PORT=1081; IGNORE_HOSTS="localhost"
  _env_write on
  _env_is_on
  grep -q 'socks5h://127.0.0.1:1081' "$ENV_FILE"
  _env_write off
  ! _env_is_on
  rm -rf "$d"
}

# The endpoint must come from the file, not from the current LOCAL_PORT: those
# drift apart when local_port changes without a re-apply, and rebuilding it here
# would hide the drift the desktop check exists to find.
@test "env backend_socks reports what the file exports" {
  local d; d="$(mktemp -d)"
  CONF_DIR="$d"; ENV_FILE="$d/env.sh"; LOCAL_PORT=1081; IGNORE_HOSTS="localhost"
  BACKEND="env"
  _env_write on
  [ "$(backend_socks)" = "127.0.0.1:1081" ]
  LOCAL_PORT=1099
  [ "$(backend_socks)" = "127.0.0.1:1081" ]
  [ "$(check_desktop_verdict "$(backend_mode)" "$(backend_socks)" '127.0.0.1:1099' up | cut -f1)" = fail ]
  _env_write off
  [ "$(backend_socks)" = ":" ]
  rm -rf "$d"
}

@test "parse_proxy rejects a non-numeric port" {
  run parse_proxy 'host:notaport'
  [ "$status" -ne 0 ]
}

@test "cmd_run exports the proxy environment and passes args through" {
  relay_is_active() { return 0; }
  LOCAL_PORT=1081
  IGNORE_HOSTS="localhost,127.0.0.0/8, ::1"
  [ "$(cmd_run sh -c 'echo "$all_proxy"')" = "socks5h://127.0.0.1:1081" ]
  [ "$(cmd_run sh -c 'echo "$HTTPS_PROXY"')" = "socks5h://127.0.0.1:1081" ]
  [ "$(cmd_run sh -c 'echo "$no_proxy"')" = "localhost,127.0.0.0/8,::1" ]
  [ "$(cmd_run printf '%s|%s' a 'b c')" = "a|b c" ]
}

@test "cmd_run propagates the command's exit code" {
  relay_is_active() { return 0; }
  LOCAL_PORT=1081
  run cmd_run sh -c 'exit 42'
  [ "$status" -eq 42 ]
}

@test "free_port lands above the relay port" {
  LOCAL_PORT=49500
  local p; p="$(free_port)"
  [ -n "$p" ]
  [ "$p" -gt 49500 ]
}
