#!/usr/bin/env python3
"""Run every test/*check.sh gate in parallel and report pass/fail.

The repo's own test/regression.sh runs ~210 gates in ONE sequential for-loop, which
exceeds the agent harness time ceiling. This runs the same scripts concurrently so a
full verification fits in one window. It does NOT modify regression.sh.

usage: pargates.py <repo-root> <ripwire-bin> [-j N] [--only substr] [--json out.json]
                   [--shard K/N] [--shard-plan] [--budget-scale F] [--exclude-list FILE]
"""
import concurrent.futures as cf
import atexit
import glob
import hashlib
import json
import os
import re
import shutil
import signal
import shlex
import subprocess
import sys
import tempfile
import threading
import time

root = os.path.abspath(sys.argv[1])
binp = os.path.abspath(sys.argv[2])
windows = os.name == "nt"

if windows:
    import ctypes
    from ctypes import wintypes

    class _LargeInteger( ctypes.Structure ):
        _fields_ = [ ( "QuadPart", ctypes.c_longlong ) ]

    class _BasicLimitInformation( ctypes.Structure ):
        _fields_ = [
            ( "PerProcessUserTimeLimit", _LargeInteger ),
            ( "PerJobUserTimeLimit", _LargeInteger ),
            ( "LimitFlags", wintypes.DWORD ),
            ( "MinimumWorkingSetSize", ctypes.c_size_t ),
            ( "MaximumWorkingSetSize", ctypes.c_size_t ),
            ( "ActiveProcessLimit", wintypes.DWORD ),
            ( "Affinity", ctypes.c_size_t ),
            ( "PriorityClass", wintypes.DWORD ),
            ( "SchedulingClass", wintypes.DWORD ),
        ]

    class _IoCounters( ctypes.Structure ):
        _fields_ = [
            ( "ReadOperationCount", _LargeInteger ),
            ( "WriteOperationCount", _LargeInteger ),
            ( "OtherOperationCount", _LargeInteger ),
            ( "ReadTransferCount", _LargeInteger ),
            ( "WriteTransferCount", _LargeInteger ),
            ( "OtherTransferCount", _LargeInteger ),
        ]

    class _ExtendedLimitInformation( ctypes.Structure ):
        _fields_ = [
            ( "BasicLimitInformation", _BasicLimitInformation ),
            ( "IoInfo", _IoCounters ),
            ( "ProcessMemoryLimit", ctypes.c_size_t ),
            ( "JobMemoryLimit", ctypes.c_size_t ),
            ( "PeakProcessMemoryUsed", ctypes.c_size_t ),
            ( "PeakJobMemoryUsed", ctypes.c_size_t ),
        ]

    class _BasicAccountingInformation( ctypes.Structure ):
        _fields_ = [
            ( "TotalUserTime", _LargeInteger ),
            ( "TotalKernelTime", _LargeInteger ),
            ( "ThisPeriodTotalUserTime", _LargeInteger ),
            ( "ThisPeriodTotalKernelTime", _LargeInteger ),
            ( "TotalPageFaultCount", wintypes.DWORD ),
            ( "TotalProcesses", wintypes.DWORD ),
            ( "ActiveProcesses", wintypes.DWORD ),
            ( "TotalTerminatedProcesses", wintypes.DWORD ),
        ]

    _kernel32 = ctypes.WinDLL( "kernel32", use_last_error=True )
    _kernel32.CreateJobObjectW.argtypes = [ wintypes.LPVOID, wintypes.LPCWSTR ]
    _kernel32.CreateJobObjectW.restype = wintypes.HANDLE
    _kernel32.SetInformationJobObject.argtypes = [ wintypes.HANDLE, wintypes.INT, wintypes.LPVOID, wintypes.DWORD ]
    _kernel32.SetInformationJobObject.restype = wintypes.BOOL
    _kernel32.AssignProcessToJobObject.argtypes = [ wintypes.HANDLE, wintypes.HANDLE ]
    _kernel32.AssignProcessToJobObject.restype = wintypes.BOOL
    _kernel32.QueryInformationJobObject.argtypes = [ wintypes.HANDLE, wintypes.INT, wintypes.LPVOID, wintypes.DWORD, ctypes.POINTER( wintypes.DWORD ) ]
    _kernel32.QueryInformationJobObject.restype = wintypes.BOOL
    _kernel32.TerminateJobObject.argtypes = [ wintypes.HANDLE, wintypes.UINT ]
    _kernel32.TerminateJobObject.restype = wintypes.BOOL
    class _ProcessEntry32W( ctypes.Structure ):
        _fields_ = [
            ( "dwSize", wintypes.DWORD ),
            ( "cntUsage", wintypes.DWORD ),
            ( "th32ProcessID", wintypes.DWORD ),
            ( "th32DefaultHeapID", ctypes.c_size_t ),
            ( "th32ModuleID", wintypes.DWORD ),
            ( "cntThreads", wintypes.DWORD ),
            ( "th32ParentProcessID", wintypes.DWORD ),
            ( "pcPriClassBase", ctypes.c_long ),
            ( "dwFlags", wintypes.DWORD ),
            ( "szExeFile", wintypes.WCHAR * 260 ),
        ]
    class _ThreadEntry32( ctypes.Structure ):
        _fields_ = [
            ( "dwSize", wintypes.DWORD ),
            ( "cntUsage", wintypes.DWORD ),
            ( "th32ThreadID", wintypes.DWORD ),
            ( "th32OwnerProcessID", wintypes.DWORD ),
            ( "tpBasePri", ctypes.c_long ),
            ( "tpDeltaPri", ctypes.c_long ),
            ( "dwFlags", wintypes.DWORD ),
        ]
    _kernel32.CreateToolhelp32Snapshot.argtypes = [ wintypes.DWORD, wintypes.DWORD ]
    _kernel32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    _kernel32.Process32FirstW.argtypes = [ wintypes.HANDLE, ctypes.POINTER( _ProcessEntry32W ) ]
    _kernel32.Process32FirstW.restype = wintypes.BOOL
    _kernel32.Process32NextW.argtypes = [ wintypes.HANDLE, ctypes.POINTER( _ProcessEntry32W ) ]
    _kernel32.Process32NextW.restype = wintypes.BOOL
    _kernel32.Thread32First.argtypes = [ wintypes.HANDLE, ctypes.POINTER( _ThreadEntry32 ) ]
    _kernel32.Thread32First.restype = wintypes.BOOL
    _kernel32.Thread32Next.argtypes = [ wintypes.HANDLE, ctypes.POINTER( _ThreadEntry32 ) ]
    _kernel32.Thread32Next.restype = wintypes.BOOL
    _kernel32.OpenThread.argtypes = [ wintypes.DWORD, wintypes.BOOL, wintypes.DWORD ]
    _kernel32.OpenThread.restype = wintypes.HANDLE
    _kernel32.ResumeThread.argtypes = [ wintypes.HANDLE ]
    _kernel32.ResumeThread.restype = wintypes.DWORD
    _kernel32.CloseHandle.argtypes = [ wintypes.HANDLE ]
    _kernel32.CloseHandle.restype = wintypes.BOOL
    _JOB_OBJECT_EXTENDED_LIMIT_INFORMATION = 9
    _JOB_OBJECT_BASIC_ACCOUNTING_INFORMATION = 1
    _JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000
    _CREATE_SUSPENDED = 0x00000004

    class _WindowsJob:
        def __init__( self ):
            self.handle = _kernel32.CreateJobObjectW( None, None )
            if not self.handle:
                raise ctypes.WinError( ctypes.get_last_error() )
            info = _ExtendedLimitInformation()
            info.BasicLimitInformation.LimitFlags = _JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            if not _kernel32.SetInformationJobObject( self.handle, _JOB_OBJECT_EXTENDED_LIMIT_INFORMATION,
                                                       ctypes.byref( info ), ctypes.sizeof( info ) ):
                error = ctypes.get_last_error()
                _kernel32.CloseHandle( self.handle )
                self.handle = None
                raise ctypes.WinError( error )

        def assign( self, process ):
            if _kernel32.AssignProcessToJobObject( self.handle, wintypes.HANDLE( process._handle ) ):
                return True
            error = ctypes.get_last_error()
            _kernel32.CloseHandle( self.handle )
            self.handle = None
            raise OSError( error, "AssignProcessToJobObject failed" )

        def alive( self ):
            info = _BasicAccountingInformation()
            size = wintypes.DWORD()
            if not _kernel32.QueryInformationJobObject( self.handle, _JOB_OBJECT_BASIC_ACCOUNTING_INFORMATION,
                                                         ctypes.byref( info ), ctypes.sizeof( info ), ctypes.byref( size ) ):
                return True
            return info.ActiveProcesses != 0

        def terminate( self ):
            if self.handle:
                _kernel32.TerminateJobObject( self.handle, 1 )

        def close( self ):
            if self.handle:
                _kernel32.CloseHandle( self.handle )
                self.handle = None


def _attach_windows_job( process ):
    if not windows:
        return None
    job = _WindowsJob()
    job.assign( process )
    return job


def _resume_windows_process( process ):
    """Resume the suspended primary thread after the process has entered its kill-on-close Job Object."""
    if not windows:
        return
    snapshot = _kernel32.CreateToolhelp32Snapshot( 0x00000004, 0 )  # TH32CS_SNAPTHREAD
    invalid = ctypes.c_void_p( -1 ).value
    if not snapshot or snapshot == invalid:
        raise ctypes.WinError( ctypes.get_last_error() )
    entry = _ThreadEntry32()
    entry.dwSize = ctypes.sizeof( entry )
    try:
        if not _kernel32.Thread32First( snapshot, ctypes.byref( entry ) ):
            raise ctypes.WinError( ctypes.get_last_error() )
        while True:
            if entry.th32OwnerProcessID == process.pid:
                thread = _kernel32.OpenThread( 0x0002, False, entry.th32ThreadID )  # THREAD_SUSPEND_RESUME
                if not thread:
                    raise ctypes.WinError( ctypes.get_last_error() )
                try:
                    previous = _kernel32.ResumeThread( thread )
                finally:
                    _kernel32.CloseHandle( thread )
                if previous == 0xFFFFFFFF:
                    raise ctypes.WinError( ctypes.get_last_error() )
                return
            if not _kernel32.Thread32Next( snapshot, ctypes.byref( entry ) ):
                break
    finally:
        _kernel32.CloseHandle( snapshot )
    raise OSError( "suspended gate has no resumable primary thread" )


def _close_windows_job( process ):
    job = getattr( process, "_ripwire_windows_job", None ) if process is not None else None
    if job is not None:
        job.close()


def _windows_descendant_pids( root_pid ):
    if not windows:
        return []
    snapshot = _kernel32.CreateToolhelp32Snapshot( 0x00000002, 0 )
    invalid = ctypes.c_void_p( -1 ).value
    if not snapshot or snapshot == invalid:
        return []
    parents = {}
    entry = _ProcessEntry32W()
    entry.dwSize = ctypes.sizeof( entry )
    try:
        if not _kernel32.Process32FirstW( snapshot, ctypes.byref( entry ) ):
            return []
        while True:
            parents.setdefault( entry.th32ParentProcessID, [] ).append( entry.th32ProcessID )
            if not _kernel32.Process32NextW( snapshot, ctypes.byref( entry ) ):
                break
    finally:
        _kernel32.CloseHandle( snapshot )
    descendants = []
    pending = [ root_pid ]
    while pending:
        parent = pending.pop()
        for child in parents.get( parent, [] ):
            if child not in descendants:
                descendants.append( child )
                pending.append( child )
    return descendants


def _windows_terminate_pids( pids ):
    if not windows:
        return
    for pid in sorted( set( pids ) ):
        if pid <= 0:
            continue
        try:
            subprocess.run( [ "taskkill", "/PID", str( pid ), "/F" ],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            timeout=KILL_GRACE_SEC, check=False )
        except ( OSError, subprocess.TimeoutExpired ):
            pass


