#!/bin/sh
# Linux: moves io/ to tmpfs (RAM), so commands, results and the heartbeat never touch the disk.
# setup-tmpfs.sh          io/ -> /dev/shm/LuaDebugAPI-<game> (existing files are moved along)
# setup-tmpfs.sh --undo   io/ becomes a normal folder again
# The target is gone after a reboot; ldb recreates it (or run this script again).
set -e
base="$(cd "$(dirname "$0")" && pwd)"
d="$base/io"
case "$base" in
*PAYDAY*) tag=pd2 ;;
*) tag=raid ;;
esac
# not $XDG_RUNTIME_DIR: the Steam runtime container (pressure-vessel) hides it from the game, /dev/shm is shared
target="/dev/shm/LuaDebugAPI-$tag"

if [ "$1" = "--undo" ]; then
	[ -L "$d" ] || { echo "io/ is no link, nothing to do"; exit 0; }
	src="$(readlink "$d")"
	rm "$d"
	mkdir "$d"
	[ -d "$src" ] && cp -a "$src/." "$d/"
	echo "io/ is a normal folder again"
	exit 0
fi

if [ -L "$d" ]; then
	mkdir -p "$(readlink "$d")"
	echo "io/ already links to $(readlink "$d")"
	exit 0
fi
mkdir -p "$target"
if [ -d "$d" ]; then
	cp -a "$d/." "$target/"
	rm -r "$d"
fi
ln -s "$target" "$d"
echo "io/ -> $target"
