#!/usr/bin/python3
"""Give muvm a terminal while systemd owns the process and its output."""
import errno
import os
from pathlib import Path
import pty
import selectors
import signal
import subprocess
import sys
import termios
import time

MUVM_BIN = Path("/usr/bin/muvm")
SHUTDOWN_GRACE_SEC = 10.0


def _disable_echo(fd: int) -> None:
    try:
        attrs = termios.tcgetattr(fd)
        attrs[3] &= ~termios.ECHO
        termios.tcsetattr(fd, termios.TCSANOW, attrs)
    except termios.error:
        pass


def _write_best_effort(fd: int, data: bytes) -> bool:
    """Write all bytes to fd; return False if fd is permanently unusable."""
    view = memoryview(data)
    written = 0
    while written < len(view):
        try:
            n = os.write(fd, view[written:])
            if n == 0:
                return False
            written += n
        except InterruptedError:
            continue
        except OSError as exc:
            if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                time.sleep(0.005)
                continue
            return False
    return True


def _terminate_process_group(proc: subprocess.Popen[bytes], sig: int) -> None:
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, sig)
    except ProcessLookupError:
        pass
    except PermissionError:
        try:
            proc.send_signal(sig)
        except ProcessLookupError:
            pass


def _resolve_command(guest_script: Path, args: list[str]) -> tuple[list[str], bool] | None:
    """Resolve launch command and whether a PTY is required.

    SPOTIFY_ASAHI_MODE:
      - auto (default): use muvm on >4KB-page kernels (e.g. Asahi 16KB) or when muvm exists;
        fall back to direct Box64 execution on 4KB ARM64 Linux if muvm is absent.
      - muvm: require /usr/bin/muvm.
      - direct: run guest_script directly without muvm (4KB ARM64 Linux, untested).
    """
    mode = os.environ.get("SPOTIFY_ASAHI_MODE", "auto").strip().lower()
    page_size = os.sysconf("SC_PAGESIZE")
    has_muvm = MUVM_BIN.is_file() and os.access(MUVM_BIN, os.X_OK)

    if mode == "direct":
        return ([str(guest_script), *args], False)
    if mode == "muvm":
        if not has_muvm:
            sys.stderr.write(f"pty-run: executable not found: {MUVM_BIN}\n")
            return None
        return ([str(MUVM_BIN), "-i", str(guest_script), *args], True)

    # auto mode
    if has_muvm:
        return ([str(MUVM_BIN), "-i", str(guest_script), *args], True)
    if page_size > 4096:
        sys.stderr.write(
            f"pty-run: host page size is {page_size}B (requires {MUVM_BIN} for 4KB guest)\n"
        )
        return None
    return ([str(guest_script), *args], False)


def main() -> int:
    root = Path(__file__).resolve().parent
    guest_script = root / "runtime/run-guest.sh"

    if not guest_script.is_file() or not os.access(guest_script, os.X_OK):
        sys.stderr.write(f"pty-run: executable not found: {guest_script}\n")
        return 127

    resolved = _resolve_command(guest_script, sys.argv[1:])
    if resolved is None:
        return 127
    cmd, use_pty = resolved

    if not use_pty:
        os.execv(cmd[0], cmd)

    master_fd, slave_fd = pty.openpty()
    _disable_echo(slave_fd)

    proc: subprocess.Popen[bytes] | None = None
    shutdown_deadline: float | None = None

    def _handle_signal(signum: int, _frame: object) -> None:
        nonlocal shutdown_deadline
        if proc is not None and proc.poll() is None:
            _terminate_process_group(proc, signum)
            if shutdown_deadline is None:
                shutdown_deadline = time.monotonic() + SHUTDOWN_GRACE_SEC

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, _handle_signal)

    try:
        def _child_setup() -> None:
            os.setsid()
            try:
                import fcntl
                fcntl.ioctl(slave_fd, termios.TIOCSCTTY, 0)
            except OSError:
                pass

        proc = subprocess.Popen(
            cmd,
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            close_fds=True,
            preexec_fn=_child_setup,
        )
    except OSError as exc:
        os.close(slave_fd)
        os.close(master_fd)
        sys.stderr.write(f"pty-run: failed to spawn muvm: {exc}\n")
        return 126

    os.close(slave_fd)
    os.set_blocking(master_fd, False)

    stdin_fd = sys.stdin.fileno()
    stdout_fd = sys.stdout.fileno()
    stdin_is_tty = os.isatty(stdin_fd)
    saved_stdin_mode = None
    if stdin_is_tty:
        try:
            saved_stdin_mode = termios.tcgetattr(stdin_fd)
            import tty
            tty.setraw(stdin_fd)
        except termios.error:
            saved_stdin_mode = None

    sel = selectors.DefaultSelector()
    sel.register(master_fd, selectors.EVENT_READ, data="master")
    stdin_open = stdin_is_tty
    if stdin_open:
        sel.register(stdin_fd, selectors.EVENT_READ, data="stdin")
    stdout_ok = True

    try:
        while True:
            if shutdown_deadline is not None and time.monotonic() >= shutdown_deadline:
                _terminate_process_group(proc, signal.SIGKILL)
                shutdown_deadline = None

            events = sel.select(timeout=0.25)
            eof = False
            for key, _ in events:
                if key.data == "master":
                    try:
                        chunk = os.read(master_fd, 4096)
                    except InterruptedError:
                        continue
                    except OSError as exc:
                        if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                            continue
                        if exc.errno == errno.EIO:
                            eof = True
                            break
                        eof = True
                        break
                    if not chunk:
                        eof = True
                        break
                    # Always drain master_fd even if stdout fails, so muvm never deadlocks.
                    if stdout_ok:
                        stdout_ok = _write_best_effort(stdout_fd, chunk)
                elif key.data == "stdin":
                    try:
                        data = os.read(stdin_fd, 4096)
                    except InterruptedError:
                        continue
                    except OSError:
                        data = b""
                    if not data:
                        sel.unregister(stdin_fd)
                        stdin_open = False
                    else:
                        _write_best_effort(master_fd, data)

            if eof:
                break
            if proc.poll() is not None and not events:
                break
    finally:
        sel.close()
        if saved_stdin_mode is not None:
            try:
                termios.tcsetattr(stdin_fd, termios.TCSAFLUSH, saved_stdin_mode)
            except termios.error:
                pass
        try:
            os.close(master_fd)
        except OSError:
            pass

    returncode = proc.wait()
    return returncode if returncode >= 0 else 128 - returncode


if __name__ == "__main__":
    sys.exit(main())