def _msys_path(path):
    """Convert an absolute Windows path to the spelling consumed by Git Bash."""
    if not windows:
        return path
    # Git Bash already uses /d/... for a native path on drive D:. Do not let
    # ntpath.abspath reinterpret that spelling as C:\\d\\..., which breaks
    # RIPWIRE_HEADBIN when the runner's TEMP directory is on another drive.
    if len(path) >= 3 and path[0] == "/" and path[1].isalpha() and path[2] == "/":
        return path.replace( "\\", "/" )
    drive, tail = os.path.splitdrive(os.path.abspath(path))
    if drive:
        return "/" + drive[0].lower() + tail.replace("\\", "/")
    return path.replace("\\", "/")


def _native_windows_path(path):
    """Translate a Git Bash absolute path before native Python joins or opens it."""
    if not windows:
        return path
    if path == "/tmp":
        return os.path.join( os.environ.get( "LOCALAPPDATA", os.path.dirname( tempfile.gettempdir() ) ), "Temp" )
    if path.startswith( "/tmp/" ):
        temp_root = os.path.join( os.environ.get( "LOCALAPPDATA", os.path.dirname( tempfile.gettempdir() ) ), "Temp" )
        return temp_root.replace( "\\", "/" ) + path[ 4: ]
    if len( path ) >= 3 and path[ 0 ] == "/" and path[ 1 ].isalpha() and path[ 2 ] in "/\\":
        return path[ 1 ].upper() + ":" + path[ 2: ]
    return path


def _git_bash():
    """Select Git Bash, never the Windows WSL launcher named bash.exe."""
    if not windows:
        return "bash"
    requested = os.environ.get("RIPWIRE_BASH")
    candidates = [requested] if requested else []
    program_files = [os.environ.get("ProgramFiles", r"C:\\Program Files"),
                     os.environ.get("ProgramW6432", r"C:\\Program Files")]
    candidates.extend(os.path.join(p, "Git", "usr", "bin", "bash.exe") for p in program_files if p)
    candidates.extend((shutil.which("bash.exe"), shutil.which("bash")))
    for candidate in candidates:
        if not candidate or not os.path.isfile(candidate):
            continue
        normalized = os.path.normcase(os.path.abspath(candidate))
        if "\\windows\\system32\\" in normalized or "\\windowsapps\\" in normalized:
            continue
        return candidate
    raise SystemExit("Windows gate harness needs Git Bash; refusing to invoke the WSL bash launcher")


def _windows_vcvars_environment():
    if not windows:
        return {}
    candidates = []
    requested = os.environ.get( "RIPWIRE_VCVARS" )
    if requested:
        candidates.append( requested )
    program_files_x86 = os.environ.get( "ProgramFiles(x86)", r"C:\Program Files (x86)" )
    candidates.append( os.path.join( program_files_x86, "Microsoft Visual Studio", "2019", "BuildTools",
                                     "VC", "Auxiliary", "Build", "vcvarsall.bat" ) )
    candidates.append( os.path.join( program_files_x86, "Microsoft Visual Studio", "2022", "BuildTools",
                                     "VC", "Auxiliary", "Build", "vcvarsall.bat" ) )
    comspec = os.environ.get( "ComSpec", r"C:\Windows\System32\cmd.exe" )
    for candidate in candidates:
        if not candidate or not os.path.isfile( candidate ):
            continue
        try:
            result = subprocess.run(
                f'"{comspec}" /d /c call "{candidate}" amd64 10.0.19041.0 >nul && set',
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=60, check=False )
        except ( OSError, subprocess.TimeoutExpired ):
            continue
        if result.returncode != 0:
            continue
        values = {}
        for raw_line in result.stdout.decode( "mbcs", errors="replace" ).splitlines():
            if "=" not in raw_line:
                continue
            key, value = raw_line.split( "=", 1 )
            if key:
                values[key] = value
        return values
    return {}


