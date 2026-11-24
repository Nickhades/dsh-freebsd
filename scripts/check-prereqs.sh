#!/bin/sh
# Check that this host can build dsh with the FreeBSD overlay.
#
# Usage: sh scripts/check-prereqs.sh
# Exit:  0 when every hard prerequisite is present, 1 otherwise.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/lib.sh"
load_version "$ROOT/VERSION"

fail=0
ok()   { printf '  [ok]  %s\n' "$*"; }
note() { printf '  [--]  %s\n' "$*"; }
bad()  { printf '  [!!]  %s\n' "$*" >&2; fail=1; }

msg "host: $(uname -s) $(uname -r) $(uname -m)"

[ "$(uname -s)" = "FreeBSD" ] || bad "this overlay targets FreeBSD; found $(uname -s)"

fbv=$(freebsd-version -u 2>/dev/null || true)
[ -n "$fbv" ] || fbv=$(uname -r)
major=${fbv%%.*}
case "$major" in
  ''|*[!0-9]*) bad "cannot determine the FreeBSD version from '$fbv'" ;;
  *)
    if [ "$major" -ge "$MIN_FREEBSD_MAJOR" ]; then
      ok "FreeBSD $fbv (>= $MIN_FREEBSD_MAJOR required)"
    else
      bad "FreeBSD $fbv is older than $MIN_FREEBSD_MAJOR; use a 15.x or newer host"
    fi
    ;;
esac

missing=""
for c in node pnpm bash gmake python3 pkgconf cc curl; do
  command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
done
if [ -n "$missing" ]; then
  bad "missing commands:$missing"
  note "install: pkg install node24 npm-node24 gmake python3 pkgconf bash ripgrep"
else
  ok "required commands present"
fi

if command -v node >/dev/null 2>&1; then
  nodev=$(node -p 'process.versions.node' 2>/dev/null || true)
  if [ -z "$nodev" ]; then
    bad "node does not run; reinstall node24"
  elif version_ge "$nodev" "$MIN_NODE_VERSION"; then
    ok "node $nodev"
    if ! version_ge "$nodev" "$RECOMMENDED_NODE_VERSION"; then
      note "node $nodev is below upstream engines >= $RECOMMENDED_NODE_VERSION; the build works on 22.x with an 'Unsupported engine' warning"
    fi
  else
    bad "node $nodev is older than $MIN_NODE_VERSION; install www/node24"
  fi
fi

if command -v pnpm >/dev/null 2>&1; then
  ok "pnpm $(pnpm -v 2>/dev/null)"
  note "if pnpm install fails with 'Cannot verify the identity of the @pnpm/exe.freebsd-x64 native binary', pnpm came from corepack; reinstall it with 'npm install -g pnpm@11.28.5'"
fi

if command -v make >/dev/null 2>&1 && make --version 2>/dev/null | grep -q 'GNU Make'; then
  ok "$(make --version 2>/dev/null | head -1)"
elif command -v gmake >/dev/null 2>&1; then
  note "'make' is BSD make; scripts/build.sh prepends a GNU make shim for node-gyp"
else
  bad "GNU make is missing (node-gyp needs it): pkg install gmake"
fi

if command -v rg >/dev/null 2>&1; then
  ok "ripgrep $(rg --version 2>/dev/null | head -1)"
else
  note "ripgrep (rg) is missing; the grep/glob tools fall back to the system rg on FreeBSD. Install with: pkg install ripgrep"
fi

mem=$(sysctl -n hw.physmem 2>/dev/null || printf '0')
if [ "$mem" -gt 0 ] && [ "$mem" -lt 8000000000 ]; then
  note "only $((mem / 1024 / 1024)) MiB RAM; the client bundle needs an 8 GiB V8 heap and may be killed"
fi

if [ "$fail" -ne 0 ]; then
  die "prerequisites are incomplete"
fi
msg "prerequisites OK"
