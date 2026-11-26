#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
deb_path=""
with_pipewire=0
profile="${SPOTIFY_PROFILE:-asahi-desktop}"

usage() {
    cat <<'EOF'
Usage: ./install.sh [--deb /path/to/spotify-client.deb] [--with-pipewire] [--profile NAME]

Options:
  --deb PATH        Path to the official Spotify Linux x86_64 .deb package downloaded by the user.
  --with-pipewire   Install PipeWire 44.1 kHz native clock switching & high-quality resampler configs.
  --profile NAME    Spotify --mu profile name (default: asahi-desktop).
  -h, --help        Show this help message.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --deb)
            [ "$#" -ge 2 ] || { echo "Missing value for --deb" >&2; exit 2; }
            deb_path="$2"
            shift 2
            ;;
        --with-pipewire)
            with_pipewire=1
            shift
            ;;
        --profile)
            [ "$#" -ge 2 ] || { echo "Missing value for --profile" >&2; exit 2; }
            profile="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# 1. Extract user-provided official Spotify .deb (never bundled for copyright reasons)
if [ -n "$deb_path" ]; then
    if [ ! -f "$deb_path" ]; then
        echo "Spotify .deb file not found: $deb_path" >&2
        exit 1
    fi
    command -v ar >/dev/null 2>&1 || { echo "Missing 'ar' (install binutils)" >&2; exit 1; }
    command -v tar >/dev/null 2>&1 || { echo "Missing 'tar'" >&2; exit 1; }

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT INT TERM
    (cd "$tmp_dir" && ar x "$deb_path")

    data_tar=""
    for cand in "$tmp_dir"/data.tar.*; do
        if [ -f "$cand" ]; then
            data_tar="$cand"
            break
        fi
    done
    if [ -z "$data_tar" ]; then
        echo "Invalid .deb archive (data.tar.* not found): $deb_path" >&2
        exit 1
    fi

    rm -rf "$root/runtime/usr"
    mkdir -p "$root/runtime"
    tar -xf "$data_tar" -C "$root/runtime"
    rm -rf "$tmp_dir"
    trap - EXIT INT TERM
    echo "Extracted Spotify client into $root/runtime/usr/share/spotify"
fi

if [ ! -x "$root/runtime/usr/share/spotify/spotify" ]; then
    echo "Spotify binary not found at $root/runtime/usr/share/spotify/spotify" >&2
    echo "Download the official Linux x86_64 .deb from https://repository.spotify.com/pool/non-free/s/spotify-client/" >&2
    echo "and run: ./install.sh --deb /path/to/spotify-client_*.deb" >&2
    exit 1
fi

if [ ! -x "$root/runtime/bin/box64" ]; then
    echo "Box64 binary not found at $root/runtime/bin/box64" >&2
    echo "Run ./build-box64.sh first." >&2
    exit 1
fi

# 2. Copy native ARM64 tray indicator libraries if installed on host
mkdir -p "$root/runtime/native/usr/lib64"
for pat in \
    'libayatana-appindicator3.so*' \
    'libayatana-indicator3.so*' \
    'libayatana-ido3-0.4.so*' \
    'libdbusmenu-glib.so*' \
    'libdbusmenu-gtk3.so*'; do
    for lib in /usr/lib64/$pat; do
        if [ -e "$lib" ]; then
            cp -a "$lib" "$root/runtime/native/usr/lib64/"
        fi
    done
done

# 3. Render and install user service, launcher, and desktop entry
render_template() {
    src="$1"
    dst="$2"
    mode="$3"
    mkdir -p "$(dirname "$dst")"
    python3 - "$src" "$dst" "$root" "$profile" <<'PY'
import sys
from pathlib import Path

src, dst, project_dir, profile = sys.argv[1:5]
text = Path(src).read_text(encoding="utf-8")
text = text.replace("@PROJECT_DIR@", project_dir).replace("@SPOTIFY_PROFILE@", profile)
Path(dst).write_text(text, encoding="utf-8")
PY
    chmod "$mode" "$dst"
}

render_template \
    "$root/templates/spotify-asahi.service.in" \
    "$HOME/.config/systemd/user/spotify-asahi.service" \
    644

render_template \
    "$root/templates/spotify-launcher.in" \
    "$HOME/.local/bin/spotify" \
    755

render_template \
    "$root/templates/spotify-asahi.desktop.in" \
    "$HOME/.local/share/applications/spotify-asahi.desktop" \
    644

# 4. Optional PipeWire lossless 44.1 kHz audio configs
if [ "$with_pipewire" -eq 1 ]; then
    for sub in pipewire.conf.d pipewire-pulse.conf.d client.conf.d; do
        mkdir -p "$HOME/.config/pipewire/$sub"
        cp "$root/pipewire/$sub/99-lossless-audio.conf" "$HOME/.config/pipewire/$sub/99-lossless-audio.conf"
    done
    echo "Installed PipeWire lossless audio configs into ~/.config/pipewire/"
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload || true
fi

echo "Installation complete."
echo "Start Spotify with: ~/.local/bin/spotify  (or: systemctl --user start spotify-asahi.service)"
