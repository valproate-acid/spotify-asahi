#!/bin/sh
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)

box64_bin="$base/bin/box64"
spotify_bin="$base/usr/share/spotify/spotify"
profile="${SPOTIFY_PROFILE:-asahi-desktop}"

if [ ! -x "$box64_bin" ]; then
    echo "run-guest: box64 not executable: $box64_bin" >&2
    exit 127
fi
if [ ! -x "$spotify_bin" ]; then
    echo "run-guest: spotify not executable: $spotify_bin" >&2
    exit 127
fi

export LD_LIBRARY_PATH="$base/native/usr/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export BOX64_LD_LIBRARY_PATH="/run/fex-emu/rootfs/usr/lib64:/run/fex-emu/rootfs/lib64${BOX64_LD_LIBRARY_PATH:+:$BOX64_LD_LIBRARY_PATH}"
export BOX64_RCFILE="$base/box64.box64rc"
export BOX64_LOG="${BOX64_LOG:-1}"

exec "$box64_bin" "$spotify_bin" \
    --mu="$profile" \
    --disable-gpu \
    --disable-dev-shm-usage \
    --single-process \
    --no-zygote \
    "$@"
