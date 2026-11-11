"""What the tools share (v0.8.4.29.7): the paths of the repo, Godot and the game's user dir, the backend traces of the
dev server and of the build's own server, a free port, a playtest's Godot run on a hidden desktop, a slug of a Russian
name. Imported by the tools beside it."""

import os
import socket
import subprocess
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GODOT = r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
USER_DIR = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming")) / "Godot" / "app_userdata" / "Between the Rolls"
DEV_VAR = ROOT / "llm_server" / "var"  # the dev llm_server's data: traces, bills, the item library
GAME_VAR = USER_DIR / "master"  # the frozen server.exe of the build keeps its data in the game's user dir (ADR-0014)

TRANSLIT = dict(zip("абвгдеёжзийклмнопрстуфхцчшщъыьэюя",
                    ["a", "b", "v", "g", "d", "e", "e", "zh", "z", "i", "y", "k", "l", "m", "n", "o", "p", "r", "s", "t", "u", "f",
                     "kh", "ts", "ch", "sh", "shch", "", "y", "", "e", "yu", "ya"]))


def godot() -> str:
    """The Godot binary: env GODOT or the Steam install."""
    return os.environ.get("GODOT", DEFAULT_GODOT)


def backend_trace_dirs() -> list[Path]:
    """Where the model side of a session is: the dev server's traces and the build's own (the author plays the build)."""
    return [d for d in (DEV_VAR / "traces", GAME_VAR / "traces") if d.exists()]


def port_busy(port: int) -> bool:
    """A bind and a connect, either says busy. The bind sees a range Windows reserves (WinError 10013) that nobody
    listens on; the connect sees a server on 0.0.0.0, beside which Windows lets a bind on 127.0.0.1 pass."""
    with socket.socket() as sock:
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            return True
    with socket.socket() as sock:
        sock.settimeout(0.2)  # a listener answers at once; a refused connect takes Windows two seconds
        return sock.connect_ex(("127.0.0.1", port)) == 0


def free_port(start: int, span: int = 300) -> int:
    """The first free port from `start` on (the player's own llm_server may hold it); `start + span` when all are busy."""
    port = start
    while port_busy(port) and port < start + span:
        port += 1
    return port


HIDDEN_DESKTOP = "btr_playtest"
_desktop: list = []  # the handle of the hidden desktop, kept open while this process lives
_spawn = threading.Lock()  # one child at a time gets the inheritable handles


