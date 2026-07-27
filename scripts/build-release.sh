#!/usr/bin/env bash
#
# Build the socksy release tarball and its checksum file.
#
# The release workflow calls this, but it runs anywhere, so a release can be
# reproduced and inspected locally before any tag is pushed:
#
#   scripts/build-release.sh              version from bin/socksy, into ./dist
#   scripts/build-release.sh --check v0.3.0-rc1
#
# --check compares a tag against the VERSION baked into bin/socksy and fails on
# a mismatch, so a release can never ship a binary claiming a different version.
# A prerelease suffix is ignored for that comparison: v0.3.0-rc1 matches 0.3.0.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/dist"
TAG=""

usage() {
  cat <<'EOF'
usage: build-release.sh [--check TAG] [--out DIR] [-h|--help]

  --check TAG  verify TAG matches VERSION in bin/socksy, then build
  --out DIR    output directory (default: ./dist)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check)  TAG="${2:?--check needs a tag}"; shift 2 ;;
    --check=*) TAG="${1#*=}"; shift ;;
    --out)    OUT="${2:?--out needs a directory}"; shift 2 ;;
    --out=*)  OUT="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

# Single source of truth for the version.
VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$ROOT/bin/socksy")"
[ -n "$VERSION" ] || { echo "error: could not read VERSION from bin/socksy" >&2; exit 1; }

if [ -n "$TAG" ]; then
  base="${TAG#v}"      # v0.3.0-rc1 -> 0.3.0-rc1
  base="${base%%-*}"   # 0.3.0-rc1  -> 0.3.0
  if [ "$base" != "$VERSION" ]; then
    echo "error: tag '$TAG' implies version '$base', but bin/socksy says '$VERSION'." >&2
    echo "Bump VERSION in bin/socksy (and the .TH line in man/socksy.1) to match." >&2
    exit 1
  fi
  echo "version check: tag '$TAG' matches VERSION '$VERSION'"
fi

NAME="socksy-$VERSION"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Everything a user needs to install from the tarball, and nothing else. The
# test suite and CI config are deliberately left out: this is a release
# artifact, not a source snapshot.
install -d "$STAGE/$NAME/bin" "$STAGE/$NAME/completions" "$STAGE/$NAME/man"
install -m 755 "$ROOT/bin/socksy"             "$STAGE/$NAME/bin/socksy"
install -m 755 "$ROOT/install.sh"             "$STAGE/$NAME/install.sh"
install -m 755 "$ROOT/uninstall.sh"           "$STAGE/$NAME/uninstall.sh"
install -m 644 "$ROOT/completions/socksy.bash" "$STAGE/$NAME/completions/socksy.bash"
install -m 644 "$ROOT/completions/socksy.zsh"  "$STAGE/$NAME/completions/socksy.zsh"
install -m 644 "$ROOT/man/socksy.1"           "$STAGE/$NAME/man/socksy.1"
install -m 644 "$ROOT/README.md"              "$STAGE/$NAME/README.md"
install -m 644 "$ROOT/LICENSE"                "$STAGE/$NAME/LICENSE"

mkdir -p "$OUT"
TARBALL="$OUT/$NAME.tar.gz"

# Deterministic: fixed owner, sorted entries, and mtimes pinned to the last
# commit (or now, outside a git checkout). Two builds of the same tree then
# produce the same checksum, which makes the published SHA256SUMS verifiable by
# anyone who rebuilds it.
SOURCE_EPOCH="$(git -C "$ROOT" log -1 --pretty=%ct 2>/dev/null || date +%s)"
tar --sort=name \
    --owner=0 --group=0 --numeric-owner \
    --mtime="@$SOURCE_EPOCH" \
    -czf "$TARBALL" -C "$STAGE" "$NAME"

# Checksum file lists bare filenames so 'sha256sum -c' works from the same dir.
( cd "$OUT" && sha256sum "$NAME.tar.gz" > SHA256SUMS )

echo "built:    $TARBALL"
echo "checksum: $(cat "$OUT/SHA256SUMS")"
echo "contents:"
tar -tzf "$TARBALL" | sed 's/^/  /'
