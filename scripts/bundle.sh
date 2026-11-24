#!/bin/sh
# Produce a self-contained FreeBSD runtime bundle from a built tree. The output
# has the same shape as the port distfile: one top-level directory holding the
# deployed CLI, the production dependency closure, the web UI, and the jail
# helper source.
#
# Usage: sh scripts/bundle.sh [tree] [version]
#   tree     build tree (default .work/tree)
#   version  bundle version (default the tree's package.json version)
#
# Outputs under .work/dist/: deepseek-harness-<version>-freebsd-amd64.tar.gz,
# distinfo.fragment, pkg-plist.fragment, smoke.log.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/lib.sh"
load_version "$ROOT/VERSION"

TREE=${1:-$ROOT/.work/tree}
[ -f "$TREE/package.json" ] || die "$TREE/package.json is missing; build a tree first"
VERSION=${2:-$( cd "$TREE" && node -p "require('./package.json').version" 2>/dev/null || true )}
[ -n "$VERSION" ] || die "cannot determine the bundle version"
WORK=${DSH_WORK:-$ROOT/.work}/dist
mkdir -p "$WORK"
TREE_ABS=$(CDPATH= cd -- "$TREE" && pwd)
GIT_CEILING_DIRECTORIES="${TREE_ABS%/*}"
export GIT_CEILING_DIRECTORIES

msg "bundling dsh $VERSION from $TREE"
# The distfile tool cd's into the repository before its fixups, so it needs an
# absolute path here (a relative one would resolve inside the deploy stage).
DSH_REPO="$TREE_ABS" DSH_WORK="$WORK" DSH_LOG="$ROOT/.work/logs/bundle.log" \
  sh "$ROOT/overlay/dsh-freebsd-port/tools/make-port-distfile.sh" "$VERSION"

TARBALL="$WORK/deepseek-harness-$VERSION-freebsd-amd64.tar.gz"
[ -f "$TARBALL" ] || die "bundle was not produced"
msg "bundle: $TARBALL ($(wc -c < "$TARBALL" | tr -d ' ') bytes)"
msg "fragments: $WORK/distinfo.fragment  $WORK/pkg-plist.fragment"
