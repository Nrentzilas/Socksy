# socksy

[![tests](https://github.com/Nrentzilas/socksy/actions/workflows/tests.yml/badge.svg)](https://github.com/Nrentzilas/socksy/actions/workflows/tests.yml)
[![shellcheck](https://github.com/Nrentzilas/socksy/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Nrentzilas/socksy/actions/workflows/shellcheck.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**The easy way to run an authenticated SOCKS5 proxy system-wide on GNOME.**

Paste one proxy string. socksy handles the credentials, wires up GNOME, and
confirms your new exit IP, all in a single command.

![socksy demo showing install, applying an authenticated SOCKS5 proxy, and confirming the exit IP from the terminal](assets/demo.gif)

```bash
socksy set 'user:pass@host:port'
```

```
▸ upstream : user:***@eu.example.net:1080
▸ relay    : 127.0.0.1:1081
✔ proxy applied.
✔ exit IP: 41.45.55.53
```

---

## Why this exists

GNOME's built-in proxy settings **cannot send a SOCKS username and password**;
there are simply no fields for it. So if your provider gives you an
*authenticated* SOCKS5 proxy (very common for residential/mobile proxies), the
GNOME GUI is a dead end: apps connect, then get rejected.

socksy solves this the clean way:

```
  GNOME apps ──▶ 127.0.0.1:1081 ──▶ gost relay ──▶ your.proxy:1080
   (no auth)      (local, no auth)   (adds creds)   (authenticated)
```

A tiny local relay ([gost](https://github.com/go-gost/gost)) holds your
credentials and forwards traffic upstream. GNOME just points at the local relay.
You get system-wide, authenticated SOCKS5 with zero fuss.

## Features

- **One command** to apply, one to turn off. No config files to hand-edit.
- **Handles authentication** that GNOME can't do on its own.
- **Auto-installs** the `gost` relay on first use, with **SHA-256 verification** (no root needed).
- **Runs as a systemd user service**: survives logout, restarts on failure.
- **Saved profiles**: `socksy save work '...'` then `socksy use work`.
- **Sticky sessions**: `--sticky` / `--session <id>` to hold one exit IP.
- **Country builder**: `--country GR` tags the username for a geo-targeted exit.
- **SOCKS5 / HTTP / HTTPS upstreams**: `--type http` for proxies that aren't SOCKS.
- **Remote DNS**: `socksy dns on` stops Firefox DNS leaks.
- **LAN bypass**: `socksy bypass` manages the GNOME no-proxy list (localhost, `.local`, RFC1918).
- **Health watchdog**: `socksy watchdog on` auto-restarts the relay when the exit goes bad.
- **Live IP watch**: `socksy watch` loops the exit IP and flags every change.
- **Scriptable**: `socksy status --json` for status bars and automation.
- **Optional config file**: set your own defaults in `~/.config/socksy/config`.
- **Shell completions**: bash & zsh, including profile names.
- **Instant feedback**: every apply prints your real exit IP.
- **Clean off switch**: `socksy off` returns you to a direct connection.
- **No root. No system packages.** Everything lives under `~/.local` and `~/.config`.

## Requirements

- A **GNOME-based** desktop (Fedora, Ubuntu GNOME, Debian GNOME, etc.); it uses `gsettings`.
- `systemd` user services (standard on modern Linux).
- `curl` (to auto-download gost) and `bash`.

## Install

```bash
git clone https://github.com/Nrentzilas/socksy.git
cd socksy
./install.sh
```

That copies `socksy` into `~/.local/bin` and ensures it's on your `PATH`.
Restart your shell (or `source ~/.bashrc`) if the command isn't found yet.

## Usage

```bash
socksy set 'user:pass@host:port'    # apply a proxy now (auto-tests the exit IP)
socksy set --type http 'user:pass@host:port'   # HTTP/HTTPS upstream (default: socks5)
socksy set --country GR 'user:pass@host:port'  # tag the username for a GR exit
socksy on                           # re-apply the last proxy
socksy off                          # back to a direct connection
socksy status                       # what's active right now
socksy status --json                # machine-readable status (for scripts)
socksy test                         # print the current exit IP
socksy watch [seconds]              # live exit-IP loop (default 5s; flags changes)
socksy watchdog on|off|status       # auto-restart the relay when the exit goes bad

socksy dns on|off|status            # remote DNS for Firefox (see below)
socksy bypass list|add|rm|reset     # manage the GNOME no-proxy (ignore-hosts) list

socksy save <name> 'user:pass@..'   # remember a proxy under a name
socksy use  [<name>]                # apply a saved proxy (no name = last used)
socksy list                         # list saved proxies (passwords masked)
socksy rm   <name>                  # forget a saved proxy
```

No-auth proxies work too; just pass `host:port`.

### Config file (optional)

Set your own defaults in `~/.config/socksy/config` (simple `key = value` lines,
parsed, never executed). Recognised keys:

```ini
local_port      = 1081
gost_version    = v3.2.6
type            = socks5          # default upstream type: socks5 | http | https
session_keyword = -session-       # your provider's sticky-session keyword
country_keyword = -country-       # your provider's country keyword
ignore_hosts    = localhost,127.0.0.0/8,::1,*.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
health_interval = 30              # watchdog: probe the exit every N seconds
health_fails    = 2               # restart the relay after N consecutive failures
health_url      = https://api.ipify.org
```

Precedence is **environment variable → config file → built-in default**, so an
env var like `SOCKSY_LOCAL_PORT` still wins for one-off overrides.

### Health watchdog

Rotating residential proxies occasionally hand you a dead exit node. Turn on the
watchdog and socksy will notice and reconnect for you:

```bash
socksy watchdog on       # probe the exit every 30s; restart the relay after 2 fails
socksy watchdog status   # is it on, and what did the last check see?
socksy watchdog off
```

It runs as a systemd user timer, so it keeps working after logout. When the
proxy is off (`socksy off`) the watchdog automatically stands down and resumes
once you turn a proxy back on. Tune the cadence with `health_interval` /
`health_fails` in the config file.

### Sticky sessions (keep the same IP)

Rotating proxies hand you a new exit IP on every connection. To pin one:

```bash
socksy set --sticky 'user-country-GR:secret@host:1080'      # random session tag
socksy set --session home1 'user-country-GR:secret@host:1080'  # reuse a fixed tag
```

socksy appends a session tag to your username (default keyword `-session-`).
**Your provider must recognise that keyword.** Check their docs and, if it
differs, override it:

```bash
export SOCKSY_SESSION_KEYWORD='-sessid-'
```

### Browsers & DNS

Point Firefox/Chrome at **"Use system proxy settings"** to follow socksy.

DNS posture with the relay:

| Client | DNS resolution | Leak? |
|---|---|---|
| CLI via `socks5h://` | at the exit (remote) | no |
| GNOME / GIO apps | hostname passed to SOCKS | no |
| Chrome + SOCKS5 | remote by default | no |
| **Firefox** | **local, unless configured** | **yes** |

So `socksy dns on` flips Firefox's `network.proxy.socks_remote_dns` in every
profile (restart Firefox to apply); `socksy dns off` reverts it. Everything else
already resolves at the exit.

## How it's wired

| Piece | Location |
|---|---|
| `socksy` command | `~/.local/bin/socksy` |
| `gost` relay binary | `~/.local/bin/gost` |
| systemd user service | `~/.config/systemd/user/socksy-relay.service` |
| watchdog timer (opt-in) | `~/.config/systemd/user/socksy-watchdog.{service,timer}` |
| saved profiles | `~/.config/socksy/profiles` (chmod `600`) |
| optional config | `~/.config/socksy/config` |
| local relay listener | `127.0.0.1:1081` |

## Security notes

- Proxy credentials are stored **in plain text** in the systemd unit and the
  profiles file, both written with `600` permissions (only your user can read
  them). This is standard for local proxy setups, but don't commit these files
  or share them.
- socksy never sends your credentials anywhere except to the upstream proxy you
  specify.

## Uninstall

```bash
./uninstall.sh            # removes socksy + service, keeps gost & profiles
./uninstall.sh --purge    # also removes gost and saved profiles
```

## Roadmap

Still ahead:

- [ ] KDE / non-GNOME backends
- [ ] GUI / tray applet
- [ ] Packaging: `.rpm` / `.deb`

Contributions welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
