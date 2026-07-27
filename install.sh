#!/usr/bin/env bash
#
# socksy installer.
#
# By default this is a rootless install into ~/.local, and it makes sure
# ~/.local/bin is on your PATH. Pass --prefix to install somewhere else, and
# --destdir to stage the files into a build root (used by the packaging targets,
# which install to /usr and must never touch a user's dotfiles).
#
#   ./install.sh                                  rootless, into ~/.local
#   ./install.sh --prefix /usr/local              system-wide
#   DESTDIR=/tmp/pkg ./install.sh --prefix /usr   stage for a .deb/.rpm
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREFIX="${PREFIX:-$HOME/.local}"
DESTDIR="${DESTDIR:-}"
EDIT_PATH="auto"     # auto | never

usage() {
  cat <<'EOF'
usage: install.sh [--prefix DIR] [--destdir DIR] [--no-path] [-h|--help]

  --prefix DIR   install root for the files themselves (default: ~/.local)
  --destdir DIR  staging root prepended to every path (default: none)
  --no-path      never edit ~/.bashrc or ~/.zshrc to extend PATH
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)  PREFIX="${2:?--prefix needs a directory}"; shift 2 ;;
    --prefix=*) PREFIX="${1#*=}"; shift ;;
    --destdir) DESTDIR="${2:?--destdir needs a directory}"; shift 2 ;;
    --destdir=*) DESTDIR="${1#*=}"; shift ;;
    --no-path) EDIT_PATH="never"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

SRC="$ROOT/bin/socksy"
[ -f "$SRC" ] || { echo "error: cannot find $SRC" >&2; exit 1; }

# Completions and man pages belong under $PREFIX/share for both a ~/.local
# install and a /usr one, so a single set of paths covers every case.
BIN_DIR="$DESTDIR$PREFIX/bin"
BASH_COMP_DIR="$DESTDIR$PREFIX/share/bash-completion/completions"
ZSH_COMP_DIR="$DESTDIR$PREFIX/share/zsh/site-functions"
MAN_DIR="$DESTDIR$PREFIX/share/man/man1"

install -d "$BIN_DIR"
install -m 755 "$SRC" "$BIN_DIR/socksy"
echo "installed: $BIN_DIR/socksy"

if [ -f "$ROOT/completions/socksy.bash" ]; then
  install -d "$BASH_COMP_DIR"
  install -m 644 "$ROOT/completions/socksy.bash" "$BASH_COMP_DIR/socksy"
  echo "installed: bash completion ($BASH_COMP_DIR/socksy)"
fi
if [ -f "$ROOT/completions/socksy.zsh" ]; then
  install -d "$ZSH_COMP_DIR"
  install -m 644 "$ROOT/completions/socksy.zsh" "$ZSH_COMP_DIR/_socksy"
  echo "installed: zsh completion ($ZSH_COMP_DIR/_socksy)"
  echo "  (zsh users: ensure 'fpath+=($PREFIX/share/zsh/site-functions)' is set before compinit)"
fi

if [ -f "$ROOT/man/socksy.1" ]; then
  install -d "$MAN_DIR"
  install -m 644 "$ROOT/man/socksy.1" "$MAN_DIR/socksy.1"
  echo "installed man page: $MAN_DIR/socksy.1 (run 'man socksy')"
fi

# PATH help only makes sense for a real (non-staged) install into the default
# rootless prefix. A packaging run stages files and must leave dotfiles alone; a
# system prefix is already on PATH.
if [ "$EDIT_PATH" = "auto" ] && [ -z "$DESTDIR" ] && [ "$PREFIX" = "$HOME/.local" ]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *)
      for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -f "$rc" ] || continue
        grep -q 'HOME/.local/bin' "$rc" && continue
        # shellcheck disable=SC2016  # $HOME must stay literal so it expands at shell startup, not now
        printf '\n# added by socksy installer\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
        echo "added ~/.local/bin to PATH in $rc (restart your shell to pick it up)"
      done
      ;;
  esac
fi

if [ -z "$DESTDIR" ]; then
  echo
  echo "done! try:  socksy --help"
  echo "then:       socksy set 'user:pass@host:port'"
fi
