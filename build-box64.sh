#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)

BOX64_TAG="${BOX64_TAG:-v0.4.4}"
BOX64_REPO="${BOX64_REPO:-https://github.com/ptitSeb/box64.git}"

if [ ! -d "$root/vendor/box64/.git" ] && [ ! -f "$root/vendor/box64/CMakeLists.txt" ]; then
    echo "Cloning Box64 ($BOX64_TAG) from $BOX64_REPO ..."
    mkdir -p "$root/vendor"
    git clone --depth 1 --branch "$BOX64_TAG" "$BOX64_REPO" "$root/vendor/box64"
fi

if [ -x "$root/.tools/bin/cmake" ]; then
    cmake_bin="$root/.tools/bin/cmake"
elif command -v cmake >/dev/null 2>&1; then
    cmake_bin=$(command -v cmake)
else
    rm -rf "$root/.tools"
    python3 -m venv "$root/.tools"
    if ! "$root/.tools/bin/pip" install 'cmake==4.4.5'; then
        rm -rf "$root/.tools"
        exit 1
    fi
    cmake_bin="$root/.tools/bin/cmake"
fi

"$cmake_bin" -S "$root/vendor/box64" -B "$root/.build/box64" \
    -DARM64=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo
"$cmake_bin" --build "$root/.build/box64" -j "${JOBS:-2}"

mkdir -p "$root/runtime/bin"
tmp_bin="$root/runtime/bin/box64.new.$$"
trap 'rm -f "$tmp_bin"' EXIT INT TERM
install -m 755 "$root/.build/box64/box64" "$tmp_bin"
strip "$tmp_bin"
mv "$tmp_bin" "$root/runtime/bin/box64"
trap - EXIT INT TERM

# Generate runtime/box64.box64rc from upstream + [spotify] stability patch
cp "$root/vendor/box64/system/box64.box64rc" "$root/runtime/box64.box64rc"
if command -v git >/dev/null 2>&1 && (cd "$root/runtime" && git apply -p2 "$root/patches/box64rc-spotify.patch") 2>/dev/null; then
    echo "Applied patches/box64rc-spotify.patch to runtime/box64.box64rc (via git apply)"
elif command -v patch >/dev/null 2>&1 && patch -s -p2 -d "$root/runtime" < "$root/patches/box64rc-spotify.patch" 2>/dev/null; then
    echo "Applied patches/box64rc-spotify.patch to runtime/box64.box64rc (via patch)"
else
    # Fallback: use standalone patched [spotify] section
    cp "$root/patches/spotify.box64rc" "$root/runtime/box64.box64rc"
    echo "Installed standalone patches/spotify.box64rc as runtime/box64.box64rc"
fi

if [ -f "$root/vendor/box64/LICENSE" ]; then
    cp "$root/vendor/box64/LICENSE" "$root/runtime/LICENSE.box64"
fi

echo "Box64 build complete: $root/runtime/bin/box64"
