#!/bin/sh
# package-desktop.sh - build a self-contained FreeBSD desktop app tarball.
#
# The package carries the prebuilt WebKitGTK window, the launcher, the icon and
# the runtime bundle (pnpm deploy closure + web UI). Unpack it, then run
# install-desktop.sh; no root is required for the default ~/.local prefix.
#
# Usage: sh scripts/package-desktop.sh [bundle-tarball] [output-dir]
#   bundle-tarball  default: newest .work/dist/deepseek-harness-*-freebsd-amd64.tar.gz
#   output-dir      default: .work/desktop
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/lib.sh"
load_version "$ROOT/VERSION"

BUNDLE=${1:-}
OUT=${2:-$ROOT/.work/desktop}
if [ -z "$BUNDLE" ]; then
    BUNDLE=$(ls -t "$ROOT"/.work/dist/deepseek-harness-*-freebsd-amd64.tar.gz 2>/dev/null | head -1 || true)
fi
[ -n "$BUNDLE" ] && [ -f "$BUNDLE" ] || die "no runtime bundle; run: sh scripts/bundle.sh .work/tree-final"

MEMBER=$(tar -tzf "$BUNDLE" | grep -E '^[^/]+/package\.json$' | head -1 || true)
[ -n "$MEMBER" ] || die "bundle has no top-level package.json"
VERSION=$(tar -xOf "$BUNDLE" "$MEMBER" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).version)}catch{console.log("")}})' 2>/dev/null || true)
[ -n "$VERSION" ] || die "cannot read the bundle version"
NAME="dsh-desktop-$VERSION-freebsd-amd64"
STAGE="$OUT/$NAME"

command -v cc >/dev/null 2>&1 || die "cc is required to build the native window"
pkg-config --exists webkit2gtk-4.1 || die "webkit2gtk-4.1 is required to build the native window"

msg "packaging dsh desktop $VERSION"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$STAGE/runtime"

cp "$ROOT/desktop/install-desktop.sh" "$STAGE/install-desktop.sh"
cp "$ROOT/desktop/dsh-desktop" "$STAGE/dsh-desktop"
cp "$ROOT/desktop/dsh-desktop.c" "$STAGE/dsh-desktop.c"
cp "$ROOT/desktop/dsh-desktop.desktop.in" "$STAGE/dsh-desktop.desktop.in"
chmod 755 "$STAGE/install-desktop.sh" "$STAGE/dsh-desktop"

msg "building the native window"
cc -O2 -Wall -o "$STAGE/dsh-desktop-window" "$ROOT/desktop/dsh-desktop.c" \
    $(pkg-config --cflags --libs webkit2gtk-4.1)
strip "$STAGE/dsh-desktop-window" 2>/dev/null || true

msg "extracting the runtime"
tar -xzf "$BUNDLE" -C "$STAGE/runtime" --strip-components 1
ICON="$STAGE/runtime/node_modules/@deepseek-ai/dsh-web-frontend/dist/icon-512.png"
[ -f "$ICON" ] && cp "$ICON" "$STAGE/icon-512.png"

cat > "$STAGE/INSTALL.txt" <<EOF
DeepSeek Harness desktop app $VERSION (FreeBSD amd64)
====================================================

Requirements
  - Node.js (pkg install node24)
  - WebKitGTK 4.1 for the native window; Chromium is the fallback
    (the window binary is already built into this package)

Install for the current user (no root)
  sh install-desktop.sh

Then start "DeepSeek Harness" from the application menu, or run
  ~/.local/bin/dsh-desktop

Install system-wide (root)
  sudo sh install-desktop.sh --prefix /usr/local

Remove
  sh install-desktop.sh --uninstall

The launcher starts the harness on 127.0.0.1, opens it in a native window and
stops the server when the window closes. State and logs live in
${XDG_STATE_HOME:-~/.local/state}/dsh-desktop and the harness home defaults to
~/.dsh (DSH_DESKTOP_HOME overrides it).
EOF

msg "tar: $NAME.tar.gz"
tar -czf "$OUT/$NAME.tar.gz" -C "$OUT" "$NAME"
SIZE=$(wc -c < "$OUT/$NAME.tar.gz" | tr -d ' ')
SUM=$(sha256 -q "$OUT/$NAME.tar.gz")
msg "package: $OUT/$NAME.tar.gz ($SIZE bytes)"
msg "sha256:  $SUM"
