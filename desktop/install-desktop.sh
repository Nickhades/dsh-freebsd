#!/bin/sh
# install-desktop.sh - install the DeepSeek Harness desktop app for one user.
#
# Installs the native WebKitGTK window, the launcher, the runtime bundle, the
# icon and an application-menu entry under PREFIX (default ~/.local), so the app
# can be started by double-clicking "DeepSeek Harness". No root is required.
#
# Usage:
#   sh desktop/install-desktop.sh [options]
#     --prefix DIR            install prefix (default: $HOME/.local)
#     --runtime-tarball FILE  runtime bundle from scripts/bundle.sh
#                             (default: newest .work/dist/deepseek-harness-*-freebsd-amd64.tar.gz)
#     --runtime-dir DIR       reuse an unpacked runtime directory (symlinked)
#     --skip-runtime          keep the runtime already installed
#     --desktop-shortcut      also put an icon on the XDG desktop (xdg-user-dir DESKTOP)
#     --uninstall             remove the app (keeps harness state in DSH_HOME)
#     -h | --help             this help
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -f "$SCRIPT_DIR/dsh-desktop" ] && [ -d "$SCRIPT_DIR/runtime" ]; then
    # Packaged layout: install-desktop.sh sits beside the app files and runtime.
    ROOT=$SCRIPT_DIR
    SRC=$ROOT
else
    # Overlay layout: desktop/install-desktop.sh under the overlay root.
    ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
    SRC="$ROOT/desktop"
fi
PREFIX="${PREFIX:-$HOME/.local}"
BUNDLE=""
RUNTIME_DIR=""
SKIP_RUNTIME=0
DESKTOP_SHORTCUT=0
UNINSTALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX=$2; shift 2 ;;
        --runtime-tarball) BUNDLE=$2; shift 2 ;;
        --runtime-dir) RUNTIME_DIR=$2; shift 2 ;;
        --skip-runtime) SKIP_RUNTIME=1; shift ;;
        --desktop-shortcut) DESKTOP_SHORTCUT=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "install-desktop: unknown option: $1" >&2; exit 2 ;;
    esac
done

