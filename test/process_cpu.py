#!/usr/bin/env python3
"""Measure one child process' CPU time with a portable native boundary."""

from __future__ import annotations

import os
import pathlib
import subprocess
import tempfile
import sys


def native_path(value: str) -> str:
    if os.name == "nt" and len(value) >= 3 and value[0] == "/" and value[2] == "/" and value[1].isalpha():
        return value[1].upper() + ":" + value[2:].replace("/", "\\")
    if os.name == "nt" and (value == "/tmp" or value.startswith("/tmp/")):
        return str(pathlib.Path(tempfile.gettempdir(), value[5:]))
    return value


def windows_cpu_seconds(handle: int) -> float:
    import ctypes
    from ctypes import wintypes

    class FILETIME(ctypes.Structure):
        _fields_ = [("dwLowDateTime", wintypes.DWORD), ("dwHighDateTime", wintypes.DWORD)]

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    get_process_times = kernel32.GetProcessTimes
    get_process_times.argtypes = [
        wintypes.HANDLE,
        ctypes.POINTER(FILETIME),
        ctypes.POINTER(FILETIME),
        ctypes.POINTER(FILETIME),
        ctypes.POINTER(FILETIME),
    ]
    get_process_times.restype = wintypes.BOOL

    creation = FILETIME()
    exit_time = FILETIME()
    kernel = FILETIME()
    user = FILETIME()
    if not get_process_times(wintypes.HANDLE(handle), creation, exit_time, kernel, user):
        raise ctypes.WinError(ctypes.get_last_error())

    def ticks(filetime: FILETIME) -> int:
        return (int(filetime.dwHighDateTime) << 32) | int(filetime.dwLowDateTime)

    return (ticks(kernel) + ticks(user)) / 10_000_000.0


def main() -> int:
    if len(sys.argv) != 3:
        print("FAIL")
        return 0

    binary = native_path(sys.argv[1])
    corpus = native_path(sys.argv[2])
    timeout = float(os.environ.get("RIPWIRE_CPU_TIMEOUT", "120"))
    before = None
    if os.name != "nt":
        import resource

        usage = resource.getrusage(resource.RUSAGE_CHILDREN)
        before = usage.ru_utime + usage.ru_stime

    child = None
    try:
        child = subprocess.Popen(
            [binary, corpus, "--no-cache"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        child.communicate(timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        if child is not None:
            try:
                child.kill()
                child.communicate(timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                pass
        print("FAIL")
        return 0

    if child.returncode != 0:
        print("FAIL")
        return 0

    if os.name == "nt":
        try:
            seconds = windows_cpu_seconds(child._handle)
        except (OSError, ValueError):
            print("FAIL")
            return 0
    else:
        import resource

        usage = resource.getrusage(resource.RUSAGE_CHILDREN)
        seconds = usage.ru_utime + usage.ru_stime - before

    print(f"{max(0.0, seconds):.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
