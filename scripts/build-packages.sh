#!/usr/bin/env bash
#
# Build the socksy .deb and .rpm.
#
# The release workflow calls this, but it runs anywhere nfpm does, so a package
# can be reproduced and inspected locally before any tag is pushed:
#
#   scripts/build-packages.sh              version from bin/socksy, into ./dist
#   scripts/build-packages.sh --check v0.5.0
#
# --check compares a tag against the VERSION baked into bin/socksy and fails on
# a mismatch, exactly as build-release.sh does, so a published package can never
# claim a different version than the binary inside it. A prerelease suffix is
# kept for the package version (v0.6.0-rc1 -> 0.6.0~rc1 on deb, which sorts
# before 0.6.0) but ignored when comparing against VERSION.
#
# The payload is staged by running install.sh with a DESTDIR rather than by
# listing files here, so the packages and a from-source install can never drift
# apart: whatever install.sh puts under /usr is what the package contains.
#
# nfpm is pure Go and writes the archives itself, so no dpkg or rpmbuild is
# needed and this works on any OS.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/dist"
CONFIG="$ROOT/packaging/nfpm.yaml"
TAG=""

usage() {
  cat <<'USAGE'
usage: build-packages.sh [--check TAG] [--out DIR] [-h|--help]

  --check TAG  verify TAG matches VERSION in bin/socksy, then build
  --out DIR    output directory (default: ./dist)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check)   TAG="${2:?--check needs a tag}"; shift 2 ;;
    --check=*) TAG="${1#*=}"; shift ;;
    --out)     OUT="${2:?--out needs a directory}"; shift 2 ;;
    --out=*)   OUT="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

command -v nfpm >/dev/null 2>&1 || {
  echo "error: nfpm not found on PATH." >&2
  echo "Install it with:  go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.47.0" >&2
  exit 1
}

# Same single source of truth for the version as build-release.sh.
VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$ROOT/bin/socksy")"
[ -n "$VERSION" ] || { echo "error: could not read VERSION from bin/socksy" >&2; exit 1; }

PKG_VERSION="$VERSION"
if [ -n "$TAG" ]; then
  full="${TAG#v}"       # v0.6.0-rc1 -> 0.6.0-rc1
  base="${full%%-*}"    # 0.6.0-rc1  -> 0.6.0
  if [ "$base" != "$VERSION" ]; then
    echo "error: tag '$TAG' implies version '$base', but bin/socksy says '$VERSION'." >&2
    echo "Bump VERSION in bin/socksy (and the .TH line in man/socksy.1) to match." >&2
    exit 1
  fi
  echo "version check: tag '$TAG' matches VERSION '$VERSION'"
  PKG_VERSION="$full"   # keep the prerelease suffix for the package version
fi

# Stage the payload exactly as an install into /usr would lay it out. --no-path
# is belt and braces: install.sh already leaves dotfiles alone under a DESTDIR.
#
# The staging directory is fixed under the repo rather than following --out:
# nfpm does not expand variables in a config's file list, so the config names
# this path literally and nfpm is run from the repo root. --out still decides
# where the finished packages land.
STAGE="$ROOT/dist/pkgroot"
rm -rf "$STAGE"
mkdir -p "$OUT"

# Clear out packages from an earlier run so a stale version cannot survive into
# SHA256SUMS below. The tarball is left alone: build-release.sh owns that one,
# and a release builds it first.
rm -f "$OUT"/socksy*.deb "$OUT"/socksy*.rpm

DESTDIR="$STAGE" "$ROOT/install.sh" --prefix /usr --no-path >/dev/null

# Both ecosystems ship man pages compressed, and man reads .1.gz on either.
# -n keeps the name and timestamp out of the gzip header, so the payload stays
# byte-identical between builds of the same tree.
gzip -9n "$STAGE/usr/share/man/man1/socksy.1"

# Docs are a packaging convention rather than part of an install, so they are
# staged here instead of in install.sh.
install -d "$STAGE/usr/share/doc/socksy"
install -m 644 "$ROOT/README.md" "$STAGE/usr/share/doc/socksy/README.md"
install -m 644 "$ROOT/LICENSE"   "$STAGE/usr/share/doc/socksy/LICENSE"

# nfpm has no flag for the version and does not expand variables in the config,
# so the one field that varies per build is rendered in here.
GENERATED="$ROOT/dist/nfpm.generated.yaml"
sed "s|@VERSION@|$PKG_VERSION|" "$CONFIG" > "$GENERATED"

# Pin every mtime nfpm records to the last commit (or now, outside a git
# checkout), for the same reason the tarball does it: two builds of the same
# tree then produce the same checksum.
SOURCE_DATE_EPOCH="$(git -C "$ROOT" log -1 --pretty=%ct 2>/dev/null || date +%s)"
export SOURCE_DATE_EPOCH

# From the repo root, so the relative paths in the config resolve.
cd "$ROOT"
for packager in deb rpm; do
  nfpm package --config "$GENERATED" --packager "$packager" --target "$OUT"
done

rm -rf "$STAGE" "$GENERATED"

# One checksum file covers every artifact in the output directory, so a release
# that builds the tarball first and the packages second ends up with a single
# SHA256SUMS listing all three. Bare filenames keep 'sha256sum -c' working from
# inside the directory.
shopt -s nullglob
cd "$OUT"
artifacts=( socksy-*.tar.gz socksy*.deb socksy*.rpm )
[ ${#artifacts[@]} -gt 0 ] || { echo "error: nfpm produced no packages" >&2; exit 1; }
sha256sum "${artifacts[@]}" > SHA256SUMS

echo "built:"
printf '  %s\n' "${artifacts[@]}"
echo "checksums:"
sed 's/^/  /' SHA256SUMS
