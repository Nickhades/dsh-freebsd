#!/bin/sh
# Shared helpers for the dsh FreeBSD overlay scripts. Source it; do not run it.

msg() { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Load the pinned upstream identity from VERSION.
load_version() {
  _version_file=$1
  [ -f "$_version_file" ] || die "missing $_version_file"
  . "$_version_file"
  [ -n "${UPSTREAM_TAG:-}" ] || die "UPSTREAM_TAG missing from $_version_file"
  [ -n "${UPSTREAM_COMMIT:-}" ] || die "UPSTREAM_COMMIT missing from $_version_file"
}

# True when dot-separated numeric version $1 is greater than or equal to $2.
version_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, x, "."); nb = split(b, y, ".");
    n = (na > nb ? na : nb);
    for (i = 1; i <= n; i++) {
      if ((x[i] + 0) > (y[i] + 0)) exit 0;
      if ((x[i] + 0) < (y[i] + 0)) exit 1;
    }
    exit 0;
  }'
}

# Filesystem device number of a path, to keep the pnpm store and the build tree
# on one filesystem (pnpm hardlinks from the store and falls back to
# re-downloading across devices).
device_of() { stat -f %d "$1" 2>/dev/null || printf 'unknown\n'; }
