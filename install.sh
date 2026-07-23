#!/usr/bin/env bash
#
# socksy installer that copies the `socksy` command into ~/.local/bin and makes
# sure that directory is on your PATH. No root required.
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin/socksy"
DEST="$HOME/.local/bin/socksy"

[ -f "$SRC" ] || { echo "error: cannot find $SRC" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$HOME/.local/bin"
install -m 755 "$SRC" "$DEST"
echo "installed: $DEST"

# shell completions (best-effort)
BASH_COMP_DIR="$HOME/.local/share/bash-completion/completions"
ZSH_COMP_DIR="$HOME/.local/share/zsh/site-functions"
if [ -f "$ROOT/completions/socksy.bash" ]; then
  mkdir -p "$BASH_COMP_DIR"
  install -m 644 "$ROOT/completions/socksy.bash" "$BASH_COMP_DIR/socksy"
  echo "installed: bash completion ($BASH_COMP_DIR/socksy)"
fi
if [ -f "$ROOT/completions/socksy.zsh" ]; then
  mkdir -p "$ZSH_COMP_DIR"
  install -m 644 "$ROOT/completions/socksy.zsh" "$ZSH_COMP_DIR/_socksy"
  echo "installed: zsh completion ($ZSH_COMP_DIR/_socksy)"
  echo "  (zsh users: ensure 'fpath+=($ZSH_COMP_DIR)' is set before compinit)"
fi

# man page (best-effort)
MAN_DIR="$HOME/.local/share/man/man1"
if [ -f "$ROOT/man/socksy.1" ]; then
  mkdir -p "$MAN_DIR"
  install -m 644 "$ROOT/man/socksy.1" "$MAN_DIR/socksy.1"
  echo "installed man page: $MAN_DIR/socksy.1 (run 'man socksy')"
fi

# ensure ~/.local/bin is on PATH for future shells
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

echo
echo "done! try:  socksy --help"
echo "then:       socksy set 'user:pass@host:port'"
