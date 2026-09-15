#!/usr/bin/env python3
"""Run one childwalk scaling arm and report native Windows user+kernel CPU seconds."""
import ctypes
import os
import re
import subprocess
import sys


class _FileTime( ctypes.Structure ):
    _fields_ = [ ( "low", ctypes.c_uint32 ), ( "high", ctypes.c_uint32 ) ]


_kernel32 = ctypes.WinDLL( "kernel32", use_last_error=True )
_kernel32.GetProcessTimes.argtypes = [
    ctypes.c_void_p,
    ctypes.POINTER( _FileTime ),
    ctypes.POINTER( _FileTime ),
    ctypes.POINTER( _FileTime ),
    ctypes.POINTER( _FileTime ),
]
_kernel32.GetProcessTimes.restype = ctypes.c_int


def native_path( value ):
    if value == "/tmp" or value.startswith( "/tmp/" ):
        root = os.environ.get( "RW_MSYS_TMP", os.environ.get( "TEMP", os.environ.get( "TMP", "" ) ) )
        if root:
            return root.rstrip( "\\/" ) + value[ 4: ]
    match = re.match( r"^/([A-Za-z])(?:/|$)", value )
    if match:
        return match.group( 1 ).upper() + ":" + value[ 2: ]
    return value


def filetime_seconds( value ):
    return ( ( value.high << 32 ) | value.low ) / 10_000_000.0


def main():
    if len( sys.argv ) < 3:
        print( "FAIL", file=sys.stderr )
        return 1
    command = [ native_path( arg ) for arg in sys.argv[ 2: ] ] + [ native_path( sys.argv[ 1 ] ), "--no-cache" ]
    try:
        child = subprocess.Popen( command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE )
    except OSError as error:
        print( f"childwalktime_windows: {error}", file=sys.stderr )
        print( "FAIL" )
        return 0
    child.wait()
    if child.returncode != 0:
        detail = child.stderr.read().decode( "utf-8", "replace" ).strip()
        if detail:
            print( detail, file=sys.stderr )
        print( "FAIL" )
        return 0
    creation, exit_time, kernel, user = ( _FileTime() for _ in range( 4 ) )
    if not _kernel32.GetProcessTimes( child._handle, ctypes.byref( creation ), ctypes.byref( exit_time ),
                                      ctypes.byref( kernel ), ctypes.byref( user ) ):
        print( "childwalktime_windows: GetProcessTimes failed", file=sys.stderr )
        print( "FAIL" )
        return 0
    print( f"{filetime_seconds( kernel ) + filetime_seconds( user ):0.2f}" )
    return 0


if __name__ == "__main__":
    raise SystemExit( main() )