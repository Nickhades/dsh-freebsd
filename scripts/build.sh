#!/bin/sh
# Build dsh from upstream + this FreeBSD overlay.
#
# Usage: sh scripts/build.sh [options]
#   --tree DIR           build tree (default: .work/tree)
#   --from-local REPO    extract the pinned commit from a local git checkout
#                        (use when GitHub is unreachable)
#   --from-dir DIR       copy an already extracted upstream tree
#   --skip-install       reuse the tree's node_modules
#   --skip-build         stop after pnpm install
#   --no-verify          skip scripts/verify.sh
#   --registry URL       write a tree-local .npmrc with this registry
#   --node-disturl URL   node-gyp headers base (default https://nodejs.org/download/release)
#
# Environment:
#   DSH_WORK             work root (default <overlay>/.work)
#   DSH_ALLOW_LOCK_UPDATE=1  drop --frozen-lockfile when the lock does not match
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/lib.sh"
load_version "$ROOT/VERSION"

WORK=${DSH_WORK:-$ROOT/.work}
TREE=""
FROM_LOCAL=""
FROM_DIR=""
DO_INSTALL=1
DO_BUILD=1
DO_VERIFY=1
REGISTRY=${DSH_NPM_REGISTRY:-}
DISTURL=${DSH_NODE_DISTURL:-https://nodejs.org/download/release}

while [ $# -gt 0 ]; do
  case "$1" in
    --tree) TREE=$2; shift 2 ;;
    --from-local) FROM_LOCAL=$2; shift 2 ;;
    --from-dir) FROM_DIR=$2; shift 2 ;;
    --skip-install) DO_INSTALL=0; shift ;;
    --skip-build) DO_BUILD=0; shift ;;
    --no-verify) DO_VERIFY=0; shift ;;
    --registry) REGISTRY=$2; shift 2 ;;
    --node-disturl) DISTURL=$2; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
TREE=${TREE:-$WORK/tree}
LOGS="$WORK/logs"
mkdir -p "$WORK" "$LOGS"

# node-gyp invokes `make`; FreeBSD's /usr/bin/make is BSD make, so put a GNU
# make shim first on PATH instead of asking the operator to edit their shell.
if ! make --version 2>/dev/null | grep -q 'GNU Make'; then
  gmake_bin=$(command -v gmake 2>/dev/null || true)
  [ -n "$gmake_bin" ] || die "GNU make is required (pkg install gmake)"
  mkdir -p "$WORK/shim"
  ln -sf "$gmake_bin" "$WORK/shim/make"
  PATH="$WORK/shim:$PATH"
  export PATH
  msg "prepended GNU make shim: $WORK/shim/make -> $gmake_bin"
fi

msg "dsh FreeBSD overlay $OVERLAY_VERSION on upstream $UPSTREAM_TAG ($UPSTREAM_COMMIT)"
sh "$ROOT/scripts/check-prereqs.sh" || exit 1

if [ ! -f "$TREE/package.json" ]; then
  if [ -n "$FROM_LOCAL" ]; then
    sh "$ROOT/scripts/fetch-upstream.sh" --from-local "$FROM_LOCAL" "$TREE"
  elif [ -n "$FROM_DIR" ]; then
    sh "$ROOT/scripts/fetch-upstream.sh" --from-dir "$FROM_DIR" "$TREE"
  else
    sh "$ROOT/scripts/fetch-upstream.sh" "$TREE"
  fi
else
  msg "reusing build tree $TREE"
fi

sh "$ROOT/scripts/apply.sh" "$TREE"

if [ -n "$REGISTRY" ]; then
  {
    printf 'registry=%s\n' "$REGISTRY"
    printf 'disturl=%s\n' "$DISTURL"
  } > "$TREE/.npmrc"
  msg "wrote $TREE/.npmrc (registry=$REGISTRY)"
fi

store=$(pnpm store path 2>/dev/null || true)
if [ -n "$store" ] && [ -d "$store" ]; then
  tree_dev=$(device_of "$TREE")
  store_dev=$(device_of "$store")
  if [ "$tree_dev" != "$store_dev" ]; then
    warn "build tree and pnpm store are on different filesystems ($tree_dev vs $store_dev); pnpm will copy instead of hardlinking"
  fi
fi

if [ "$DO_INSTALL" -eq 1 ]; then
  log="$LOGS/install.log"
  msg "pnpm install (log: $log)"
  frozen="--frozen-lockfile"
  if [ "${DSH_ALLOW_LOCK_UPDATE:-0}" = "1" ]; then
    frozen=""
  fi
  if ! ( cd "$TREE" && npm_config_disturl="$DISTURL" pnpm install $frozen ) > "$log" 2>&1; then
    tail -80 "$log" >&2
    die "pnpm install failed (log: $log). If the lockfile is stale, rerun with DSH_ALLOW_LOCK_UPDATE=1."
  fi
  tail -5 "$log"
fi

if [ "$DO_BUILD" -eq 1 ]; then
  log="$LOGS/build.log"
  msg "pnpm run build (log: $log)"
  started=$(date +%s)
  # The tree is extracted from git archive and has no .git, so name the source
  # commit explicitly; scripts/client-build-environment.ts otherwise runs
  # git rev-parse HEAD and aborts the build.
  if ! ( cd "$TREE" && DSH_CLIENT_COMMIT_HASH="$UPSTREAM_COMMIT" pnpm run build ) > "$log" 2>&1; then
    tail -100 "$log" >&2
    die "build failed (log: $log)"
  fi
  msg "build finished in $(( $(date +%s) - started ))s"
  tail -5 "$log"
fi

if [ "$DO_VERIFY" -eq 1 ]; then
  sh "$ROOT/scripts/verify.sh" "$TREE"
fi
msg "done: $TREE"
