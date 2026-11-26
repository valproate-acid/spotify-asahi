# Spotify on Asahi Linux (muvm + Box64)

**English** | [한국어](README.ko.md)

Wrapper scripts, Box64 stability patches, and lossless PipeWire audio configurations for running the official Spotify Linux `x86_64` desktop client on Apple Silicon (Fedora Asahi Remix) via `muvm` and `Box64`.

> **Copyright Notice**
> This repository does **NOT** include or redistribute any proprietary Spotify binaries, libraries, or assets.
> Users must download the official `.deb` package directly from Spotify's official repository and extract it locally.
> Box64 source code is also fetched directly from upstream (`ptitSeb/box64`) during build.

---

## Disclaimer

- **Non-Affiliation with Spotify**: This project is an independent, unofficial collection of wrapper scripts and configuration templates. It is NOT affiliated with, endorsed by, sponsored by, or officially connected with Spotify AB or any of its affiliates. All rights to the "Spotify" name, trademarks, and logos belong to Spotify AB.
- **Account Suspension / Terms of Service Risk**: Running the client in an unofficial virtualized/emulated environment may carry risks regarding Spotify's Terms of Service, including service restrictions or account suspension. The authors and contributors assume no responsibility for any such outcomes; use is strictly at your own risk.
- **No Warranty & Limitation of Liability**: All scripts, patches, and configurations in this repository are provided **"AS IS"** under the Apache License 2.0, without warranties of any kind. The authors and contributors are not liable for any direct or indirect damages, including crashes, errors, local cache/data loss, system malfunction, or audio configuration issues.
- **AI-Generated Code Disclosure**: The scripts, patches, and documentation in this repository were written and reviewed with the assistance of AI coding tools. Please review the code carefully before running it on your system.

---

## Prerequisites (Fedora Asahi Remix)

```sh
sudo dnf install -y \
  muvm fex-emu-rootfs-fedora \
  git gcc make cmake binutils tar patch python3 \
  libayatana-appindicator-gtk3
```

---

## Installation

### 1. Build Box64 and apply the `[spotify]` stability patch

```sh
./build-box64.sh
```

- Clones upstream `ptitSeb/box64` (`v0.4.4`) into `vendor/box64` and builds for `ARM64`.
- Applies `patches/box64rc-spotify.patch` to generate `runtime/box64.box64rc`.

### 2. Download the official Spotify Linux `x86_64` package

Download the latest `spotify-client_*_amd64.deb` directly from Spotify's official Linux repository:

- Official repository index: https://repository.spotify.com/pool/non-free/s/spotify-client/

Example (check the link above for the latest filename):

```sh
curl -LO https://repository.spotify.com/pool/non-free/s/spotify-client/spotify-client_<VERSION>_amd64.deb
```

### 3. Run the installer

```sh
# Standard install (extracts Spotify + installs systemd user service, launcher, and desktop entry)
./install.sh --deb ./spotify-client_*.deb

# Also install PipeWire 44.1 kHz native clock switching & high-quality resampler configs
./install.sh --deb ./spotify-client_*.deb --with-pipewire
```

---

## Usage & Management

```sh
./run.sh                                          # or launch "Spotify" from app menu / run `spotify`
systemctl --user restart spotify-asahi.service
systemctl --user stop spotify-asahi.service
journalctl --user -u spotify-asahi.service -n 80 --no-pager
```

### Uninstall

```sh
./uninstall.sh                   # removes user service, launcher, and desktop entry
./uninstall.sh --remove-pipewire # also removes installed PipeWire configs
```

---

## Included Stability & Audio Improvements

1. **Hardened PTY Supervisor (`pty-run.py`)**: Replaces Python's `pty.spawn()` to avoid premature `SIGHUP` exits on non-blocking `EAGAIN` and `stdout` backpressure deadlocks, while forwarding `SIGTERM`/`SIGINT`/`SIGHUP` cleanly to the child process group.
2. **Box64 CEF/V8 Stability Patch (`patches/box64rc-spotify.patch`)**: Applies conservative DynaRec settings (`STRONGMEM=3`, `SAFEFLAGS=2`, `CALLRET=0`, `INTERP_SIGNAL=1`, `FASTROUND=0`, `FASTNAN=0`, `AVX=0`, `MAXCPU=4`, `DYNACACHE=0`) to reduce intermittent ARM64 memory-ordering and JIT crashes.
3. **Guest Launcher (`runtime/run-guest.sh`)**: Adds `--disable-dev-shm-usage` to prevent `/dev/shm` exhaustion `SIGBUS` crashes inside `muvm`, and preserves existing `LD_LIBRARY_PATH` / `BOX64_LD_LIBRARY_PATH`.
4. **Lossless Audio (`pipewire/`)**: Enables `44100` Hz in PipeWire `clock.allowed-rates` so 44.1 kHz Lossless FLAC plays natively without resampling, and sets `resample.quality = 10` when mixed sample rates play simultaneously.

## License

- Scripts, patches, and configs in this repository: [Apache License 2.0](LICENSE) (see [NOTICE](NOTICE))
- Spotify client: Proprietary license by Spotify AB (not included in this repository)
- Box64: MIT License (built directly from upstream)