case "$PREFIX" in
    /*) ;;
    *) PREFIX=$(pwd)/$PREFIX ;;
esac

LIBEXEC="$PREFIX/libexec/dsh-desktop"
APPS="$PREFIX/share/applications"
ICON_DIR="$PREFIX/share/icons/hicolor/512x512/apps"
DESKTOP_FILE="$APPS/dsh-desktop.desktop"
ICON_FILE="$ICON_DIR/dsh-desktop.png"
LAUNCHER="$PREFIX/bin/dsh-desktop"

if [ "$UNINSTALL" = 1 ]; then
    [ -x "$LAUNCHER" ] && "$LAUNCHER" --stop >/dev/null 2>&1 || true
    rm -f "$LAUNCHER" "$DESKTOP_FILE" "$ICON_FILE"
    rm -rf "$LIBEXEC"
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" >/dev/null 2>&1 || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$PREFIX/share/icons/hicolor" >/dev/null 2>&1 || true
    echo "Removed the DeepSeek Harness desktop app from $PREFIX"
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    case "$PREFIX" in
        /usr/*|/opt/*) echo "install-desktop: $PREFIX needs root; rerun with sudo or choose --prefix \$HOME/.local" >&2; exit 1 ;;
    esac
fi

command -v node >/dev/null 2>&1 || { echo "install-desktop: node not found (pkg install node24)" >&2; exit 1; }
[ -f "$SRC/dsh-desktop" ] || { echo "install-desktop: missing $SRC/dsh-desktop; run it from the overlay or an unpacked desktop package" >&2; exit 1; }

mkdir -p "$PREFIX/bin" "$PREFIX/share/applications" "$ICON_DIR"

# Stop a running instance before replacing the runtime it uses.
[ -x "$LAUNCHER" ] && "$LAUNCHER" --stop >/dev/null 2>&1 || true

if [ "$SKIP_RUNTIME" = 0 ]; then
    mkdir -p "$LIBEXEC"
    if [ -n "$RUNTIME_DIR" ]; then
        RUNTIME_DIR=$(CDPATH= cd -- "$RUNTIME_DIR" && pwd)
        rm -rf "$LIBEXEC/runtime"
        ln -s "$RUNTIME_DIR" "$LIBEXEC/runtime"
        echo "runtime: $LIBEXEC/runtime -> $RUNTIME_DIR (this directory must stay in place)"
    else
        if [ -z "$BUNDLE" ] && [ -f "$ROOT/runtime/lib/bin.js" ]; then
            echo "runtime: using the runtime bundled with this package"
            rm -rf "$LIBEXEC/runtime"
            cp -R "$ROOT/runtime" "$LIBEXEC/runtime"
        elif [ -n "$BUNDLE" ] || ls "$ROOT"/.work/dist/deepseek-harness-*-freebsd-amd64.tar.gz >/dev/null 2>&1; then
            if [ -z "$BUNDLE" ]; then
                BUNDLE=$(ls -t "$ROOT"/.work/dist/deepseek-harness-*-freebsd-amd64.tar.gz 2>/dev/null | head -1 || true)
            fi
            [ -n "$BUNDLE" ] && [ -f "$BUNDLE" ] || {
                echo "install-desktop: no runtime bundle found." >&2
                echo "  Build one with: sh scripts/bundle.sh .work/tree-final" >&2
                echo "  or pass --runtime-tarball FILE / --runtime-dir DIR." >&2
                exit 1
            }
            echo "runtime: extracting $(basename "$BUNDLE")"
            rm -rf "$LIBEXEC/runtime"
            mkdir -p "$LIBEXEC/runtime"
            tar -xzf "$BUNDLE" -C "$LIBEXEC/runtime" --strip-components 1
        else
            echo "install-desktop: no runtime bundle found." >&2
            echo "  Build one with: sh scripts/bundle.sh .work/tree-final" >&2
            echo "  or pass --runtime-tarball FILE / --runtime-dir DIR." >&2
            exit 1
        fi
    fi
fi
RUNTIME="$LIBEXEC/runtime"
[ -f "$RUNTIME/lib/bin.js" ] || [ -f "$RUNTIME/apps/cli/lib/bin.js" ] || {
    echo "install-desktop: $RUNTIME has no lib/bin.js; use --runtime-tarball or --runtime-dir" >&2
    exit 1
}

# Native window (WebKitGTK). A packaged build ships a prebuilt binary; the
# overlay build compiles it here. Without it the launcher falls back to Chromium.
mkdir -p "$LIBEXEC"
if [ -x "$SRC/dsh-desktop-window" ]; then
    echo "window:  installing the packaged WebKitGTK window"
    install -m 755 "$SRC/dsh-desktop-window" "$LIBEXEC/dsh-desktop-window"
elif command -v pkg-config >/dev/null 2>&1 && pkg-config --exists webkit2gtk-4.1; then
    if command -v cc >/dev/null 2>&1; then
        echo "window:  building native WebKitGTK window"
        cc -O2 -Wall -o "$LIBEXEC/dsh-desktop-window" "$SRC/dsh-desktop.c" \
            $(pkg-config --cflags --libs webkit2gtk-4.1) || {
            echo "install-desktop: WebKitGTK window build failed; the launcher will fall back to Chromium" >&2
            rm -f "$LIBEXEC/dsh-desktop-window"
        }
    else
        echo "window:  cc not found; the launcher will fall back to Chromium" >&2
    fi
else
    echo "window:  webkit2gtk-4.1 not found; the launcher will fall back to Chromium (pkg install webkit2gtk-4.1 for the native window)" >&2
fi

install -m 755 "$SRC/dsh-desktop" "$LAUNCHER"

ICON_SRC="$RUNTIME/node_modules/@deepseek-ai/dsh-web-frontend/dist/icon-512.png"
[ -f "$ICON_SRC" ] || ICON_SRC="$SRC/icon-512.png"
if [ -f "$ICON_SRC" ]; then
    install -m 644 "$ICON_SRC" "$ICON_FILE"
else
    echo "window:  runtime has no icon-512.png; the menu entry will use a generic icon" >&2
fi

EXEC_PATH="$LAUNCHER"
ICON_PATH="$ICON_FILE"
sed -e "s|@EXEC@|$EXEC_PATH|g" -e "s|@ICON@|$ICON_PATH|g" \
    "$SRC/dsh-desktop.desktop.in" > "$DESKTOP_FILE"
chmod 644 "$DESKTOP_FILE"

if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$DESKTOP_FILE" || echo "install-desktop: desktop-file-validate reported issues (continuing)" >&2
fi
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" >/dev/null 2>&1 || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$PREFIX/share/icons/hicolor" >/dev/null 2>&1 || true

if [ "$DESKTOP_SHORTCUT" = 1 ]; then
    DESKTOP_DIR=""
    if command -v xdg-user-dir >/dev/null 2>&1; then
        DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || true)
    fi
    [ -n "$DESKTOP_DIR" ] || DESKTOP_DIR="$HOME/Desktop"
    if [ -d "$DESKTOP_DIR" ]; then
        cp "$DESKTOP_FILE" "$DESKTOP_DIR/dsh-desktop.desktop"
        chmod 755 "$DESKTOP_DIR/dsh-desktop.desktop"
        echo "shortcut: $DESKTOP_DIR/dsh-desktop.desktop"
    else
        echo "shortcut: $DESKTOP_DIR does not exist; skipped (menu entry is installed)" >&2
    fi
fi

echo ""
echo "Installed DeepSeek Harness desktop app"
echo "  launcher:   $LAUNCHER"
echo "  runtime:    $RUNTIME"
echo "  menu entry: $DESKTOP_FILE"
echo "  logs:       ${XDG_STATE_HOME:-$HOME/.local/state}/dsh-desktop/"
echo ""
echo "Start it from the application menu, or run: $LAUNCHER"
case ":$PATH:" in
    *":$PREFIX/bin:"*) ;;
    *) echo "Note: add $PREFIX/bin to PATH to run 'dsh-desktop' from a terminal." ;;
esac