def _windows_gate_environment():
    """Provide native Python/temporary paths while shell gates keep POSIX syntax."""
    if not windows:
        return {}, _git_bash()
    shell = _git_bash()
    native_tmp = os.path.join( _native_windows_path( tempfile.gettempdir() ), f"ripwire-pargates-{os.getpid()}" )
    native_tmp = native_tmp.replace( "\\", "/" )
    native_python = sys.executable.replace( "\\", "/" )
    os.makedirs(native_tmp, exist_ok=True)
    tools = os.path.join(native_tmp, "bin")
    os.makedirs(tools, exist_ok=True)
    sitecustomize = os.path.join(tools, "sitecustomize.py")
    with open(sitecustomize, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(
            "import os, sys\n"
            "for _name in (\"stdout\", \"stderr\"):\n"
            "    _stream = getattr( sys, _name, None )\n"
            "    if _stream is not None and hasattr( _stream, \"reconfigure\" ):\n"
            "        _stream.reconfigure( newline=chr( 10 ) )\n"
            "_tmp = os.environ.get( \"RW_MSYS_TMP\", \"\" ).rstrip( \"/\\\\\" )\n"
            "def _map_tmp( _arg ):\n"
            "    if not _tmp: return _arg\n"
            "    if _arg == \"/tmp\": return _tmp\n"
            "    if _arg.startswith( \"/tmp/\" ): return _tmp + _arg[ 4: ]\n"
            "    return _arg\n"
            "if _tmp: sys.argv = [ sys.argv[ 0 ] ] + [ _map_tmp( _arg ) for _arg in sys.argv[ 1: ] ]\n"
            "def _native_env( _arg ):\n"
            "    if _arg == \"/tmp\": return _tmp\n"
            "    if _arg.startswith( \"/tmp/\" ): return _tmp + _arg[ 4: ]\n"
            "    if len( _arg ) >= 3 and _arg[ 0 ] == \"/\" and _arg[ 1 ].isalpha() and _arg[ 2 ] == \"/\":\n"
            "        return _arg[ 1 ].upper() + \":\" + _arg[ 2: ]\n"
            "    return _arg\n"
            "for _name in ( \"TMPDIR\", \"TEMP\", \"TMP\", \"XDG_CACHE_HOME\" ):\n"
            "    _value = os.environ.get( _name, \"\" )\n"
            "    if _value: os.environ[ _name ] = _native_env( _value )\n"
        )
    msys_tmp = os.path.join( os.environ.get( "LOCALAPPDATA", os.path.dirname( tempfile.gettempdir() ) ), "Temp" )
    msys_tmp = msys_tmp.replace( "\\", "/" )
    python3 = os.path.join(tools, "python3")
    with open(python3, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("#!/usr/bin/env bash\n")
        fh.write(f"PYTHON_NATIVE={shlex.quote(native_python)}\n")
        fh.write(f"MSYS_TMP_NATIVE={shlex.quote(msys_tmp)}\n")
        fh.write("map_native_arg() {\n"
                 "    case \"${1-}\" in\n"
                 "        /tmp) printf '%s' \"$MSYS_TMP_NATIVE\";;\n"
                 "        /tmp/*) printf '%s%s' \"$MSYS_TMP_NATIVE\" \"${1#/tmp}\";;\n"
                 "        /[A-Za-z]/*) printf '%s:%s' \"${1:1:1}\" \"${1:2}\";;\n"
                 "        *) printf '%s' \"${1-}\";;\n"
                 "    esac\n"
                 "}\n"
                 "map_native_args() {\n"
                 "    mapped=()\n"
                 "    for arg in \"$@\"; do mapped+=(\"$( map_native_arg \"$arg\" )\"); done\n"
                 "}\n")
        fh.write("if [ \"${1-}\" != \"-c\" ]; then\n")
        fh.write("    map_native_args \"$@\"\n")
        fh.write("    exec \"$PYTHON_NATIVE\" \"${mapped[@]}\"\n")
        fh.write("fi\n")
        inline_runner = (
            "import os,sys\n"
            "def msys_path(path):\n"
            "    if len(path)>=3 and path[0]==\"/\" and path[1].isalpha() and path[2] in \"/\\\\\": return \"/\"+path[1].lower()+path[2:]\n"
            "    if len(path)>=3 and path[1]==\":\" and path[0].isalpha(): return \"/\"+path[0].lower()+path[2:].replace(\"\\\\\",\"/\")\n"
            "    return path\n"
            "def map_embedded_paths(code):\n"
            "    pairs=[]\n"
            "    for name in (\"TMPDIR\",\"TMP\",\"TEMP\"):\n"
            "        native=os.environ.get(name,\"\")\n"
            "        if native: native_source=native.replace(\"\\\\\",\"/\"); pairs.append((native, native_source)); pairs.append((msys_path(native), native_source))\n"
            "    native_root=os.environ.get(\"RIPWIRE_NATIVE_ROOT\",\"\"); pairs.append((os.environ.get(\"RIPWIRE_MSYS_ROOT\",\"\"), native_root.replace(\"\\\\\",\"/\")))\n"
            "    for old,new in pairs:\n"
            "        if old and new: code=code.replace(old,new)\n"
            "    return code.replace(\"/tmp/\", os.environ.get(\"RW_MSYS_TMP\", \"/tmp\")+\"/\")\n"
            "code=map_embedded_paths(sys.argv[1])\n"
            "sys.argv=[\"-c\"]+sys.argv[2:]\n"
            "exec(compile(code,\"<string>\",\"exec\"), {\"__name__\":\"__main__\",\"__file__\":\"<string>\"})"
        )
        fh.write("map_native_args \"$@\"\n")
        fh.write("arg_bytes=0\n")
        fh.write("for arg in \"${mapped[@]}\"; do arg_bytes=$(( arg_bytes + ${#arg} + 1 )); done\n")
        fh.write("if [ \"$arg_bytes\" -le 20000 ]; then\n")
        fh.write("    map_native_args \"$2\" \"${@:3}\"\n")
        fh.write("    exec \"$PYTHON_NATIVE\" -c " + shlex.quote( inline_runner ) + " \"${mapped[@]}\"\n")
        fh.write("fi\n")
        fh.write("arg_dir=\"${TMPDIR:-/tmp}\"\n")
        fh.write("case \"$arg_dir\" in /tmp) arg_dir=\"$MSYS_TMP_NATIVE\";; /tmp/*) arg_dir=\"$MSYS_TMP_NATIVE${arg_dir#/tmp}\";; esac\n")
        fh.write("mkdir -p \"$arg_dir\" || exit 1\n")
        fh.write("arg_file=\"$arg_dir/ripwire-python-args.$$\"\n")
        fh.write("trap 'rm -f -- \"$arg_file\"' EXIT\n")
        fh.write("printf '%s\\0' \"${mapped[@]}\" > \"$arg_file\" || exit 1\n")
        python_runner = ( "import os,pathlib,sys; a=pathlib.Path(sys.argv[1]).read_bytes().split(bytes([0]))[:-1]; "
                          "sys.argv=[\"-c\"]+[x.decode(\"utf-8\",\"surrogateescape\") for x in a[2:]]; "
                          "exec(compile(a[1].decode(\"utf-8\",\"surrogateescape\").replace(\"/tmp/\", os.environ.get(\"RW_MSYS_TMP\", \"/tmp\")+\"/\"),\"<string>\",\"exec\"), "
                          "{\"__name__\":\"__main__\",\"__file__\":\"<string>\"})" )
        fh.write( "exec \"$PYTHON_NATIVE\" -c " + shlex.quote( python_runner ) + " \"$arg_file\"\n" )
    try:
        os.chmod(python3, 0o755)
    except OSError:
        pass

    # Git for Windows does not ship xmllint.  Keep the existing XML assertions live instead of letting
    # Windows-only runs turn them into skips: this shim exposes the small --noout/--format/--html surface
    # used by the gates and delegates parsing to the stdlib implementation committed in test/xmlcheck.py.
    xmllint = os.path.join(tools, "xmllint")
    xmlcheck = os.path.join(root, "test", "xmlcheck.py").replace( "\\", "/" )
    with open(xmllint, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("#!/usr/bin/env bash\n")
        fh.write("exec " + shlex.quote( python3 ) + " " + shlex.quote( xmlcheck ) + " \"$@\"\n")
    try:
        os.chmod(xmllint, 0o755)
    except OSError:
        pass

    vcvars = _windows_vcvars_environment()
    llvm_candidates = [
        os.environ.get( "RIPWIRE_LLVM_BIN", "" ),
        os.path.join( os.environ.get( "ProgramFiles", r"C:\Program Files" ), "LLVM", "bin" ),
        os.path.join( os.environ.get( "ProgramW6432", r"C:\Program Files" ), "LLVM", "bin" ),
    ]
    llvm_bin = next( ( path for path in llvm_candidates if path and os.path.isfile( os.path.join( path, "clang++.exe" ) ) ), "" )
    if not llvm_bin:
        clang_path = shutil.which( "clang++.exe" ) or shutil.which( "clang++" )
        if clang_path:
            llvm_bin = os.path.dirname( clang_path )
    clangxx = os.path.join( llvm_bin, "clang++.exe" ) if llvm_bin else ""
    clangcl = os.path.join( llvm_bin, "clang-cl.exe" ) if llvm_bin else ""
    clang = os.path.join( llvm_bin, "clang.exe" ) if llvm_bin else ""
    compiler = clangcl if os.path.isfile( clangcl ) else clangxx
    if compiler and os.path.isfile( compiler ):
        cxx_wrapper = os.path.join( tools, "ripwire-cxx" )
        with open( cxx_wrapper, "w", encoding="utf-8", newline="\n" ) as fh:
            fh.write( "#!/usr/bin/env bash\n" )
            if compiler.lower().endswith( "clang-cl.exe" ):
                fh.write( "export MSYS_NO_PATHCONV=1\n"
                          "rw_native_path() {\n"
                          "    case \"${1-}\" in\n"
                          "        /tmp) printf '%s' \"$RIPWIRE_NATIVE_TMP\";;\n"
                          "        /tmp/*) printf '%s%s' \"$RIPWIRE_NATIVE_TMP\" \"${1#/tmp}\";;\n"
                          "        /[A-Za-z]/*) printf '%s:%s' \"${1:1:1}\" \"${1:2}\";;\n"
                          "        *) printf '%s' \"${1-}\";;\n"
                          "    esac\n"
                          "}\n"
                          "emit_source=0\n"
                          "for arg in \"$@\"; do [ \"$arg\" = \"-S\" ] && emit_source=1; done\n"
                          "args=()\n"
                          "take_output=0\n"
                          "for arg in \"$@\"; do\n"
                          "    if [ \"$take_output\" = 1 ]; then\n"
                          "        if [ \"$emit_source\" = 1 ]; then args+=(/clang:-o \"/clang:$( rw_native_path \"$arg\" )\"); else args+=(-o \"$( rw_native_path \"$arg\" )\"); fi\n"
                          "        take_output=0\n"
                          "        continue\n"
                          "    fi\n"
                          "    case \"$arg\" in\n"
                          "        -o) take_output=1;;\n"
                          "        -std=*|--std=*) ;;\n"
                          "        -fsyntax-only) args+=(/Zs);;\n"
                          "        -S) args+=(/clang:-S);;\n"
                          "        -emit-llvm|-fno-discard-value-names|-mllvm) args+=(\"/clang:$arg\");;\n"
                          "        -basic-aa-separate-storage*) args+=(\"/clang:$arg\");;\n"
                          "        -I/*) args+=(\"-I$( rw_native_path \"${arg#-I}\" )\");;\n"
                          "        /tmp/*|/[A-Za-z]/*) args+=(\"$( rw_native_path \"$arg\" )\");;\n"
                          "        *) args+=(\"$arg\");;\n"
                          "    esac\n"
                          "done\n"
                          "needs_link=1\n"
                          "has_platform=0\n"
                          "for arg in \"$@\"; do\n"
                          "    case \"$arg\" in -c|/c|-E|-S|-fsyntax-only) needs_link=0;; *platform_compat.cpp) has_platform=1;; esac\n"
                          "done\n"
                          "if [ \"$needs_link\" = 1 ] && [ \"$has_platform\" = 0 ] && [ -n \"${RIPWIRE_PLATFORM_COMPAT_CPP:-}\" ]; then\n"
                          "    args+=(\"$RIPWIRE_PLATFORM_COMPAT_CPP\" /link ws2_32.lib)\n"
                          "fi\n"
                          "exec \"$RIPWIRE_CXX_REAL\" /TP -clang:-std=c++23 /EHsc /permissive- "
                          "/DWIN32 /D_WINDOWS /utf-8 /FI \"$RIPWIRE_PLATFORM_COMPAT\" /D_MSVC_LANG=202302L "
                          "/D_CRT_SECURE_NO_WARNINGS /D_CRT_NONSTDC_NO_DEPRECATE \"${args[@]}\"\n" )
            else:
                fh.write( "exec \"$RIPWIRE_CXX_REAL\" -D_MSVC_LANG=202302L -D_CRT_SECURE_NO_WARNINGS "
                          "-D_CRT_NONSTDC_NO_DEPRECATE \"$@\"\n" )
        c_driver = os.path.join( tools, "ripwire-c" )
        with open( c_driver, "w", encoding="utf-8", newline="\n" ) as fh:
            fh.write( "#!/usr/bin/env bash\nexport MSYS_NO_PATHCONV=1\n" )
            fh.write( "rw_native_path() {\n"
                      "    case \"${1-}\" in\n"
                      "        /tmp) printf '%s' \"$RIPWIRE_NATIVE_TMP\";;\n"
                      "        /tmp/*) printf '%s%s' \"$RIPWIRE_NATIVE_TMP\" \"${1#/tmp}\";;\n"
                      "        /[A-Za-z]/*) printf '%s:%s' \"${1:1:1}\" \"${1:2}\";;\n"
                      "        *) printf '%s' \"${1-}\";;\n"
                      "    esac\n"
                      "}\n"
                      "args=()\n"
                      "for arg in \"$@\"; do\n"
                      "    case \"$arg\" in\n"
                      "        -I/*) args+=(\"-I$( rw_native_path \"${arg#-I}\" )\");;\n"
                      "        /tmp/*|/[A-Za-z]/*) args+=(\"$( rw_native_path \"$arg\" )\");;\n"
                      "        *) args+=(\"$arg\");;\n"
                      "    esac\n"
                      "done\n"
                      "exec \"$RIPWIRE_CC_REAL\" -D_CRT_SECURE_NO_WARNINGS -D_CRT_NONSTDC_NO_DEPRECATE \"${args[@]}\"\n" )
        for wrapper in ( cxx_wrapper, c_driver ):
            try:
                os.chmod( wrapper, 0o755 )
            except OSError:
                pass
        driver_script = "#!/usr/bin/env bash\nexec \"$RIPWIRE_CXX\" \"$@\"\n"
        c_driver_script = "#!/usr/bin/env bash\nexec \"$RIPWIRE_CC\" \"$@\"\n"
        for name, content in ( ( "c++", driver_script ), ( "g++", driver_script ), ( "clang++", driver_script ),
                                ( "cc", c_driver_script ), ( "gcc", c_driver_script ), ( "clang", c_driver_script ) ):
            alias = os.path.join( tools, name )
            with open( alias, "w", encoding="utf-8", newline="\n" ) as fh:
                fh.write( content )
            try:
                os.chmod( alias, 0o755 )
            except OSError:
                pass

    def cleanup():
        shutil.rmtree(native_tmp, ignore_errors=True)

    atexit.register(cleanup)
    toolchain_path = vcvars.get( "PATH", vcvars.get( "Path", "" ) )
    native_path = ";".join( part for part in ( toolchain_path + ";" + os.environ.get( "PATH", "" ) ).split( ";" ) if part )
    path_components = []
    seen_path_components = set()
    for part in native_path.split( ";" ):
        if not part:
            continue
        msys_part = _msys_path( part )
        key = msys_part.rstrip( "/" ).casefold()
        if key in seen_path_components:
            continue
        seen_path_components.add( key )
        path_components.append( msys_part )
    # The child is Git Bash with a deliberately rebuilt PATH.  Keep Git's own POSIX utilities in that PATH;
    # otherwise dirname/mktemp/rm/cat disappear and a gate reports a misleading product or toolchain failure.
    git_usr_bin = os.path.dirname( os.path.abspath( shell ) )
    git_root = os.path.dirname( os.path.dirname( git_usr_bin ) )
    git_bin = os.path.join( git_root, "bin" )
    git_core_perl = os.path.join( git_usr_bin, "core_perl" )
    path_components.insert( 0, _msys_path( git_bin ) )
    if os.path.isdir( git_core_perl ):
        path_components.insert( 0, _msys_path( git_core_perl ) )
    path_components.insert( 0, _msys_path( git_usr_bin ) )
    llvm_runtime = next( iter( sorted( glob.glob( os.path.join( llvm_bin, "..", "lib", "clang", "*", "lib", "windows" ) ) ) ), "" ) if llvm_bin else ""
    if llvm_bin:
        path_components.insert( 0, _msys_path( llvm_bin ) )
    if llvm_runtime:
        path_components.insert( 0, _msys_path( llvm_runtime ) )
    gate_path = ":".join( [ _msys_path( tools ) ] + path_components )
    fifo_bin = os.path.join( tools, "ripwire-fifo" )
    with open( fifo_bin, "w", encoding="utf-8", newline="\n" ) as fh:
        fh.write( "#!/usr/bin/env bash\n" )
        fh.write( "if [ \"${1-}\" = \"--mcp\" ]; then\n" )
        fh.write( "    cat | \"$RIPWIRE_REAL_BIN\" \"$@\"\n" )
        fh.write( "else\n" )
        fh.write( "    exec \"$RIPWIRE_REAL_BIN\" \"$@\"\n" )
        fh.write( "fi\n" )
    try:
        os.chmod( fifo_bin, 0o755 )
    except OSError:
        pass
    env = {
        "RIPWIRE_BIN": _msys_path( binp ),
        "RIPWIRE_FIFO_BIN": _msys_path( fifo_bin ),
        "RIPWIRE_REAL_BIN": binp.replace( "\\", "/" ),
        "RIPWIRE_PROBE": _msys_path( binp[:-4] + "_probe.exe" if binp.lower().endswith( ".exe" ) else binp + "_probe" ),
        "RIPWIRE_BASH": shell.replace( "\\", "/" ),
        "RW_BASH": shell.replace( "\\", "/" ),
        "RIPWIRE_PLATFORM_COMPAT": os.path.join( root, "src", "infra", "platform_compat.h" ).replace( "\\", "/" ),
        "RIPWIRE_PLATFORM_COMPAT_CPP": os.path.join( root, "src", "infra", "platform_compat.cpp" ).replace( "\\", "/" ),
        "RIPWIRE_NATIVE_TMP": msys_tmp,
        "RIPWIRE_NATIVE_PATH": native_path,
        "RIPWIRE_NATIVE_ROOT": root.replace( "\\", "/" ),
        "RIPWIRE_MSYS_ROOT": _msys_path( root ),
        "RIPWIRE_PYTHON": native_python,
        "RW_MSYS_TMP": msys_tmp,
        "PATH": gate_path,
        "PYTHONPATH": tools + os.pathsep + os.environ.get("PYTHONPATH", ""),
        "TMPDIR": _msys_path( native_tmp ),
        "TEMP": native_tmp,
        "TMP": native_tmp,
        "XDG_CACHE_HOME": _msys_path( native_tmp ),
        # Preserve merge-scout ref tokens byte-for-byte.  MSYS would otherwise rewrite a payload such as
        # --merge-scout=--output=/c/... into --merge-scout=--output=C:/..., changing the token before the
        # product can reject it.  Keep conversion enabled for ordinary path arguments (Git needs C:/...)
        # and exclude only this option's embedded ref payload.
        "MSYS2_ARG_CONV_EXCL": "--merge-scout=",
    }

    if os.environ.get( "RIPWIRE_HEADBIN" ):
        env[ "RIPWIRE_HEADBIN" ] = _msys_path( os.environ[ "RIPWIRE_HEADBIN" ] )
    if compiler and os.path.isfile( compiler ):
        env["RIPWIRE_CXX_REAL"] = _msys_path( compiler )
        env["RIPWIRE_CC_REAL"] = _msys_path( clang if os.path.isfile( clang ) else compiler )
        if os.path.isfile( clangxx ):
            # GCC-shape probes must undefine __clang__ without first preincluding the MSVC CRT.  Keep the
            # clang-cl wrapper for Windows-aware gates, but expose the sibling GNU driver for isolated probes.
            env["RIPWIRE_CXX_GNU"] = _msys_path( clangxx )
        env["RIPWIRE_CXX"] = _msys_path( os.path.join( tools, "ripwire-cxx" ) )
        env["RIPWIRE_CC"] = _msys_path( os.path.join( tools, "ripwire-c" ) )
        env["CXX"] = env["RIPWIRE_CXX"]
        env["CC"] = env["RIPWIRE_CC"]
    for key in ( "INCLUDE", "LIB", "LIBPATH", "VCToolsInstallDir", "WindowsSdkDir", "WindowsSDKVersion",
                 "UniversalCRTSdkDir", "UCRTVersion" ):
        if vcvars.get( key ):
            env[key] = vcvars[key]
    return env, shell


WINDOWS_GATE_ENV, GATE_SHELL = _windows_gate_environment()
WINDOWS_MSYS_SHELL = windows and "\\git\\" in os.path.normcase( os.path.abspath( GATE_SHELL ) )
FIFO_GATES = {
    "freshnesscheck.sh", "mcpeditcheck.sh", "mcpincrementalcheck.sh",
    "mcpreloadcheck.sh", "mcpeditracecheck.sh", "mcpstalecheck.sh", "mcpwatchercheck.sh",
    "qsnapprefetchcheck.sh",
}
jobs = 6
only = None
jsonout = None
shard = None          # (k, n): run only the k-th of n deterministic slices of the gate list
shard_plan = False    # print every slice's membership and predicted weight, run nothing
budget_scale = 1.0    # scales the DEFAULT budget; a declared override acts as a FLOOR under it -- CI passes >1
exclude_list = None   # a committed file naming gates this leg does not run (one per line, # comments)
args = sys.argv[3:]
for i, a in enumerate(args):
    if a == "-j":
        jobs = int(args[i + 1])
    elif a == "--only":
        only = args[i + 1]
    elif a == "--json":
        jsonout = args[i + 1]
    elif a == "--shard":
        k, n = args[i + 1].split("/")
        shard = (int(k), int(n))
        if not (1 <= shard[0] <= shard[1]):
            sys.exit(f"--shard K/N needs 1 <= K <= N, got {args[i + 1]}")
    elif a == "--shard-plan":
        shard_plan = True
    elif a == "--exclude-list":
        exclude_list = args[i + 1]
    elif a == "--budget-scale":
        budget_scale = float(args[i + 1])
        if budget_scale <= 0:
            sys.exit(f"--budget-scale needs a positive factor, got {args[i + 1]}")

# One ripwire instance already sizes its parse pool to every logical CPU. Running the default six gates beside
# one another therefore oversubscribes Windows hosts (six instances x sixteen workers on the dev machine),
# making a healthy verification look like a runaway process storm. Keep the explicit escape hatch for a caller
# that has measured a separately provisioned machine and deliberately wants process-level oversubscription.
if windows and jobs > 1 and os.environ.get( "RIPWIRE_ALLOW_WINDOWS_OVERSUBSCRIPTION" ) != "1":
    requested_jobs = jobs
    jobs = 1
    print( f"Windows scheduler: capped requested jobs={requested_jobs} to jobs=1; "
           "set RIPWIRE_ALLOW_WINDOWS_OVERSUBSCRIPTION=1 to opt in", file=sys.stderr )

testdir = os.path.join(root, "test")
# item 7 (§B12 polish round): os.listdir returns dotfiles too (unlike a shell glob without dotglob), so a
# leftover probe script such as a gate's own `.gateprobe.*.sh` scratch file would be discovered and RUN AS
# A GATE. Skip anything starting with "." — a real gate is never a dotfile.
gates = sorted(f for f in os.listdir(testdir) if f.endswith(".sh") and not f.startswith("."))
# regression.sh is the driver itself; det-gate is invoked inside it.
skip = {"regression.sh"}
gates = [g for g in gates if g not in skip]
if only:
    gates = [g for g in gates if only in g]

# --exclude-list: a leg may decline a NAMED set of gates, and only by pointing at a committed file whose
# every line says which gate and why. The use it exists for (2026-09-07): the macOS plain leg -- an -O0
# binary on a 3-core runner -- was the critical path of the whole workflow at 33-37 min, and its four
# slowest gates (binoverridecheck, knownitemcheck, ripwirepubliccheck, xmlwellformed) assert nothing
# platform-specific and run unchanged on the macOS Release leg and all four Linux legs. Applied BEFORE the
# shard split so the remaining gates rebalance; the count is printed so a log reader sees the omission
# instead of inferring it from a shorter gate total. A name in the file that matches no gate is an error:
# a stale exclusion silently excluding nothing is how a list like this rots.
excluded = []
if exclude_list:
    with open(os.path.join(root, exclude_list)) as fh:
        wanted = [ln.split("#", 1)[0].strip() for ln in fh]
    wanted = [w for w in wanted if w]
    unknown = [w for w in wanted if w not in gates and not (only and only not in w)]
    if unknown and not only:
        sys.exit(f"--exclude-list {exclude_list} names gates that do not exist: {' '.join(unknown)}")
    excluded = [g for g in gates if g in wanted]
    gates = [g for g in gates if g not in wanted]
    print(f"exclude-list {exclude_list}: {len(excluded)} gate(s) not run on this leg: {' '.join(excluded)}")

# --- longest-first (LPT) scheduling -----------------------------------------------------------
# A greedy scheduler minimizes wall time by handing the slowest jobs to workers FIRST -- a long
# gate started late is a long gate that ends up running solo after every worker finishes its
# short queue. We persist each gate's measured seconds across runs and sort by that next time.
#
# The timings file must NOT live under test/ (item 7 above already burned us once on a scanner
# that discovers anything in that directory and treats it as a gate) and must not need
# committing -- it's a per-machine measurement, not project state. tempfile.gettempdir() honors
# $TMPDIR first, same as the binary's own cacheDirLadder(), so this is the same convention the
# rest of the repo already uses for scratch state. Keyed by the repo root's absolute path (hashed,
# so worktrees/checkouts of the same repo at different paths don't collide or share a stale file).
def _root_key():
    return hashlib.sha1(root.encode("utf-8")).hexdigest()[:16]


def _timings_path():
    return os.path.join(tempfile.gettempdir(), f"ripwire-pargates-timings-{_root_key()}.json")


def _load_timings(path):
    # Corrupt/missing/foreign-shaped JSON must degrade to "no history" -- never crash the run.
    # A stale or hand-edited file is exactly the kind of thing that WILL show up in the wild.
    try:
        with open(path) as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            return {g: dt for g, dt in data.items() if isinstance(dt, (int, float))}
    except (OSError, ValueError):
        pass
    return {}


prior_timings = _load_timings(_timings_path())

# --- sharding: one deterministic slice of the suite per CI job -------------------------------------
# CI runs this suite on every release leg; at 560+ gates that is ~150 CPU-minutes, i.e. ~60 min wall at
# -j 3 on a 4-vCPU runner, and the wall clock of the whole workflow IS one leg's suite. Splitting the
# list across N runner jobs divides that. The split has to be (a) deterministic -- every job computes
# the same partition from the same inputs, no shared state -- and (b) balanced by cost, or the shard
# that draws binoverridecheck + pagingsweepcheck + knownitemcheck finishes last and nothing was gained.
# So the weights come from a COMMITTED table (.github/pargates-shard-weights.json: median measured
# seconds per gate, regenerated from the local timings file when the suite's shape moves), not from
# the per-machine scratch timings above, and the assignment is longest-processing-time-first: gates
# sorted by weight descending (name ascending on ties), each handed to the currently lightest shard.
# A gate missing from the table gets the table's median -- unknown is not free, and it is not the
# slowest thing in the batch either when the question is which shard, not which worker. The scheduler
# below still orders the shard's own gates by the local scratch timings, exactly as before.
def _shard_weights():
    path = os.path.join(root, ".github", "pargates-shard-weights.json")
    w = _load_timings(path) if os.path.isfile(path) else {}
    if not w:
        return {}, 1.0
    med = sorted(w.values())[len(w) // 2]
    return w, med


def shard_plan_for(gate_names, n):
    weights, median = _shard_weights()
    order = sorted(gate_names, key=lambda g: (-weights.get(g, median), g))
    buckets = [[] for _ in range(n)]
    load = [0.0] * n
    for g in order:
        i = min(range(n), key=lambda j: (load[j], j))
        buckets[i].append(g)
        load[i] += weights.get(g, median)
    return buckets, load


if shard_plan:
    n = shard[1] if shard else 4
    buckets, load = shard_plan_for(gates, n)
    for i, (b, w) in enumerate(zip(buckets, load), 1):
        print(f"shard {i}/{n}: {len(b)} gates, predicted {w:.0f}s")
    print(f"total {len(gates)} gates, predicted {sum(load):.0f}s; largest shard {max(load):.0f}s")
    sys.exit(0)

if shard:
    buckets, load = shard_plan_for(gates, shard[1])
    gates = buckets[shard[0] - 1]
    print(f"shard {shard[0]}/{shard[1]}: {len(gates)} gates, predicted {load[shard[0] - 1]:.0f}s "
          f"(largest shard {max(load):.0f}s)")

# One checkout must have one active scheduler. A second full/focused run would otherwise launch another
# ripwire parse pool against the same cache and source tree, multiplying CPU and making the tree-writer
# tripwire report misleading races. OS file locks release automatically if the scheduler is terminated.
_run_lock_file = open( os.path.join( tempfile.gettempdir(), f"ripwire-pargates-lock-{_root_key()}.lock" ), "a+b" )
_run_lock_file.seek( 0 )
_run_lock_file.write( b"\0" )
_run_lock_file.flush()
_run_lock_file.seek( 0 )
try:
    if windows:
        import msvcrt
        msvcrt.locking( _run_lock_file.fileno(), msvcrt.LK_NBLCK, 1 )
    else:
        import fcntl
        fcntl.flock( _run_lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB )
except ( OSError, BlockingIOError ):
    _run_lock_file.close()
    sys.exit( f"pargates: another run is already running for {root}" )

# Sort longest-first using recorded durations. A gate with NO recorded duration is unknown, not
# fast -- treat it as potentially the slowest thing in the batch (float('inf')) so it schedules
# EARLY, alongside the known-long gates, rather than drifting to the tail of the run where an
# unlucky first-time-seen slow gate would extend the wall clock the same way a genuinely-slow
# gate starting late would.
gates.sort(key=lambda g: -prior_timings.get(g, float("inf")))

# A wall-clock budget cannot be interpreted while five unrelated compiler/git-heavy gates are saturating
# the machine beside it. Keep the measured gates in this same authoritative run, but give their timing windows
# exclusive ownership after the parallel correctness wave. agenttable's nine wrap/install probes, attrvocab's
# repeated verb runs, agentloopgrader's Python grader, and the a9/deck diagnostic bundles are correct in isolation
# but cross the 300 s tripwire when they compete with the compiler-heavy wave.
exclusive = {"a9disclosurecheck.sh", "agentloopgradercheck.sh", "agenttablecheck.sh", "attrvocabcheck.sh", "deckcheck.sh", "editcheckcheck.sh"}

# --- per-gate budget overrides (W1-V4, 2026-08-11) ---------------------------------------------
# A flat cap is wrong for the minority of gates whose HONEST work exceeds it -- the fix is a per-gate
# override, not a raised global ceiling that would blunt the tripwire for the other ~370 gates that
# really do finish in seconds. This is a declared table (gate name -> budget seconds), not a marker
# line grepped out of each gate file: the table is the single place a reviewer checks "is this gate's
# timeout honest", and it can't drift out of sync with a comment buried in a script nobody re-reads.
#
# DEFAULT_TIMEOUT_SEC applies to every gate not named below.
#
# The six *importprecisecheck/*condcheck entries build a SECOND ripwire from git HEAD to diff today's
# resolver against it, sharing one sha-keyed binary through test/lib/headbinlib.sh: one elected
# builder, the rest wait on its lock. A full build is ~50s on the dev machine but several minutes on a
# 4-vCPU CI runner with -j 3 gates already competing for it, so DEFAULT_TIMEOUT_SEC is not a budget
# for them -- it is shorter than the work. Measured: rc=124 at 300.1 s on ALL FOUR Linux legs of CI run
# 31182301976, green on macOS where the same build fits in ~60 s. headbinlib.sh's own waiter budget
# must stay well under 900 -- its comment explains the coupling.
# Since 2026-09-10 CI no longer builds that binary inside any gate: ci.yml builds it in its own step BEFORE this
# harness starts and exports RIPWIRE_HEADBIN, and headbinlib's STAGED mode then never builds and never waits
# (test/headbinstagecheck.sh). No timeout could have fixed it -- the build is super-linear in the -j contention
# these budgets run under, so a slow draw outgrew 900 s and then 1200 s. The six numbers stay as declared because
# the unstaged path (a local run with RIPWIRE_HEADBIN unset) still builds inside the first gate and still waits.
#
# cppbenchcheck / regexbombcheck: legitimate ASan-on-a-cold-cache work, not a hang -- ~856 s and ~804 s
# measured respectively -- so the old flat 300 s cap read a healthy run as a timeout. 1200 s leaves
# headroom above both measurements without being so loose it stops meaning anything.
#
# binoverridecheck / estchargecheck / pagingsweepcheck (2026-08-23): the same story a third time, and the
# reds were counted as three separate mysteries before anyone lined them up. All three hit rc=124 at
# exactly 300.0-300.1 s on the ubuntu legs of CI run 32609218692 -- "exactly the budget" is the signature
# of a cap, not of a hang, and a real hang does not stop at the cap on four legs and finish in under a
# minute on the fifth. Measured on an idle dev machine against the same commit: 54 s, 26 s and 34 s wall.
# binoverridecheck is the heaviest because it is a META-gate -- it re-runs a slice of the suite against a
# sentinel binary, so it pays the suite's own cost while competing for the same -j 3 -- which is why it
# also overran on macos-14 Release where the other two fit. A 4-vCPU runner at -j 3 is roughly a 6-11x
# multiplier on these, putting the honest CI numbers well past 300 s and under 900 s; 900 matches what the
# six *importprecisecheck/*condcheck entries above already use for the same reason. Per the house rule
# that build and CI cost never gate on wall clock, a budget here is a hang tripwire, not a perf bar.
# --budget-scale (2026-09-07, first sharded CI runs): the flat default is a HANG tripwire calibrated on an idle
# dev machine, and a 4-vCPU runner at -j 3 is a 3-8x multiplier on any gate's wall time (mcpframehonestycheck
# 151 s local -> rc=124 at 300.1 s; paginationcheck 53 s local -> rc=124 at 300.0 s). Sixty-four uncapped gates
# sit inside that multiplier of the cap, so per-gate entries would be the wrong shape -- and raising the constant
# itself would blunt the tripwire on the machines it was measured on. So CI passes a scale factor that applies
# to the DEFAULT, and a declared entry below acts as a FLOOR under it rather than a ceiling over it. The
# TIMEOUT message names the effective budget and the scale, so a red still names its own limit.
#
# The floor (2026-09-10) repairs an inversion the first shape had. Skipping the scale for declared entries
# meant that under CI's --budget-scale 4 the gates this table calls out as HEAVY were the only gates in the
# job running on LESS time than an ordinary one: crossdirincludecheck, which builds a whole second ripwire
# from git HEAD, got 900 s while xmlwellformed -- which pipes one map through xmllint -- got 300 x 4 = 1200.
# Measured on a CI run of main (34479806177, macos-14 Release shard 2/2): crossdirincludecheck rc=124 at
# 900.1 s in a shard whose wall was 3588.6 s, with xmlwellformed at 585.8 s and rootrelcheck at 345.9 s in
# the same job -- every gate on that runner ran 6-10x its idle-local wall, and only the UNDECLARED ones had
# a budget that had moved with it. max(declared, default x scale) keeps each declared number meaningful on
# the machine it was measured on (at scale 1.0 the declared value still wins, unchanged) and stops the table
# from buying a gate less time than saying nothing would have. It never loosens a tripwire below today.
DEFAULT_TIMEOUT_SEC = 300
GATE_BUDGET_SEC = {
    "crossdirincludecheck.sh":    900,
    "nestedimportcheck.sh":       900,
    "preproccondcheck.sh":        900,
    "pyimportprecisecheck.sh":    900,
    "rustimportprecisecheck.sh":  900,
    "tsimportprecisecheck.sh":    900,
    "bodydialectcheck.sh":        900,   # T3 gave --for/--pack-task real body assembly (v0.3.5/6);
                                         # ~160 s CPU -- a plain -O0 CI runner overruns the flat cap
                                         # while a healthy local run takes ~17 s wall.
    "binoverridecheck.sh":        900,   # meta-gate: re-runs a suite slice against a sentinel binary,
                                         # so it pays the suite's cost while competing for the same -j.
                                         # ~54 s idle local; rc=124 at the flat cap on 5 of 6 CI legs.
    "estchargecheck.sh":          900,   # ~26 s idle local; rc=124 at the flat cap on all ubuntu legs.
    "pagingsweepcheck.sh":        900,   # ~34 s idle local; rc=124 at the flat cap on all ubuntu legs.
    "slicediffcheck.sh":          900,   # replays 57 labelled commits (checkout + --slice --since each); ~80 s local
    "mcpframehonestycheck.sh":    900,   # 2026-09-07 (first sharded CI run 34145918269): rc=124 at 300.1 s on three of
                                         # four Linux legs' shard 2 -- "exactly the cap" again. ~150 s local; a shard
                                         # job hands it fewer neighbours to hide behind than the whole suite did.
    "knownitemcheck.sh":          900,   # 2026-09-05: --eval-retrieval stopped sampling 150 symbols in PATH order and
                                         # now grades its whole population exhaustively (the sampler measured the corpus,
                                         # not the ranker -- docs/EVALS.md section 7). The gate runs it twice on src/ for
                                         # the determinism arm plus three bounded corpora for the order-independence arm:
                                         # ~132 s idle local, where it was ~10 s. Under the flat cap this is the same
                                         # rc=124-at-300.0 s signature the three gates above carry, and the two entries
                                         # directly above are 26 s and 34 s local -- a 4-vCPU leg running -j 3 has no
                                         # chance of fitting 132 s. Per the header: a budget here is a HANG TRIPWIRE,
                                         # not a perf bar; the eval is deliberately exhaustive and its cost is the price
                                         # of a number that no longer moves with a file's path.
    # 2026-09-05 (capture-audit round landed, CI run 33978240573): three universe-sweep gates from that round hit
    # rc=124 at exactly 300.0-300.1 s -- the cap signature again, not a hang. compactlegendcheck overran on ALL
    # FIVE failing legs (it runs the compact legend rewrite over every XML verb, full and compact, plus the MCP
    # twins), shapingflagcheck on the four ubuntu legs (every kShapingVerbs row probed on a shape where the budget
    # binds, un-budgeted and budgeted), collectioncapcheck on macos-14 Release only (15 s idle local -- it lost
    # the CPU to the two above at -j 3, the pagingsweepcheck story). Measured on the dev machine with the three
    # running concurrently: 107 s, 166 s, 15 s wall. At the runner's 6-11x, the first two land past 900, so they
    # take the 1200 that cppbenchcheck/regexbombcheck already use; collectioncapcheck takes 900 like pagingsweep.
    # Making the two sweeps cheaper (one ingest shared across probes) is registered for the terminality round's
    # battery-hygiene lane; a budget here is the hang tripwire, never the perf bar.
    #
    # 2026-09-05, LATER (terminality round A, lane V2): that registered work LANDED, and these two rows come
    # DOWN 1200 -> 900. Both gates now redirect $TMPDIR into their own scratch dir and warm each root they
    # probe ONCE, instead of passing --no-cache on every probe; the private TMPDIR is what makes a warm probe
    # safe beside a parallel battery, because both gates assert byte-identity between two runs of the same
    # argv and a sibling gate's blob write would otherwise move a cache-reporting row (--doctor's cache-dir
    # bytes=) between them. Identical arm sets before and after, ALL PASS both ways.
    #
    # THE ARITHMETIC, measured the same way the paragraph above measured it -- the three gates running
    # concurrently on the dev machine, before and after, same machine, same binary:
    #     compactlegendcheck  74.1 s -> 53.9 s   (-27%)      solo: 68.6 s -> 49.4 s
    #     shapingflagcheck   107.2 s -> 71.1 s   (-34%)      solo: 105.6 s -> 66.5 s
    #     collectioncapcheck   8.8 s ->  9.6 s   (untouched; the noise band on this measurement)
    # Scaling the budget by the measured ratio: 1200 x 53.9/74.1 = 873 and 1200 x 71.1/107.2 = 796 -- both
    # land on the 900 tier pagingsweep/collectioncap already use. Cross-checked against the runner factor
    # this file's own rows are derived from: at 6-11x, 53.9 s projects to 323-593 s and 71.1 s to 427-782 s,
    # so 900 still clears the SLOWEST projection with headroom, which is the property a hang tripwire needs.
    # NOT taken: 4x the local wall (216 s / 284 s). That is below the flat 300 s default and would re-create
    # exactly the rc=124 reds these rows were added to fix -- these gates got ~30% cheaper, not 4x cheaper,
    # and a budget has to survive the slowest leg, not the machine it was measured on.
    # WHERE THE REST OF THE TIME IS, so the next lane does not re-run this experiment: profiled with a
    # timing shim, shapingflagcheck makes 890 binary invocations totalling well under a third of its wall.
    # The binary is no longer the dominant cost of either gate -- the residual is the per-row shell/awk/
    # python glue of the universe sweeps. Another round of ingest-sharing buys nothing; only fewer
    # subprocesses per row would.
    #
    # 2026-09-05, LATER STILL (terminality round A wave-2 verifier, N1; lane V3): shapingflagcheck goes back
    # UP to 1200 and compactlegendcheck STAYS at 900. Nothing about the gates changed -- the BASIS did. V2
    # measured the pair with only their two siblings running; the verifier re-timed them at the same commit
    # under a full parallel battery (load average 19), which is the contention shape a CI leg at -j actually
    # has and closer to it than a three-gates-only run. Both ALL PASS; the walls are higher:
    #     gate                V2 concurrent   V2 solo   verifier, LOADED   x6      x11     budget   margin
    #     compactlegendcheck        53.9 s     49.4 s          69 s       414 s   759 s     900     141 s
    #     shapingflagcheck          71.1 s     66.5 s          80 s       480 s   880 s     900      20 s
    # At the 6-11x runner factor THIS FILE's own rows are derived from (see the header paragraph),
    # compactlegendcheck projects to 759 s at the top of the range and clears 900 by 16%; shapingflagcheck
    # projects to 880 s and clears it by 20 s, which is 2.2% -- less headroom than the round's own
    # measurement noise, on the gate CI run 33978240573 went red on across four ubuntu legs. A budget here is
    # a hang tripwire, never a perf bar (the house rule that build and CI cost never gate on wall clock), so
    # the two errors are not symmetric: a too-generous budget costs nothing at all, and a thin one costs a
    # red CI leg and the hour spent re-deciding whether it was a hang. 1200 is the tier
    # cppbenchcheck/regexbombcheck already use for exactly this reason. compactlegendcheck's 141 s is real
    # headroom and is left alone -- the row that needs the margin is the one that gets it.
    "compactlegendcheck.sh":      900,
    "shapingflagcheck.sh":       1200,
    "collectioncapcheck.sh":      900,
                                          # under -j6, rc=124 at the flat cap on both ubuntu PLAIN legs of run
                                          # 33762934972 (Release legs and macOS fit). Warm replay landed with this row.
    "cppbenchcheck.sh":          1200,
    "regexbombcheck.sh":         1200,
}
parallel_gates = [g for g in gates if g not in exclusive]
exclusive_gates = [g for g in gates if g in exclusive]


# --- a failing gate's output: kept whole, and summarised by the line that FAILED ------------------
# (F1/F2, terminality round A 2026-09-05.) The summary used to print a failing gate's last 12 non-blank
# lines out of a 2500-char tail, which is the wrong 12 lines for the way this repo's gates are written:
# a gate prints `  FAIL  arm (X) ...` at the moment the arm fails and then keeps going through its
# remaining arms, so the tail is a wall of PASS rows and a closing `SOME CHECKS FAILED`. That is
# literally what three rounds of readers saw -- V1 ("eleven PASS lines then SOME FAILED"), V2 and the
# capture-audit close all recorded the same loss, each time for `gitstampcheck`, and each time the arm
# that failed stayed unknown. Printing FEWER trailing lines would not have helped; the fix is to select
# the failure-carrying lines, not to move the window.
#
# Three changes, all in service of "a red names what failed":
#   1. stdout and stderr are captured MERGED, in the order the gate wrote them (stderr=STDOUT), instead
#      of concatenated after the fact -- a message written to stderr next to the FAIL row it explains
#      no longer teleports to the end of the transcript.
#   2. A failing gate's FULL output is written to FAIL_LOG_DIR/<gate>.log and the path is printed. The
#      summary is a summary; nothing is destroyed by it any more.
#   3. The summary prints, in this order: the failure-shaped lines with their line numbers, then the
#      LAST 5 lines of the transcript. Failure shapes are the repo's own markers first, anchored and
#      case-sensitive (`  FAIL  `, `FAILURES ABOVE`, `SOME CHECKS FAILED`, `TIMEOUT after`) exactly as
#      regression.sh's absorb window does it, so a PASS row whose prose contains the word "fail" cannot
#      hijack the selection; only if a gate produced none of those (it died before its own reporting)
#      do the loose shapes -- `error:`, `fatal`, `Sanitizer`, a Python traceback, a missing binary --
#      get a turn.
REPORT_CHARS = 2000     # the stored report for a skipped gate -- see skip_report(), which keeps the declaration
FAIL_TAIL_LINES = 5
FAIL_MARK_LINES = 10
# re.M because classify_skipped() matches this against a WHOLE transcript: without it `^` binds only to the start
# of the string, every anchored alternative here is dead below line 1, and the only one that would still fire is the
# unanchored "SOME CHECKS FAILED" -- so a gate that printed a FAIL row and then a SKIP row read as "proved nothing".
# A no-op for failure_lines(), which searches one line at a time: a single line has no newline for `^` to find.
_MARKER_RE = re.compile(r"^\s*FAIL\b|^FAILURES ABOVE|SOME CHECKS FAILED|^\s*TIMEOUT after", re.M)
_LOOSE_RE = re.compile(r"error:|fatal|Sanitizer|Traceback|command not found|no ripwire binary|required$")


def _fail_log_dir():
    return os.path.join(tempfile.gettempdir(), f"ripwire-pargates-fails-{_root_key()}")


def failure_lines(out):
    """The lines a reader needs: the markers this repo's gates print when an arm fails."""
    lines = out.splitlines()
    marked = [(i + 1, ln) for i, ln in enumerate(lines) if ln.strip() and _MARKER_RE.search(ln)]
    if not marked:
        marked = [(i + 1, ln) for i, ln in enumerate(lines) if ln.strip() and _LOOSE_RE.search(ln)]
    return marked


def failure_report(out, logpath):
    """The block printed under FAILURES for one gate: what failed, then how it ended, then where the
    whole thing is. Composed here so the run's result rows stay small -- only this summary is carried
    back from the worker, never every gate's full transcript."""
    lines = out.splitlines()
    total = len(lines)
    marked = failure_lines(out)
    block = []
    if marked:
        block.append(f"what failed ({len(marked)} failure-shaped line(s)):")
        for lineno, ln in marked[:FAIL_MARK_LINES]:
            block.append(f"  L{lineno}: {ln}")
        if len(marked) > FAIL_MARK_LINES:
            block.append(f"  ... {len(marked) - FAIL_MARK_LINES} more — see the full log")
    else:
        block.append("what failed: no failure-shaped line in the transcript (the gate died before its own reporting)")
    tail = [(i + 1, ln) for i, ln in enumerate(lines) if ln.strip()][-FAIL_TAIL_LINES:]
    block.append(f"last {len(tail)} line(s) of {total}:")
    for lineno, ln in tail:
        block.append(f"  L{lineno}: {ln}")
    block.append(f"full output: {logpath}")
    return "\n".join(block)


# --- SKIPPED vs PASSED: a gate's FIRST verdict decides (2026-09-13) ----------------------------------------------
# A gate that SKIPS is not a gate that PASSED. argvdiffcheck skips without a RIPWIRE_BASE reference binary, and
# reporting that as a pass is exactly the green-while-inert failure this suite exists to catch elsewhere (the
# CI/NDEBUG blindness is the same family).
#
# This used to read `"SKIP" in out[:400]` -- a ruler laid over the transcript, and the transcript's origin moves.
# The ruler was 400 CHARACTERS, not bytes: run_gate hands back raw bytes, run() decodes them
# (`out = raw.decode("utf-8", "replace")`) and the slice lands on the str, so it counted code points. This
# suite prints box-drawing rules and em dashes liberally, so an offset quoted in bytes against that threshold
# is a unit error -- which is why every offset below names its unit.
# Gates open with a banner naming their own absolute paths (`<name>: BIN=<abs>  ROOT=<abs>`) -- 515 of the 628
# transcripts in one full run carry the crawl root in their first line -- so for those the window's CONTENTS are a
# function of the checkout's pathname. Measured on w3fixlegendcheck, whose output is byte-identical after line 1:
# the banner is 217 B from an 87-char root and 67 B from a 12-char one, and every offset after it moves by that
# 150 B -- about 2 B per character of path, because the root is spelled twice.
#
# REPRODUCED, and the tree matters. The reported symptom was `skip=2` from a 137-char checkout against `skip=3`
# from a 38-char one on 3c191bdf -- a commit on lane/recent-scope, NOT on main. On that tree w3fixlegendcheck's
# N=3 partition arm TIES (`TIE 0.0928 vs 0.093`) and honestly skips, and that tie row is the third thing the gate
# prints. Running that tree's gate from two checkouts, same binary, arm output byte-identical after line 1:
#     38-char root    banner 168 B    tie row starts at 308    -> old rule: SKIP
#    138-char root    banner 268 B    tie row starts at 408    -> old rule: PASS
# It straddles the window by 8 bytes. On main (c1915d21) that arm does NOT tie -- N=3 passes -- so its only skip
# marker is the NDEBUG degrade row about 3 KB in, and the symptom does not reproduce there at any path length.
# An absolute offset in this comment is therefore a property of a named tree, never a constant of the gate.
# `skip=` is read before every push; a count that moves with the pathname is not evidence.
#
# AND THE EXPOSURE IS NOT ONE GATE'S. Measured over all 628 transcripts of one full run: 24 gates print a skip
# MARKER downstream of at least one absolute-root mention (28 by the bare substring the old rule actually looked
# for, the extra four being gates that only narrate the word), so their classification moves with the checkout. The
# nearest is a REAL standing skip -- editchecknotecheck declares its skip at byte 145, and 255 more characters of
# checkout path (a 342-char root: ordinary for a nested worktree or a CI runner) push that declaration out of the
# window, at which point the suite reports a gate that proved nothing as a PASS. Which gates are in range is a
# property of the MACHINE, not of the commit, so the answer is not a wider window.
#
# THE RULE: a gate that proves nothing says so BEFORE it claims anything. The FIRST verdict marker in the
# transcript decides -- a SKIP ahead of every PASS and FAIL marker is a WHOLE-GATE skip ("ran, but proved
# nothing"); a SKIP that follows one is an ARM-level skip inside a gate that did prove something, and the gate is
# a pass. That is what this tree already did on purpose -- namingcalibrationcheck runs its live arm FIRST so that
# its skip banner precedes the instrument arm's pass rows, argvdiffcheck's skip is its opening line -- now written
# down and free of the offsets. (That gate's comment used to justify the order by byte offset; this same change
# rewrote it, so there is no longer a sentence there to quote.) Measured over one full run's 628 transcripts, the new rule and the old one
# disagree on ZERO gates: it reproduces today's answers on this tree and stops needing the pathname to do it.
#
# MARKERS, NOT SUBSTRINGS. Five gates NARRATE the word SKIPPED (doctorcheck, formatgatecheck, headbinstagecheck,
# mcpreadloopcheck, releaseinstallcheck) and prove plenty, so a verdict must be a row this tree's helpers actually
# print -- `  SKIP  x` from skip(), `<name>: SKIP ...`, `SKIP: ...`, `...; SKIP` -- never a bare mention of the
# word. The nearest gate-side contract is test/gateexitcheck.sh arm (D), but it holds LESS than the rule above: it
# flags an `exit 0` only where both a skip word and "ALL PASS" appear within three lines of it, so it does not
# police marker ORDER at all. This harness side is pinned by test/skipclassifycheck.sh.
#
# THE DIRECTION THIS RULE OPENS, disclosed rather than discovered later. A WHOLE-GATE skip that prints any PASS row
# BEFORE its skip marker is now counted as a PASS -- it looks exactly like a gate that proved something and then
# skipped an arm, and no transcript can tell the two apart. No gate in the suite does this today (the 628-transcript
# replay is the evidence) and the convention "announce the skip before you claim anything" is what the two
# sanctioned skips already follow, but NOTHING ENFORCES IT: a gate that grew a `  PASS  fixture present` row above
# its skip banner would go from skip to pass silently. That is the green-while-inert direction this count exists to
# refuse, so it is stated here as an unenforced convention and is the obvious next arm for gateexitcheck.
_SKIP_RE = re.compile(r"^[ \t]*SKIP\b|^\S+:[ \t]*SKIP\b|;[ \t]*SKIP[ \t]*$", re.M)
# The `<name>: PASS` form is real: 15 gates print it, w3fixlegendcheck among them. Widening to it changes 0 of the
# 628 (no gate that prints it also prints a skip marker), so this is a latent hole closed, not a behaviour change.
_PASS_RE = re.compile(r"^[ \t]*PASS\b|^[ \t]*ALL PASS\b|^\S+:[ \t]*(?:ALL )?PASS\b", re.M)


def classify_skipped(rc, out):
    """True when the gate RAN BUT PROVED NOTHING: it exited 0, and the FIRST verdict marker in its output is a
    SKIP. A SKIP marker that follows a PASS or FAIL marker is an arm-level skip inside a gate that proved
    something, and is not counted. A function of the verdicts alone -- the same output is classified the same way
    from every checkout, whatever its pathname costs the transcript in leading bytes."""
    if rc != 0:
        return False            # a red is a FAILURE however it narrated itself: rc outranks every marker
    skip = _SKIP_RE.search(out)
    if skip is None:
        return False
    claims = [m.start() for m in (_PASS_RE.search(out), _MARKER_RE.search(out)) if m is not None]
    return all(skip.start() < c for c in claims)


def skip_reason(out):
    """The gate's own skip declaration, for the SKIPPED section -- the marker line itself, never a line that
    merely mentions the word."""
    return next((ln.strip() for ln in out.splitlines() if _SKIP_RE.search(ln)), "")


def skip_report(out, limit=REPORT_CHARS):
    """The report stored for a skipped gate: a bounded prefix of the transcript that is GUARANTEED to carry
    the gate's own declaration. classify_skipped() reads the WHOLE transcript, so a declaration sitting past
    `limit` would leave the SKIPPED section printing that gate with an EMPTY reason -- the one thing the
    section exists to say. Carrying the declaration costs one line, never the transcript, and a gate whose
    reason already falls inside the prefix gets a byte-identical report. Pinned by arm (H) of
    test/skipclassifycheck.sh, whose probe declares at character 3221."""
    head = out[:limit]
    decl = skip_reason(out)
    if decl and skip_reason(head) != decl:
        return decl + "\n" + head
    return head


# --- a gate is its whole process group, and a stop signals all of it (2026-09-10) ---------------------------------
# A gate's work runs in its children -- ripwire over whole trees, and on the unstaged path headbinlib.sh's parallel
# `cmake --build`. The budget used to be subprocess.run(timeout=), which expires into Popen.kill(): SIGKILL to the
# gate's bash and to nothing else, and SIGKILL runs no trap. Measured on a probe gate under a 2 s budget: its
# background child and the child it waited on inside $( ) were both alive, reparented to pid 1, after this harness had
# printed TIMEOUT -- still running beside the next gates, on runners the budget table above describes as super-linear
# in exactly that contention.
#
# So every gate starts in a session of its own, which makes it the leader of a process group holding each descendant
# that does not move itself out (one that calls setsid is out of reach), and a stop signals that group: TERM first, so
# the gate's EXIT trap still removes its temp dir -- a private checkout there is a whole tree of the repository -- then
# KILL for whatever is still in the group KILL_GRACE_SEC later. The grace belongs to the whole group, not to the gate's
# bash: a child whose output goes elsewhere can still be cleaning up after both are gone, and the first version KILLed
# it right then (CodeRabbit on #129). A group seen empty is never signalled again. What the gate printed before and
# during the stop is kept -- it is in the capture file described below, not in flight down a pipe.
#
# A session of its own also takes the gate out of the terminal's foreground group, so Ctrl-C would no longer reach it at
# all. pargates therefore catches SIGINT, SIGTERM and SIGHUP -- unless it inherited one ignored -- stops every running
# gate the same way within STOP_POLL_SEC, starts none after, and exits 128+signal with no summary. A gate admitted in
# the instant the signal lands, between run()'s check and its spawn, is stopped before its first read (CodeRabbit on
# #129); no check can close that window itself against an asynchronous signal. A second signal changes nothing: the
# stop is bounded by 2 x (STOP_POLL_SEC + KILL_GRACE_SEC). A SIGKILL to pargates itself reaches no gate.
# test/pargatescheck.sh runs these paths on probe gates, beside mutants of each that must go red.
KILL_GRACE_SEC = 10
STOP_POLL_SEC = 0.5
stop_signal = None      # the first SIGINT/SIGTERM/SIGHUP pargates received; set only by _on_stop_signal


def _on_stop_signal(signum, _frame):
    global stop_signal
    if stop_signal is None:
        stop_signal = signum
        try:
            # os.write, not print: a handler writing through sys.stderr can re-enter the write it interrupted
            os.write(2, f"\npargates: {signal.Signals(signum).name} -- stopping every running gate's process group\n".encode())
        except OSError:
            pass


_stop_signals = tuple(_sig for _sig in (signal.SIGINT, signal.SIGTERM, getattr( signal, "SIGHUP", None )) if _sig is not None)
for _sig in _stop_signals:
    if signal.getsignal(_sig) is not signal.SIG_IGN:        # nohup, or `&` without job control: an inherited ignore stands
        signal.signal(_sig, _on_stop_signal)


def _group_alive(p):
    """Whether the gate's process group still has a member. An exited leader is reaped first, so it does not count."""
    p.poll()
    if windows:
        job = getattr( p, "_ripwire_windows_job", None )
        if job is not None:
            return job.alive()
        return p.returncode is None
    try:
        os.killpg(p.pid, 0)
    except ProcessLookupError:
        return False
    except OSError:
        pass                        # EPERM: a member exists that this process may not signal
    return True


# --- a gate's stdout is a FILE, never a pipe (2026-09-11) -------------------------------------------------------
# Whether a gate's `printf` succeeds is a property of what this harness hands it as stdout, and a verdict must never
# depend on it. stdout used to be subprocess.PIPE: a blocking pipe with a ~16 KiB kernel buffer, drained by one Python
# thread per gate. Let that reader stall -- GIL contention at -j 6, or the macOS runner starvation this repo has hit
# before -- and a verbose gate fills the buffer, its next printf BLOCKS inside write(2), and because bash installs its
# SIGCHLD handler without SA_RESTART (and every gate forks), the blocked write comes back EINTR. bash's printf then
# reports `write error: Interrupted system call` and returns non-zero, which is how PR #126 got
#     FAIL  B4 crossing: packet lists 12 of the map's 25 symbols in wide.md (cap 12)
# out of an arm whose pass condition (12 == 12, 25 > 12) held. Measured on a plain blocking pipe with a stalled
# reader: 600 arms -> 600 PASS lines AND 21 spurious FAILs, `Interrupted system call` on all 21. Contention alone did
# not do it (1500 arms drained a byte at a time: none), so it is the BLOCKED write specifically.
#
# A regular file cannot block a write, so the write cannot be interrupted, and there is no reader whose absence can
# break the descriptor -- the whole errno family goes away for every gate at once, however verbose and whatever the
# runner is doing. stderr stays stderr=STDOUT, i.e. the SAME open file description, so the two streams still interleave
# in real write order and a gate's stderr still lands beside the FAIL row it explains. The gate side of this is
# test/gateexitcheck.sh arm (G); this side is pinned by test/pargatescheck.sh arm (H). Note that test/regression.sh
# runs gates straight into CI's own pipe, where none of this applies -- which is why the gate-side contract, not this,
# is the load-bearing fix.
def _wait_for(p, secs):
    """Wait up to `secs` for the gate's leader -> True once it has exited and been reaped."""
    try:
        p.wait(timeout=secs)
        return True
    except subprocess.TimeoutExpired:
        return False


def _await_group(p, secs):
    """Wait until the gate's process group is empty or `secs` pass."""
    end = time.monotonic() + secs
    while _group_alive(p) and time.monotonic() < end:
        left = max(0.0, min(STOP_POLL_SEC, end - time.monotonic()))
        if _wait_for(p, left):
            time.sleep(left)        # the leader is reaped: what is left to wait on is the group itself
    return not _group_alive( p )


def _stop_group(p):
    """TERM the gate's process group and give the WHOLE group KILL_GRACE_SEC to exit -- not only its bash -- then KILL
    whatever is still in it and give that the same. A group seen empty is not signalled again. Nothing the gate wrote
    is at risk here any more: it is already in the capture file, including what the last members wrote on their way
    out. A descendant that left the group can still be writing after this returns; the caller reads the file once,
    so tail is missed, exactly as the pipe version missed it."""
    if windows:
        descendant_pids = _windows_descendant_pids( p.pid )
        if not _group_alive(p):
            _windows_terminate_pids( descendant_pids )
            return
        if not WINDOWS_MSYS_SHELL:
            try:
                p.send_signal( signal.CTRL_BREAK_EVENT )
            except ( OSError, ValueError, AttributeError ):
                pass
        if _await_group( p, KILL_GRACE_SEC ):
            _windows_terminate_pids( descendant_pids + _windows_descendant_pids( p.pid ) )
            return
        job = getattr( p, "_ripwire_windows_job", None )
        try:
            subprocess.run( [ "taskkill", "/PID", str( p.pid ), "/T", "/F" ],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            timeout=KILL_GRACE_SEC, check=False )
        except ( OSError, subprocess.TimeoutExpired ):
            pass
        _windows_terminate_pids( descendant_pids + _windows_descendant_pids( p.pid ) )
        if job is not None:
            job.terminate()
        else:
            # taskkill above is the only available tree operation when a Job Object could not be attached.
            pass
        _wait_for( p, STOP_POLL_SEC )
        return
    for sig in (signal.SIGTERM, signal.SIGKILL):
        if not _group_alive(p):
            break
        try:
            os.killpg(p.pid, sig)
        except OSError:
            pass
        _await_group(p, KILL_GRACE_SEC)
    _wait_for(p, STOP_POLL_SEC)


def _capture_read(path):
    """Everything the gate and its descendants have written so far. A capture that cannot be read is empty, never a
    crash of the harness: the rc and the budget message still stand on their own."""
    try:
        with open(path, "rb") as fh:
            return fh.read()
    except OSError:
        return b""


def run_gate(argv, env, limit):
    """Run one gate in a session of its own, stdout and stderr merged in write order into a regular file. Returns
    (rc, output bytes, how): how is "exited", "timeout" (rc 124, its group stopped at the budget) or "stopped"
    (pargates itself was signalled)."""
    deadline = time.monotonic() + limit
    fd, capture = tempfile.mkstemp(prefix="ripwire-pargates-capture-", suffix=".out")
    os.close(fd)
    try:
        gate_env = env
        if windows and os.path.basename( argv[ -1 ] ) in FIFO_GATES:
            gate_env = dict( env )
            gate_env[ "RIPWIRE_BIN" ] = env[ "RIPWIRE_FIFO_BIN" ]
        with open(capture, "wb") as fh, \
             subprocess.Popen(argv, cwd=root, env=gate_env, stdout=fh, stderr=subprocess.STDOUT,
                              **( { "creationflags": subprocess.CREATE_NEW_PROCESS_GROUP | _CREATE_SUSPENDED }
                                  if windows else { "start_new_session": True } )) as p:
            # Windows assigns the suspended leader before Git Bash can create its script shell; POSIX keeps
            # start_new_session=True for the same isolation.
            if windows:
                try:
                    p._ripwire_windows_job = _attach_windows_job( p )
                    _resume_windows_process( p )
                except OSError as exc:
                    descendants = _windows_descendant_pids( p.pid )
                    _windows_terminate_pids( [ p.pid ] + descendants )
                    try:
                        p.wait( timeout=KILL_GRACE_SEC )
                    except subprocess.TimeoutExpired:
                        pass
                    fh.write( f"pargates: could not associate gate with Windows Job Object: {exc}\n".encode( "utf-8" ) )
                    return 125, _capture_read( capture ), "error"
            while True:
                if stop_signal is not None:     # before every wait, the first included: a gate admitted as the signal landed stops now
                    _stop_group(p)
                    return 128 + stop_signal, _capture_read(capture), "stopped"
                if _wait_for(p, max(0.0, min(STOP_POLL_SEC, deadline - time.monotonic()))):
                    if not windows or not _group_alive( p ):
                        return p.returncode, _capture_read(capture), "exited"
                    time.sleep( STOP_POLL_SEC )
                    continue
                if time.monotonic() >= deadline:
                    _stop_group(p)
                    return 124, _capture_read(capture), "timeout"
    finally:
        _close_windows_job( locals().get( "p" ) )
        try:
            os.unlink(capture)
        except OSError:
            pass


def run(g):
    # PYTHONDONTWRITEBYTECODE: a gate that imports a module straight out of the checkout (agentlooplockcheck:
    # bench/agentloop/; aiderbytescheck: bench/headtohead/r4-2026-08-06/) would otherwise have Python drop a
    # __pycache__/ beside it. That directory is gitignored, so the tree tripwire below cannot see it, and its
    # name is on the crawl's built-in denylist, so every crawl of the live repo still counts it
    # (corpus_pruned_dirs=). Created between the two re-crawls of pagingsweepcheck's cold grep (G) pair, it
    # made that pair disagree on main twice (CI runs 34534320580, 34536435376). pargatescheck.sh pins it.
    env = dict(os.environ, RIPWIRE_BIN=binp, PYTHONDONTWRITEBYTECODE="1")
    # A standalone gate such as noaliascheck cross-checks compiler probes against the CMake configuration that
    # produced the selected binary.  The historical fallback `$ROOT/build/CMakeCache.txt` is wrong for named build
    # trees (build-win-final, ASAN, PGO, and staging bins), and silently compared a probe with an unrelated cache.
    # Derive the cache from the binary's own build directory, but preserve an explicit override used to classify a
    # deliberately different compiler.  Pass the path in the spelling consumed by the Git Bash child on Windows.
    if "RIPWIRE_CMAKE_CACHE" not in env:
        binary_cache = os.path.join( os.path.dirname( binp ), "CMakeCache.txt" )
        if os.path.isfile( binary_cache ):
            env[ "RIPWIRE_CMAKE_CACHE" ] = _msys_path( binary_cache ) if windows else binary_cache
    scaled_default = int( round( DEFAULT_TIMEOUT_SEC * budget_scale ) )
    if g in GATE_BUDGET_SEC:
        # A declared entry is a FLOOR, not a ceiling: it is the number below which this gate would be a
        # hang even on an idle machine. It must never buy the gate LESS time than an undeclared one gets.
        declared = GATE_BUDGET_SEC[g]
        limit = max( declared, scaled_default )
        scaled = "" if limit == declared else f", declared {declared}s raised to the scaled default {DEFAULT_TIMEOUT_SEC}s x --budget-scale {budget_scale:g}"
    else:
        limit = scaled_default
        scaled = "" if budget_scale == 1.0 else f", default {DEFAULT_TIMEOUT_SEC}s x --budget-scale {budget_scale:g}"
    t0 = time.time()
    env.update(WINDOWS_GATE_ENV)
    if windows:
        # Do not inherit a caller's global no-conversion switch: ordinary Git paths in the fixture need MSYS
        # conversion, while WINDOWS_GATE_ENV excludes only the embedded merge-scout ref payload above.
        env.pop( "MSYS_NO_PATHCONV", None )
    if stop_signal is not None:
        return g, 128 + stop_signal, 0.0, "", False     # pargates is stopping: no gate starts after the signal
    with running_lock:
        running.add(g)          # the tree tripwire names whoever is in flight when it sees new dirt
    try:
        script = _msys_path(os.path.join(testdir, g))
        rc, raw, how = run_gate([GATE_SHELL, script], env, limit)
    finally:
        with running_lock:
            running.discard(g)
    if how == "stopped":
        return g, rc, round(time.time() - t0, 1), "", False
    out = raw.decode("utf-8", "replace")
    if how == "timeout":
        # the budget itself is part of the message -- a red names its own declared budget instead of
        # making the reader go look it up in GATE_BUDGET_SEC. Whatever the gate managed to print before
        # the budget expired, and while its group was being stopped, is kept ahead of it: a gate killed at
        # 300 s that had already announced a failing arm used to report ONLY the word TIMEOUT.
        out += f"\nTIMEOUT after {limit}s (declared budget={limit}s{scaled})"
    # SKIPPED vs PASSED -- the gate's first verdict decides; see classify_skipped() for the rule and the red
    # that produced it (a byte window over a transcript whose origin moves with the checkout's pathname).
    skipped = classify_skipped(rc, out)
    report = ""
    if skipped:
        report = skip_report(out)            # bounded, and guaranteed to carry the declaration itself
    elif rc != 0:
        # best-effort: a full-output write that fails must never turn the report into a second failure.
        logpath = "(not written)"
        try:
            d = _fail_log_dir()
            os.makedirs(d, exist_ok=True)
            logpath = os.path.join(d, g + ".log")
            with open(logpath, "w") as fh:
                fh.write(out)
        except OSError:
            logpath = "(not written)"
        report = failure_report(out, logpath)
    return g, rc, round(time.time() - t0, 1), report, skipped


# --- shared-binary tripwire ---------------------------------------------------------------------
# A gate that rebuilds the binary under test hands every CONCURRENT gate either a missing file
# (rc=2, "no ripwire binary") or one the loader refuses while the linker still holds it
# (ETXTBSY -> exit 126, printed as "Permission denied"). CI run 31145553507 lost 126 of 361 gates
# that way to naminglocalscheck.sh's old source-mutation arm, and every one of the 126 reported a
# plausible-looking failure of its OWN subject -- swiftcheck "non-deterministic", rubymetricscheck
# "ccx should be > 0", type3check "XML not well-formed". Reading that log costs an hour before the
# common cause is visible. Fingerprint the binary before and after: if it moved, say so first, and
# say it loudly enough that nobody triages the 126 individually.
def _bin_fingerprint():
    try:
        st = os.stat(binp)
        return (st.st_size, st.st_mtime_ns, st.st_ino)
    except OSError:
        return None


# --- shared-tree tripwire ----------------------------------------------------------------------
# The sibling of the binary tripwire above, for the OTHER thing every gate shares: the checkout. A
# gate that writes a transient file anywhere under the repo root -- a probe copy beside the script
# it copies, an appended function it then `git checkout`s away -- makes `git status --porcelain`
# non-empty for as long as the file exists, and every stamped verb (--for, --pr-context,
# --edit-check, --slice, --situ, --hotspots, --doctor, ...) reads exactly that command, from ANY
# crawl root inside the checkout, for the `+dirty` half of its at="<sha>[+dirty]" anchor
# (src/gitstamp.h stampAt). CI run 34298150602, macOS plain shard 2/2: tokenbudgetcheck's `--for`
# determinism arm got est_tokens 3949 then 3947 -- the six bytes of "+dirty" at 2.5 B/tok -- while
# gateexitcheck, three worker slots away, had test/gateexitfix/.gateprobe.*.sh on disk. The red
# named an innocent gate on an innocent tree, and the issue thread named a third gate that had
# never written outside its own mktemp at all.
#
# So: baseline `git status` before the run, sample it while the run is in flight, and report every
# NEW line together with the gates that were running when it was seen. This is a SAMPLER (every
# PARGATES_DIRT_POLL_SEC, default 0.25 s): a window shorter than the interval can be missed, so a
# clean report is "none found", never "none exists" -- the floor rule the binary applies to its own
# counts. A hit FAILS the run: a writer is a defect whether or not a determinism arm happened to be
# reading in that window, and the same suite would only flake somewhere else next time.
# `--no-optional-locks` keeps the sampler from ever taking the index lock a gate might need.
#
# Its blind spot is a write git ignores. That is usually harmless, because the crawl skips gitignored paths
# too -- EXCEPT a directory whose NAME is on the crawl's own denylist (build, __pycache__, node_modules, ...):
# a crawl of the live repo still counts it in corpus_pruned_dirs= while `git status` stays empty. Python's
# bytecode cache was one such writer (see run()'s PYTHONDONTWRITEBYTECODE); a clean report stays "none found".
DIRT_POLL_SEC = float(os.environ.get("PARGATES_DIRT_POLL_SEC", "0.25"))


def _tree_dirt():
    """The set of `git status --porcelain` lines for the shared checkout, or None when git cannot
    answer (no git, not a repository, a lock held elsewhere) -- a skipped sample, never a false clean."""
    try:
        p = subprocess.run(["git", "--no-optional-locks", "-C", root, "status", "--porcelain", "--untracked-files=all"],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if p.returncode != 0:
        return None
    return set(p.stdout.decode("utf-8", "replace").splitlines())


running = set()                 # gates in flight right now; run() keeps it under running_lock
running_lock = threading.Lock()
dirt_baseline = _tree_dirt()    # None: git cannot see this root -- the tripwire is disarmed, and says so
dirt_seen = {}                  # status line -> [first_t, last_t, samples, gates running when seen]
dirt_stop = threading.Event()


def _dirt_sample():
    now = _tree_dirt()
    if now is None:
        return
    new = now - dirt_baseline
    if not new:
        return
    with running_lock:
        snap = sorted(running)
    t = round(time.time() - t0, 1)
    for ln in new:
        e = dirt_seen.setdefault(ln, [t, t, 0, set()])
        e[1] = t
        e[2] += 1
        e[3].update(snap)


def _dirt_watch():
    while not dirt_stop.wait(DIRT_POLL_SEC):
        _dirt_sample()


bin_before = _bin_fingerprint()

t0 = time.time()
dirt_thread = None
if dirt_baseline is not None:
    dirt_thread = threading.Thread(target=_dirt_watch, name="tree-dirt-tripwire", daemon=True)
    dirt_thread.start()
results = []
with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
    for r in ex.map(run, parallel_gates):
        results.append(r)
        if stop_signal is None:
            sys.stderr.write("s" if r[4] else ("." if r[1] == 0 else "X"))
            sys.stderr.flush()
for g in exclusive_gates:
    r = run(g)
    results.append(r)
    if stop_signal is None:
        sys.stderr.write("s" if r[4] else ("." if r[1] == 0 else "X"))
        sys.stderr.flush()
sys.stderr.write("\n")
if stop_signal is not None:
    # a stopped run proved nothing and measured nothing: no summary, no --json, no timings for the next LPT sort
    print(f"pargates: stopped by {signal.Signals(stop_signal).name} before the suite finished -- every gate still running had its "
          f"whole process group stopped (TERM, then KILL after {KILL_GRACE_SEC}s), and no gate started after the signal")
    sys.exit(128 + stop_signal)
if dirt_thread is not None:
    dirt_stop.set()
    dirt_thread.join()
    _dirt_sample()          # one last look: a file a gate LEFT BEHIND is a hit with no gate in flight

bin_after = _bin_fingerprint()
bin_moved = bin_before != bin_after

fails = [r for r in results if r[1] != 0]
skips = [r for r in results if r[4]]
slow = sorted(results, key=lambda r: -r[2])[:8]

# Persist fresh durations for next run's LPT sort. Best-effort: a write failure (read-only temp
# dir, a concurrent pargates run racing us) must not turn a passing gate run into a failing one --
# worst case the next run just falls back to whatever it could load, same as a missing file today.
# Written via a pid-suffixed temp file + os.replace so a concurrent writer never sees a half-written
# JSON file (os.replace is an atomic rename on POSIX).
try:
    tpath = _timings_path()
    ttmp = f"{tpath}.tmp{os.getpid()}"
    with open(ttmp, "w") as fh:
        json.dump({g: dt for g, rc, dt, _out, _sk in results}, fh)
    os.replace(ttmp, tpath)
except OSError:
    pass

# --- slowness tripwire -------------------------------------------------------------------------
# A gate that quietly grows from 1s to 8s over a series of unrelated commits is invisible in the
# "slowest" top-8 (it's still nowhere near the top) and doesn't fail anything -- so nobody notices
# until it's a 60s gate someone finally complains about. Flag it the day it happens: >=2x its own
# prior measurement AND over 5s absolute, so a gate going from 0.1s to 0.3s (3x, but trivial) stays
# quiet. Non-failing by design -- this is a heads-up, not a gate of its own, so it must never touch
# the exit code below.
tripwire = []
for g, rc, dt, _out, _sk in results:
    prev = prior_timings.get(g)
    if prev and dt >= 2 * prev and dt > 5.0:
        tripwire.append((g, prev, dt))

print(f"gates={len(results)} pass={len(results)-len(fails)-len(skips)} "
      f"skip={len(skips)} fail={len(fails)} wall={round(time.time()-t0,1)}s jobs={jobs}"
      + (f" tree_writes={len(dirt_seen)}" if dirt_baseline is not None else " tree_writes=unwatched"))
if bin_moved:
    print(f"\n*** THE BINARY UNDER TEST CHANGED WHILE THE SUITE RAN: {binp}")
    print(f"***   before={bin_before}  after={bin_after}")
    print("***   Some gate rebuilt it in place. Every gate that ran concurrently saw it missing")
    print("***   (rc=2) or busy (exit 126 / 'Permission denied'), so THOSE FAILURES ARE NOT REAL.")
    print("***   Find the gate that writes to the shared build tree and fix that first.")
if dirt_baseline is None:
    print("\ntree tripwire: DISARMED -- git cannot report status for this root, so a gate writing into the shared checkout goes unseen here")
if dirt_seen:
    print(f"\n*** A GATE WROTE INTO THE SHARED CHECKOUT WHILE THE SUITE RAN: {root}")
    print(f"***   sampled every {DIRT_POLL_SEC:g}s -- a shorter window can be missed, so this list is a floor, not a total:")
    for ln, (t_first, t_last, n, gs) in sorted(dirt_seen.items(), key=lambda kv: kv[1][0]):
        who = ", ".join(sorted(gs)) if gs else "(no gate in flight -- left behind after the run)"
        print(f"***   {ln}  seen {n}x, T+{t_first}s..T+{t_last}s; running then: {who}")
    print("***   Every stamped verb reads `git status --porcelain` for its at=\"...+dirty\" bit from ANY crawl root")
    print("***   inside this checkout, so a determinism arm that ran in that window can red with the tree innocent.")
    print("***   Fix the writer first (work on a copy, or a gitignored name that is not a crawl-pruned directory")
    print("***   name -- never build/, __pycache__/ or node_modules/); only then triage the arms above.")
if skips:
    print("\nSKIPPED (ran, but proved nothing — not counted as passing):")
    for g, rc, dt, report, _ in skips:       # the 4th field is the stored REPORT, not the full transcript
        why = skip_reason(report)
        print(f"  {g}  {why}")
print(f"bin={binp}")
print("\nslowest:")
for g, rc, dt, _, _sk in slow:
    print(f"  {dt:6.1f}s  {g}")
if tripwire:
    print("\nSLOWER (>=2x prior measured time and over 5s -- not a failure, worth a look):")
    for g, prev, dt in sorted(tripwire, key=lambda t: -t[2]):
        print(f"  {g}  {prev:.1f}s -> {dt:.1f}s")
if fails:
    print("\nFAILURES:")
    for g, rc, dt, report, _sk in fails:
        print(f"\n=== {g} (rc={rc}, {dt}s) ===")
        print("\n".join("    " + ln for ln in report.splitlines()))
elif dirt_seen:
    print("\nNO GATE FAILED, BUT THE SUITE IS NOT CLEAN -- a gate wrote into the shared checkout (see the tree tripwire above)")
else:
    print("\nALL PASS")

if jsonout:
    with open(jsonout, "w") as fh:
        json.dump({g: {"rc": rc, "sec": dt, "skipped": sk} for g, rc, dt, _, sk in results}, fh, indent=1)
sys.exit(1 if fails or dirt_seen else 0)
