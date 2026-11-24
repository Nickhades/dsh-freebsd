#!/bin/sh
# Regenerate patches/ and overlay/ from a git tree that carries this overlay on
# top of the pinned upstream commit.
#
# Usage: sh scripts/regen.sh <git-tree> [--check]
#   --check   do not write; fail when patches/ or overlay/ are stale.
#
# Maintainer loop for a new upstream release:
#   1. edit VERSION to the new tag/commit
#   2. fetch-upstream.sh, then apply.sh (or copy the previous tree)
#   3. resolve conflicts, commit the result in the tree
#   4. regen.sh <tree>   -> new patch series + overlay files
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/lib.sh"
load_version "$ROOT/VERSION"

TREE=${1:-}
MODE=${2:-}
[ -n "$TREE" ] || die "usage: sh scripts/regen.sh <git-tree> [--check]"
[ -d "$TREE/.git" ] || die "$TREE is not a git repository"
check=0
[ "$MODE" = "--check" ] && check=1

if [ -n "$(git -C "$TREE" status --porcelain)" ]; then
  die "$TREE has uncommitted changes; commit or discard them first"
fi
git -C "$TREE" merge-base --is-ancestor "$UPSTREAM_COMMIT" HEAD \
  || die "$UPSTREAM_COMMIT is not an ancestor of $TREE HEAD"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/dsh-regen.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

while IFS='	' read -r name paths; do
  case "$name" in ''|'#'*) continue ;; esac
  # Word splitting is intentional: the series file lists git pathspecs.
  # shellcheck disable=SC2086
  git -C "$TREE" diff --no-color --binary "$UPSTREAM_COMMIT" HEAD -- $paths > "$tmp/$name"
  if [ "$check" -eq 1 ]; then
    if ! cmp -s "$tmp/$name" "$ROOT/patches/$name"; then
      diff -u "$ROOT/patches/$name" "$tmp/$name" | head -60 || true
      die "$name is stale; run without --check to regenerate"
    fi
  else
    mv "$tmp/$name" "$ROOT/patches/$name"
    msg "regenerated patches/$name"
  fi
done < "$ROOT/patches/series"

while IFS= read -r rel; do
  case "$rel" in ''|'#'*) continue ;; esac
  [ -f "$TREE/$rel" ] || die "missing $rel in $TREE"
  if [ "$check" -eq 1 ]; then
    cmp -s "$TREE/$rel" "$ROOT/overlay/$rel" || die "overlay/$rel is stale; run without --check"
  else
    mkdir -p "$ROOT/overlay/$(dirname "$rel")"
    cp "$TREE/$rel" "$ROOT/overlay/$rel"
  fi
done < "$ROOT/scripts/overlay-files.txt"

if [ "$check" -eq 1 ]; then
  msg "patches and overlay are current"
else
  msg "patches and overlay regenerated from $TREE"
fi
