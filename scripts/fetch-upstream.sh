#!/bin/sh
# Fetch the pinned upstream revision into a build tree.
#
# Usage:
#   sh scripts/fetch-upstream.sh [--from-local <checkout>] [--from-dir <dir>] [dest]
#
# Without --from-local/--from-dir the script clones UPSTREAM_REPO at
# UPSTREAM_TAG (GitHub is unreachable from some networks; point
# DSH_UPSTREAM_REPO at a mirror or use a local checkout instead).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/lib.sh"
load_version "$ROOT/VERSION"

FROM_LOCAL=""
FROM_DIR=""
DEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from-local) FROM_LOCAL=$2; shift 2 ;;
    --from-dir) FROM_DIR=$2; shift 2 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    -*) die "unknown option: $1" ;;
    *) DEST=$1; shift ;;
  esac
done
DEST="${DEST:-$ROOT/.work/upstream}"

if [ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
  die "$DEST is not empty; remove it or pass another destination"
fi
mkdir -p "$DEST"

if [ -n "$FROM_LOCAL" ]; then
  msg "extracting $UPSTREAM_COMMIT from local checkout $FROM_LOCAL"
  git -C "$FROM_LOCAL" cat-file -e "$UPSTREAM_COMMIT^{commit}" 2>/dev/null \
    || die "$FROM_LOCAL does not contain commit $UPSTREAM_COMMIT"
  git -C "$FROM_LOCAL" archive "$UPSTREAM_COMMIT" | tar -xf - -C "$DEST" \
    || die "git archive failed"
elif [ -n "$FROM_DIR" ]; then
  msg "copying upstream tree from $FROM_DIR"
  ( cd "$FROM_DIR" && tar -cf - --exclude .git . ) | ( cd "$DEST" && tar -xf - ) \
    || die "copy failed"
else
  repo=${DSH_UPSTREAM_REPO:-$UPSTREAM_REPO}
  msg "cloning $repo at $UPSTREAM_TAG"
  if ! git clone --quiet --depth 1 --branch "$UPSTREAM_TAG" "$repo" "$DEST"; then
    die "clone failed. GitHub is blocked on some networks: use --from-local <checkout>, or set DSH_UPSTREAM_REPO to a mirror"
  fi
  got=$(git -C "$DEST" rev-parse HEAD)
  if [ "$got" != "$UPSTREAM_COMMIT" ]; then
    die "tag $UPSTREAM_TAG points at $got, expected $UPSTREAM_COMMIT; update VERSION after reviewing the difference"
  fi
fi

printf '%s\n' "$UPSTREAM_COMMIT" > "$DEST/.dsh-upstream-commit"
msg "upstream tree ready at $DEST ($UPSTREAM_TAG)"
