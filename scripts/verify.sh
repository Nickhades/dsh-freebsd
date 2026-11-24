#!/bin/sh
# Verify a built dsh tree on FreeBSD: artifacts, CLI, jail helper compile, and
# a loopback web boot with a scratch HOME.
#
# Usage: sh scripts/verify.sh [tree] [--no-web] [--port N] [--tests]
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/lib.sh"
load_version "$ROOT/VERSION"

TREE=""
DO_WEB=1
DO_TESTS=0
PORT=${DSH_SMOKE_PORT:-3999}
while [ $# -gt 0 ]; do
  case "$1" in
    --no-web) DO_WEB=0; shift ;;
    --tests) DO_TESTS=1; shift ;;
    --port) PORT=$2; shift 2 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) TREE=$1; shift ;;
  esac
done
TREE=${TREE:-$ROOT/.work/tree}
[ -d "$TREE" ] || die "$TREE does not exist"
TREE_ABS=$(CDPATH= cd -- "$TREE" && pwd)
GIT_CEILING_DIRECTORIES="${TREE_ABS%/*}"
export GIT_CEILING_DIRECTORIES

failures=0
pass() { printf '  [PASS] %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*"; failures=$((failures + 1)); }

msg "verifying $TREE"

[ -s "$TREE/apps/cli/lib/bin.js" ] && pass "CLI artifact apps/cli/lib/bin.js" || fail "CLI artifact missing (pnpm run build)"
[ -f "$TREE/apps/web/dist/index.html" ] && pass "web UI artifact apps/web/dist/index.html" || fail "web UI artifact missing"
[ -s "$TREE/native/system/packages/freebsd-x64/bin/system.node" ] \
  && pass "FreeBSD flock addon system.node" \
  || fail "FreeBSD flock addon missing (pnpm run build:native-system)"
[ -f "$TREE/freebsd/dsh-jail-run.c" ] && pass "jail helper source freebsd/dsh-jail-run.c" || fail "jail helper source missing"

if [ -s "$TREE/apps/cli/lib/bin.js" ]; then
  ver=$( cd "$TREE" && node --expose-internals apps/cli/lib/bin.js --version 2>&1 ) || ver=""
  expected=$( cd "$TREE" && node -p "require('./package.json').version" 2>/dev/null ) || expected=""
  if [ -n "$ver" ] && [ "$ver" = "$expected" ]; then
    pass "CLI reports version $ver"
  else
    fail "CLI --version reported '$ver' (expected '$expected')"
  fi
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/dsh-verify.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

if [ -f "$TREE/freebsd/dsh-jail-run.c" ]; then
  if cc -O2 -Wall -o "$TMP/dsh-jail-run" "$TREE/freebsd/dsh-jail-run.c" -ljail > "$TMP/jail-build.log" 2>&1; then
    pass "jail helper compiles against libjail"
  else
    tail -20 "$TMP/jail-build.log" >&2
    fail "jail helper does not compile"
  fi
fi

if [ "$DO_TESTS" -eq 1 ]; then
  # The ripgrep stream tests exercise the packaged @vscode/ripgrep binary, which
  # does not exist for FreeBSD; the fallback behavior is covered by path.spec.ts.
  if ( cd "$TREE" && pnpm exec vitest run packages/util/ripgrep/tests/path.spec.ts packages/util/native-command packages/sandbox/sandbox-local/tests/local.spec.ts ) > "$TMP/tests.log" 2>&1; then
    pass "targeted unit tests"
  else
    tail -40 "$TMP/tests.log" >&2
    fail "targeted unit tests"
  fi
fi

if [ "$DO_WEB" -eq 1 ]; then
  mkdir -p "$TMP/home"
  web_log="$TMP/web.log"
  ( cd "$TREE" && HOME="$TMP/home" DSH_HOME="$TMP/home/.dsh" \
      node --expose-internals apps/cli/lib/bin.js web --host 127.0.0.1 --port "$PORT" --no-open ) \
      > "$web_log" 2>&1 &
  web_pid=$!
  token=""
  i=0
  while [ "$i" -lt 120 ]; do
    if ! kill -0 "$web_pid" 2>/dev/null; then break; fi
    token=$(grep -oE 'token=[A-Za-z0-9_-]+' "$web_log" 2>/dev/null | tail -1 | cut -d= -f2-)
    [ -n "$token" ] && break
    i=$((i + 1))
    sleep 1
  done
  if [ -z "$token" ]; then
    tail -40 "$web_log" >&2
    fail "web server did not print an auth token on 127.0.0.1:$PORT"
  else
    code=$(curl -s -L -c "$TMP/cookies" -o /dev/null -w '%{http_code}' \
      "http://127.0.0.1:$PORT/?token=$token" 2>/dev/null || printf '000')
    if [ "$code" = "200" ]; then
      pass "web UI answers HTTP 200 on loopback:$PORT"
    else
      tail -20 "$web_log" >&2
      fail "web UI answered HTTP $code on loopback:$PORT"
    fi
  fi
  kill "$web_pid" 2>/dev/null || true
  wait "$web_pid" 2>/dev/null || true
fi

if [ "$failures" -ne 0 ]; then
  die "$failures verification check(s) failed"
fi
msg "verification passed"
