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

@test "json_esc escapes quotes" {
  [ "$(json_esc 'a"b')" = 'a\"b' ]
}

@test "parse_proxy rejects a non-numeric port" {
  run parse_proxy 'host:notaport'
  [ "$status" -ne 0 ]
}