def run_unseen(args: list[str], env: dict[str, str] | None = None, timeout: float | None = None) -> subprocess.CompletedProcess:
    """subprocess.run(args, env=env, capture_output=True, text=True, timeout=timeout) for a program with a window — a
    playtest's Godot. On Windows it runs on a hidden desktop of its own (CreateDesktop): its window never shows over the
    author's screen nor takes the focus, and it still renders, so the screenshots are whole. BTR_PLAYTEST_SHOW=1 puts
    it on the author's desktop again, to watch it play."""
    if os.name != "nt" or os.environ.get("BTR_PLAYTEST_SHOW"):
        return subprocess.run(args, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    import ctypes
    import ctypes.wintypes as wt
    import msvcrt
    import tempfile

    class StartupInfo(ctypes.Structure):
        _fields_ = [("cb", wt.DWORD), ("lpReserved", wt.LPWSTR), ("lpDesktop", wt.LPWSTR), ("lpTitle", wt.LPWSTR),
                    ("dwX", wt.DWORD), ("dwY", wt.DWORD), ("dwXSize", wt.DWORD), ("dwYSize", wt.DWORD),
                    ("dwXCountChars", wt.DWORD), ("dwYCountChars", wt.DWORD), ("dwFillAttribute", wt.DWORD),
                    ("dwFlags", wt.DWORD), ("wShowWindow", wt.WORD), ("cbReserved2", wt.WORD),
                    ("lpReserved2", ctypes.c_void_p), ("hStdInput", wt.HANDLE), ("hStdOutput", wt.HANDLE),
                    ("hStdError", wt.HANDLE)]

    class ProcessInfo(ctypes.Structure):
        _fields_ = [("hProcess", wt.HANDLE), ("hThread", wt.HANDLE), ("dwProcessId", wt.DWORD), ("dwThreadId", wt.DWORD)]

    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    u32 = ctypes.WinDLL("user32", use_last_error=True)
    u32.CreateDesktopW.restype = wt.HANDLE
    u32.CreateDesktopW.argtypes = [wt.LPCWSTR, wt.LPCWSTR, ctypes.c_void_p, wt.DWORD, wt.DWORD, ctypes.c_void_p]
    k32.CreateProcessW.argtypes = [wt.LPCWSTR, wt.LPWSTR, ctypes.c_void_p, ctypes.c_void_p, wt.BOOL, wt.DWORD,
                                   ctypes.c_void_p, wt.LPCWSTR, ctypes.POINTER(StartupInfo), ctypes.POINTER(ProcessInfo)]
    k32.WaitForSingleObject.argtypes = [wt.HANDLE, wt.DWORD]
    k32.TerminateProcess.argtypes = [wt.HANDLE, wt.UINT]
    k32.GetExitCodeProcess.argtypes = [wt.HANDLE, ctypes.POINTER(wt.DWORD)]
    k32.CloseHandle.argtypes = [wt.HANDLE]
    with _spawn:
        if not _desktop:
            handle = u32.CreateDesktopW(HIDDEN_DESKTOP, None, None, 0, 0x10000000, None)  # GENERIC_ALL; opens it if it is there
            if not handle:
                raise ctypes.WinError(ctypes.get_last_error())
            _desktop.append(handle)
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:  # a child of the child may hold the files
        out_path, err_path = Path(tmp) / "out", Path(tmp) / "err"
        with open(os.devnull, "rb") as fin, open(out_path, "wb") as fout, open(err_path, "wb") as ferr:
            handles = [msvcrt.get_osfhandle(f.fileno()) for f in (fin, fout, ferr)]
            si = StartupInfo(cb=ctypes.sizeof(StartupInfo), lpDesktop=HIDDEN_DESKTOP, dwFlags=0x100)  # STARTF_USESTDHANDLES
            si.hStdInput, si.hStdOutput, si.hStdError = handles
            flags, block = 0x08000000, None  # CREATE_NO_WINDOW
            if env is not None:
                text = "".join(f"{k}={v}\0" for k, v in sorted(env.items(), key=lambda kv: kv[0].upper())) + "\0"
                block, flags = ctypes.create_unicode_buffer(text, len(text) + 1), flags | 0x400  # CREATE_UNICODE_ENVIRONMENT
            pi = ProcessInfo()
            with _spawn:
                for h in handles:
                    os.set_handle_inheritable(h, True)
                try:
                    ok = k32.CreateProcessW(None, ctypes.create_unicode_buffer(subprocess.list2cmdline(args)), None, None,
                                            True, flags, block, None, ctypes.byref(si), ctypes.byref(pi))
                    error = ctypes.get_last_error()
                finally:
                    for h in handles:
                        os.set_handle_inheritable(h, False)
            if not ok:
                raise ctypes.WinError(error)
        timed_out, code = False, wt.DWORD()
        try:
            deadline = None if timeout is None else time.monotonic() + timeout
            while k32.WaitForSingleObject(pi.hProcess, 500) != 0:  # short waits: Ctrl+C still stops the run
                if deadline is not None and time.monotonic() > deadline:
                    timed_out = True
                    break
        finally:
            if timed_out or k32.WaitForSingleObject(pi.hProcess, 0) != 0:
                k32.TerminateProcess(pi.hProcess, 1)
                k32.WaitForSingleObject(pi.hProcess, 10_000)
            k32.GetExitCodeProcess(pi.hProcess, ctypes.byref(code))
            k32.CloseHandle(pi.hThread)
            k32.CloseHandle(pi.hProcess)
        out, err = (p.read_bytes().decode("utf-8", "replace").replace("\r\n", "\n") for p in (out_path, err_path))
    if timed_out:
        raise subprocess.TimeoutExpired(args, timeout, output=out, stderr=err)
    return subprocess.CompletedProcess(args, code.value, out, err)


def slug(name: str, sep: str = "_", empty: str = "item") -> str:
    import re

    s = "".join(TRANSLIT.get(ch, ch) for ch in name.lower())
    return re.sub(r"[^a-z0-9]+", sep, s).strip(sep)[:40] or empty
