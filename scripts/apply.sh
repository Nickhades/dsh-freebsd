#!/bin/sh
# Apply the FreeBSD overlay to an upstream tree: apply the patch series in
# order, then copy the files this overlay owns.
#
# Usage: sh scripts/apply.sh <tree>
# The tree must be a pristine upstream checkout at UPSTREAM_COMMIT. A tree that
# already carries this overlay revision is left untouched.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/lib.sh"
load_version "$ROOT/VERSION"

TREE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) TREE=$1; shift ;;
  esac
done
[ -n "$TREE" ] || die "usage: sh scripts/apply.sh <tree>"
[ -d "$TREE" ] || die "$TREE does not exist"
[ -f "$TREE/package.json" ] || die "$TREE/package.json is missing; point at an upstream checkout"
grep -q '"@deepseek-ai/dsh-root"' "$TREE/package.json" \
  || die "$TREE is not a deepseek-harness checkout"

MARKER="$TREE/.dsh-freebsd-overlay"
WANT="overlay=$OVERLAY_VERSION upstream=$UPSTREAM_COMMIT"
if [ -f "$MARKER" ]; then
  have=$(cat "$MARKER")
  if [ "$have" = "$WANT" ]; then
    msg "overlay $OVERLAY_VERSION is already applied to $TREE"
    exit 0
  fi
  die "$TREE carries a different overlay ($have); use a fresh tree instead of stacking overlays"
fi

# Check the whole series before mutating, so a moved upstream file is reported
# without leaving a half-patched tree.
if command -v git >/dev/null 2>&1; then
  # The build tree usually sits inside this overlay's own git repository. A
  # plain `git apply` there discovers the outer repository and silently skips
  # every patch whose paths lack the caller's prefix, so pin discovery to the
  # tree's parent: the tree is then either its own repository or no repository.
  TREE_ABS=$(CDPATH= cd -- "$TREE" && pwd)
  GIT_CEILING="${TREE_ABS%/*}"
  while IFS='	' read -r name paths; do
    case "$name" in ''|'#'*) continue ;; esac
    ( cd "$TREE" && GIT_CEILING_DIRECTORIES="$GIT_CEILING" git apply --check --whitespace=nowarn "$ROOT/patches/$name" ) \
      || die "$name does not apply to this tree: upstream likely moved the code. Rebase the overlay (see README, 'Updating to a new upstream release')."
  done < "$ROOT/patches/series"
else
  while IFS='	' read -r name paths; do
    case "$name" in ''|'#'*) continue ;; esac
    ( cd "$TREE" && patch -p1 -E --dry-run -s < "$ROOT/patches/$name" ) \
      || die "$name does not apply to this tree (patch dry-run failed)"
  done < "$ROOT/patches/series"
fi

count=0
while IFS='	' read -r name paths; do
  case "$name" in ''|'#'*) continue ;; esac
  if command -v git >/dev/null 2>&1; then
    ( cd "$TREE" && GIT_CEILING_DIRECTORIES="$GIT_CEILING" git apply --whitespace=nowarn "$ROOT/patches/$name" ) \
      || die "applying $name failed"
  else
    ( cd "$TREE" && patch -p1 -E -s < "$ROOT/patches/$name" ) \
      || die "applying $name failed"
  fi
  count=$((count + 1))
done < "$ROOT/patches/series"

msg "copying overlay files"
( cd "$ROOT/overlay" && tar -cf - . ) | ( cd "$TREE" && tar -xf - ) \
  || die "copying the overlay tree failed"

printf '%s\n' "$WANT" > "$MARKER"
msg "applied $count patches and overlay $OVERLAY_VERSION to $TREE"
