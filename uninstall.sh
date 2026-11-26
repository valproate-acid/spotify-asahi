#!/bin/sh
set -eu

remove_pipewire=0
if [ "${1:-}" = "--remove-pipewire" ]; then
    remove_pipewire=1
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl --user stop spotify-asahi.service 2>/dev/null || true
fi

rm -f "$HOME/.config/systemd/user/spotify-asahi.service"
rm -f "$HOME/.local/bin/spotify"
rm -f "$HOME/.local/share/applications/spotify-asahi.desktop"

if [ "$remove_pipewire" -eq 1 ]; then
    rm -f "$HOME/.config/pipewire/pipewire.conf.d/99-lossless-audio.conf"
    rm -f "$HOME/.config/pipewire/pipewire-pulse.conf.d/99-lossless-audio.conf"
    rm -f "$HOME/.config/pipewire/client.conf.d/99-lossless-audio.conf"
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload || true
fi

echo "Uninstalled spotify-asahi user service, launcher, and desktop entry."
echo "Note: Spotify cache (~/.cache/spotify-*) was preserved."
