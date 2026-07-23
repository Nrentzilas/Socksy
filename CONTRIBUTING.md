# Contributing to socksy

Thanks for helping make socksy better! It's a small, single-file Bash tool, so
contributing is easy.

## Ground rules

- Keep it **dependency-light**: Bash + `gsettings` + `systemctl` + `curl`. Don't
  pull in heavy runtimes.
- Keep it **user-friendly**: clear messages, sensible defaults, predictable behavior.
- Keep it **rootless**: everything under `~/.local` and `~/.config`.

## Before you open a PR

1. Run [ShellCheck](https://www.shellcheck.net/); CI runs it too:
   ```bash
   shellcheck bin/socksy install.sh uninstall.sh
   ```
2. Run the unit tests (no dependencies needed; CI runs these too):
   ```bash
   bash test/run.sh          # dependency-free runner
   bats test/                # optional, if you have bats-core
   ```
   The tests source the script as a library via `SOCKSY_LIB=1`, so they exercise
   the parsing/tagging logic without touching GNOME, systemd, or the network.
   Add a case when you touch that logic.
3. Test the happy path on a GNOME machine:
   ```bash
   ./install.sh
   socksy set 'user:pass@host:port'
   socksy status && socksy test
   socksy off
   ```
4. If you change behavior, update `README.md`, the `--help` text, and
   `man/socksy.1`.

## Ideas to pick up

See the **Roadmap** in the [README](README.md#roadmap) and the open
[issues](https://github.com/Nrentzilas/socksy/issues). Good first issues:
KDE / non-GNOME backend support, `.deb`/`.rpm` packaging, or porting more of
`test/run.sh` into additional coverage.

## Commit style

Short, imperative subject lines ("add dns toggle", "fix profile parsing").
