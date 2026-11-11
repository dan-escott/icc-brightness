#!/usr/bin/env bash
# Install icc-brightness (patched script, profile generator, GNOME autostart)
# and restart the watcher. Works on a clean Ubuntu/Debian GNOME install.
# Run as your normal user (not with sudo); sudo is used only for the install.
set -euo pipefail

DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
SRC="$DIR/icc-brightness"
GEN_SRC="$DIR/icc-brightness-gen.c"
DESKTOP_SRC="$DIR/icc-brightness.desktop"
BIN_DIR=/usr/local/bin
DEST=$BIN_DIR/icc-brightness
AUTOSTART_DIR=/usr/share/gnome/autostart

[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user, not root." >&2; exit 1; }
for f in "$SRC" "$GEN_SRC" "$DESKTOP_SRC"; do
    [ -f "$f" ] || { echo "Missing $f" >&2; exit 1; }
done

# colord provides colormgr; the script's shebang needs a "python" command.
pkgs=(colord python3 python-is-python3 gcc make liblcms2-dev)
missing=()
for p in "${pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "Installing packages: ${missing[*]}"
    sudo apt-get install -y "${missing[@]}"
fi

python3 -m py_compile "$SRC"

build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
# Use the system compiler: other gcc builds on PATH (e.g. Nix) may not search /usr/include.
/usr/bin/gcc -W -Wall "$GEN_SRC" -l lcms2 -o "$build/icc-brightness-gen"

if [ -f "$DEST" ] && [ ! -f "$DEST.orig" ]; then
    sudo cp -p "$DEST" "$DEST.orig"
    echo "Backed up original to $DEST.orig"
fi
sudo install -m755 "$SRC" "$DEST"
# The script looks for icc-brightness-gen next to itself.
sudo install -m755 "$build/icc-brightness-gen" "$BIN_DIR/icc-brightness-gen"
sudo install -D -m644 "$DESKTOP_SRC" "$AUTOSTART_DIR/icc-brightness.desktop"
echo "Installed $DEST, icc-brightness-gen and autostart entry"

if pids=$(pgrep -u "$USER" -f "icc-brightness watch"); then
    # shellcheck disable=SC2086
    kill $pids
    sleep 1
fi
setsid systemd-cat -t icc-brightness "$DEST" watch >/dev/null 2>&1 &
sleep 2

if pgrep -u "$USER" -f "icc-brightness watch" >/dev/null; then
    echo "Watcher running (PID $(pgrep -u "$USER" -f 'icc-brightness watch' | tr '\n' ' '))"
else
    echo "Watcher failed to start" >&2
    exit 1
fi
