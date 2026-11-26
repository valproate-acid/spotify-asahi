# Spotify on Asahi Linux (muvm + Box64)

Apple Silicon(Fedora Asahi Remix)에서 공식 Spotify Linux `x86_64` 데스크톱 앱을 `muvm`과 `Box64`로 안정적으로 실행하기 위한 **래퍼 스크립트, Box64 안정화 패치, 오디오 설정 모음**입니다.

> **저작권 안내 (Copyright Notice)**
> 이 저장소는 Spotify의 독점 바이너리, 라이브러리, 에셋을 **일절 포함·재배포하지 않습니다**.
> 사용자는 아래 안내에 따라 Spotify 공식 저장소에서 원본 `.deb` 패키지를 직접 내려받아 로컬에서 설치해야 합니다.
> Box64 소스 역시 빌드 시 공식 업스트림(`ptitSeb/box64`)에서 직접 내려받습니다.

---

## 면책 조항 (Disclaimer)

- **Spotify와의 무관 및 격리 (Non-Affiliation)**: 이 프로젝트는 Spotify AB 및 그 계열사와 어떠한 제휴, 후원, 보증, 공식 관계도 없는 독립적인 비공식 실행 스크립트·설정 모음입니다. "Spotify" 명칭·상표·로고에 대한 모든 권리는 Spotify AB에 있습니다.
- **계정 정지 및 이용 제한 위험 (Account / ToS Risk)**: 비공식 실행 환경(가상화·에뮬레이션)에서 클라이언트를 구동함으로써 발생할 수 있는 Spotify 이용약관(ToS) 해석 문제, 서비스 이용 제한, 계정 정지 등에 대해 제작자 및 기여자는 어떠한 책임도 지지 않습니다. 사용 여부와 그 결과는 전적으로 사용자 본인의 판단과 책임입니다.
- **오류 및 손실 면책 (No Warranty & Limitation of Liability)**: 본 프로젝트의 모든 스크립트와 설정은 Apache License 2.0에 따라 **"있는 그대로(AS IS)"** 제공됩니다. 실행 오류, 앱 비정상 종료(튕김), 로컬 캐시·데이터 손실, 시스템 오작동, 오디오 설정 변경으로 인한 문제 등 직·간접적 손실에 대해 어떠한 보증이나 법적 책임도 지지 않습니다.
- **AI 작성 코드 고지 (AI-Generated Code)**: 이 저장소의 실행 스크립트, 패치 및 문서는 AI 코딩 도구의 도움을 받아 작성·검토되었습니다. 실제 환경에 적용하기 전에 스크립트 내용을 직접 확인하시기 바랍니다.

---

## 사전 준비 (Fedora Asahi Remix)

```sh
sudo dnf install -y \
  muvm fex-emu-rootfs-fedora \
  git gcc make cmake binutils tar patch python3 \
  libayatana-appindicator-gtk3
```

---

## 설치 방법

### 1. Box64 빌드 및 `[spotify]` 안정화 패치 적용

```sh
./build-box64.sh
```

- 공식 `ptitSeb/box64` (`v0.4.4`)를 `vendor/box64`에 내려받아 `ARM64` 타깃으로 빌드합니다.
- `patches/box64rc-spotify.patch`를 적용해 `runtime/box64.box64rc`를 생성합니다.

### 2. 공식 Spotify Linux `x86_64` 패키지 다운로드

Spotify 공식 Linux 저장소에서 최신 `spotify-client_*_amd64.deb` 파일을 직접 다운로드합니다.

- 공식 저장소 목록: https://repository.spotify.com/pool/non-free/s/spotify-client/

예시 (최신 파일명은 위 링크에서 확인):

```sh
curl -LO https://repository.spotify.com/pool/non-free/s/spotify-client/spotify-client_<VERSION>_amd64.deb
```

### 3. 설치 스크립트 실행

```sh
# 기본 설치 (Spotify 추출 + systemd 사용자 서비스 + 런처 + 앱 메뉴 아이콘)
./install.sh --deb ./spotify-client_*.deb

# PipeWire 44.1 kHz 무손실(리샘플링 제거) 설정까지 함께 설치
./install.sh --deb ./spotify-client_*.deb --with-pipewire
```

---

## 실행 및 관리

```sh
./run.sh                                          # 또는 앱 메뉴의 Spotify / 터미널에서 spotify
systemctl --user restart spotify-asahi.service
systemctl --user stop spotify-asahi.service
journalctl --user -u spotify-asahi.service -n 80 --no-pager
```

### 제거

```sh
./uninstall.sh                  # 서비스, 런처, 데스크톱 항목 제거
./uninstall.sh --remove-pipewire # PipeWire 설정까지 제거
```

---

## 포함된 안정성·음질 개선

1. **PTY 슈퍼바이저 (`pty-run.py`)**: Python `pty.spawn()`의 `EAGAIN` 조기 종료(`SIGHUP`) 및 `stdout` 백프레셔 데드락 문제를 제거하고, `SIGTERM`/`SIGINT` 시그널을 자식 프로세스 그룹에 안전하게 전달합니다.
2. **Box64 CEF/V8 안정화 패치 (`patches/box64rc-spotify.patch`)**: `STRONGMEM=3`, `SAFEFLAGS=2`, `CALLRET=0`, `INTERP_SIGNAL=1`, `FASTROUND=0`, `FASTNAN=0`, `AVX=0`, `MAXCPU=4`, `DYNACACHE=0` 적용.
3. **게스트 런처 (`runtime/run-guest.sh`)**: `--disable-dev-shm-usage`로 `muvm` 내 `/dev/shm` 부족 `SIGBUS` 크래시 방지 및 `LD_LIBRARY_PATH` 보존.
4. **무손실 오디오 (`pipewire/`)**: PipeWire `clock.allowed-rates`에 `44100`을 활성화해 44.1 kHz Lossless FLAC 재생 시 리샘플링을 제거하고, 혼합 재생 시에도 `resample.quality = 10`을 유지합니다.

## 라이선스

- 본 저장소의 스크립트 및 설정 파일: [Apache License 2.0](LICENSE) ([NOTICE](NOTICE) 참고)
- Spotify 클라이언트: Spotify 독점 라이선스 (본 저장소에 미포함)
- Box64: MIT License (업스트림에서 직접 빌드)
