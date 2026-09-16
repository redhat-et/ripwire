#!/usr/bin/env python3
"""Native Windows sidecar/pathguard gate.

The POSIX gate uses FIFOs and RLIMIT_FSIZE.  Those primitives do not exist for a
Win32 path opened by ripwire, so this companion keeps the same security claims
with native symlinks/reparse points, directories, racing replacement, and
write/read byte checks.  It deliberately fails when a fixture cannot be made;
there are no silent skips.
"""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from pathlib import Path


VICTIM_BYTES = b"important user data\n"
READ_SENTINEL = "sidecar-read-sentinel-outside-note"
ARCH_HEADER = "# ripwire arch baseline — do not edit by hand. Regenerate with --baseline or --baseline-update.\n"
ARCH_MUL = 0x9E3779B97F4A7C15


class Suite:
    def __init__( self, root: Path, binary: Path ) -> None:
        self.root = root
        self.binary = binary
        self.failures = 0
        self.checks = 0

    def check( self, label: str, condition: bool, detail: str ) -> None:
        self.checks += 1
        if condition:
            print( f"  PASS  {label}: {detail}" )
        else:
            self.failures += 1
            print( f"  FAIL  {label}: {detail}" )

    def run( self, args: list[str], cwd: Path | None = None, timeout: float = 30.0 ) -> subprocess.CompletedProcess[str] | None:
        try:
            return subprocess.run(
                [ str( self.binary ), *args ],
                cwd=str( cwd ) if cwd is not None else None,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=timeout,
                check=False,
            )
        except ( OSError, subprocess.TimeoutExpired ) as exc:
            print( f"  FAIL  command: {self.binary} {' '.join( args )}: {exc}" )
            self.failures += 1
            self.checks += 1
            return None

    @staticmethod
    def make_tree( tree: Path, arch_rules: str = "layer core = a.c\nlayer consumer = sub/\ndeny consumer -> core\n" ) -> None:
        tree.mkdir( parents=True, exist_ok=True )
        ( tree / "sub" ).mkdir( exist_ok=True )
        ( tree / "a.c" ).write_text(
            '#include <stdio.h>\nint helper( int x ) { return x + 1; }\n'
            'int main( void ) { printf( "%d\\n", helper( 1 ) ); return 0; }\n',
            encoding="utf-8",
        )
        ( tree / "sub" / "b.c" ).write_text( "int other( int y ) { return y * 2; }\n", encoding="utf-8" )
        ( tree / "rules.txt" ).write_text( arch_rules, encoding="utf-8" )

    @staticmethod
    def make_arch_violation_tree( tree: Path ) -> None:
        Suite.make_tree( tree, "deny test -> render\n" )
        ( tree / "render" ).mkdir( exist_ok=True )
        ( tree / "test" ).mkdir( exist_ok=True )
        ( tree / "render" / "shader.h" ).write_text( "int shade( int x ) { return x; }\n", encoding="utf-8" )
        ( tree / "test" / "main.cpp" ).write_text(
            '#include "../render/shader.h"\n\nint main()\n{\n    compileShader( "void main(){}" );\n    return 0;\n}\n',
            encoding="utf-8"
        )

    @staticmethod
    def symlink( target: Path, link: Path, directory: bool = False ) -> None:
        link.parent.mkdir( parents=True, exist_ok=True )
        os.symlink( str( target ), str( link ), target_is_directory=directory )

    @staticmethod
    def normalized_path( path: Path | str ) -> str:
        value = os.path.abspath( os.path.realpath( str( path ) ) )
        if value.startswith( "\\\\?\\" ):
            value = value[4:]
        return os.path.normcase( os.path.normpath( value ) )

    @classmethod
    def same_link_target( cls, link: Path, target: Path ) -> bool:
        return link.is_symlink() and cls.normalized_path( link ) == cls.normalized_path( target )

    @staticmethod
    def remove_path( path: Path ) -> None:
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree( path )
        else:
            path.unlink( missing_ok=True )

    @staticmethod
    def sidecar_for( kind: str ) -> str:
        return {
            "qualitybaseline": ".ripwire_quality_baseline",
            "notes": ".ripwire_notes",
            "archbaseline": ".ripwire_arch_baseline",
        }[kind]

    def writer( self, kind: str, tree: Path, update: bool = False ) -> subprocess.CompletedProcess[str] | None:
        sidecar = self.sidecar_for( kind )
        if kind == "qualitybaseline":
            return self.run( [ str( tree ), "--quality-baseline", "--no-cache" ], cwd=tree )
        if kind == "notes":
            return self.run( [ str( tree ), f"--note-add=a.c: {READ_SENTINEL}", "--no-cache" ], cwd=tree )
        verb = "--baseline-update" if update else "--baseline"
        return self.run( [ str( tree ), "--arch=rules.txt", verb, "--no-cache" ], cwd=tree )

    def reader( self, kind: str, tree: Path ) -> subprocess.CompletedProcess[str] | None:
        if kind == "notes":
            return self.run( [ str( tree ), "--notes", "--no-cache" ], cwd=tree )
        if kind == "qualitybaseline":
            return self.run( [ str( tree ), "--quality-delta", "--legend=compact", "--no-cache" ], cwd=tree )
        return self.run( [ str( tree ), "--arch=rules.txt", "--no-cache" ], cwd=tree )

    def write_symlink_arm( self, kind: str ) -> None:
        label = f"{kind}-write"
        base = self.root / label
        tree = base / "tree"
        victim = base / "outside" / "victim.txt"
        self.make_tree( tree )
        victim.parent.mkdir( parents=True, exist_ok=True )
        victim.write_bytes( VICTIM_BYTES )
        pristine = victim.read_bytes()
        sidecar = tree / self.sidecar_for( kind )
        self.symlink( victim, sidecar )
        self.check( f"{label}/guard", self.same_link_target( sidecar, victim ), "native Win32 symlink planted outside the crawl tree" )
        result = self.writer( kind, tree )
        if result is None:
            return
        err = result.stderr.lower()
        self.check( f"{label}/victim", victim.read_bytes() == pristine, "victim bytes survived the writer" )
        self.check( f"{label}/rc", result.returncode != 0, f"writer refused with exit {result.returncode}" )
        self.check( f"{label}/reason", "refusing to write" in err and ( "symlink" in err or "reparse" in err ), "stderr names the refusal and symlink/reparse reason" )
        self.check( f"{label}/entry", self.same_link_target( sidecar, victim ), "user symlink remained untouched" )

    def write_regular_arm( self, kind: str ) -> None:
        label = f"{kind}-regular"
        tree = self.root / label / "tree"
        self.make_tree( tree )
        result = self.writer( kind, tree )
        sidecar = tree / self.sidecar_for( kind )
        self.check( f"{label}/rc", result is not None and result.returncode == 0, "regular sidecar writer returned success" )
        self.check( f"{label}/file", sidecar.is_file() and not sidecar.is_symlink() and sidecar.stat().st_size > 0, "sidecar is a regular non-empty file" )

    def directory_arm( self, kind: str ) -> None:
        label = f"{kind}-directory"
        tree = self.root / label / "tree"
        self.make_tree( tree )
        sidecar = tree / self.sidecar_for( kind )
        sidecar.mkdir( parents=True )
        result = self.writer( kind, tree )
        if result is None:
            return
        err = result.stderr.lower()
        self.check( f"{label}/rc", result.returncode != 0, f"directory was refused with exit {result.returncode}" )
        self.check( f"{label}/reason", ( "directory" in err or "not a regular file" in err ) and "symlink" not in err, f"stderr reports the non-regular directory failure, not a false symlink diagnosis: {result.stderr[:180]!r}" )

    def reparse_arm( self, kind: str ) -> None:
        label = f"{kind}-reparse-dir"
        base = self.root / label
        tree = base / "tree"
        target = base / "outside-dir"
        self.make_tree( tree )
        target.mkdir( parents=True )
        sidecar = tree / self.sidecar_for( kind )
        self.symlink( target, sidecar, directory=True )
        result = self.writer( kind, tree )
        if result is None:
            return
        err = result.stderr.lower()
        self.check( f"{label}/guard", sidecar.is_symlink(), "directory reparse point was planted natively" )
        self.check( f"{label}/rc", result.returncode != 0, f"directory reparse point was refused with exit {result.returncode}" )
        self.check( f"{label}/reason", "symlink" in err or "reparse" in err, "stderr discloses the reparse/symlink refusal" )

    def read_arm( self, kind: str ) -> None:
        label = f"{kind}-read"
        base = self.root / label
        tree = base / "tree"
        if kind == "archbaseline":
            self.make_arch_violation_tree( tree )
        else:
            self.make_tree( tree )
        if kind == "qualitybaseline":
            git = shutil.which( "git" )
            self.check( f"{label}/guard", git is not None, "git is available to pin the quality payload" )
            if git is None:
                return
            commands = [
                [ git, "init", "-q" ],
                [ git, "config", "user.email", "ripwire-test@example.invalid" ],
                [ git, "config", "user.name", "ripwire-test" ],
                [ git, "add", "a.c" ],
                [ git, "commit", "-qm", "init" ],
            ]
            for command in commands:
                try:
                    subprocess.run( command, cwd=str( tree ), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True )
                except ( OSError, subprocess.CalledProcessError ) as exc:
                    self.check( f"{label}/git", False, f"could not create pinned git fixture: {exc}" )
                    return
        created = self.writer( kind, tree )
        sidecar = tree / self.sidecar_for( kind )
        if created is None or not sidecar.is_file():
            self.check( f"{label}/guard", False, "regular payload could not be created" )
            return
        payload = base / "payload"
        payload.write_bytes( sidecar.read_bytes() )
        self.remove_path( sidecar )

        sidecar.write_bytes( payload.read_bytes() )
        control = self.reader( kind, tree )
        live = "<notes" if kind == "notes" else "quality-delta" if kind == "qualitybaseline" else "<arch"
        used = READ_SENTINEL if kind == "notes" else 'baseline="sidecar"' if kind == "qualitybaseline" else 'baselined="1"'
        regular_ok = control is not None and live in control.stdout and used in control.stdout
        detail = "regular sidecar was read and used"
        if not regular_ok and control is not None:
            detail += f"; stdout={control.stdout[:240]!r} stderr={control.stderr[:160]!r}"
        self.check( f"{label}/regular", regular_ok, detail )

        for mode in ( "outside", "inside" ):
            link = tree / self.sidecar_for( kind )
            self.remove_path( link )
            if mode == "outside":
                target = base / "outside" / "shared-sidecar"
                target.parent.mkdir( parents=True, exist_ok=True )
                target.write_bytes( payload.read_bytes() )
                self.symlink( target, link )
            else:
                target = tree / "docs" / "shared-sidecar"
                target.parent.mkdir( parents=True, exist_ok=True )
                target.write_bytes( payload.read_bytes() )
                self.symlink( Path( "docs" ) / "shared-sidecar", link )
            result = self.reader( kind, tree )
            if result is None:
                continue
            err = result.stderr.lower()
            self.check( f"{label}/{mode}/used", used not in result.stdout, "symlinked payload was not used" )
            self.check( f"{label}/{mode}/reason", "refusing to read" in err and ( "symlink" in err or "reparse" in err ), "stderr names the read refusal" )
            self.remove_path( link )

    def arch_bytes_arm( self ) -> None:
        label = "arch-bytes"
        base = self.root / label
        tree = base / "tree"
        self.make_tree( tree )
        sidecar = tree / ".ripwire_arch_baseline"
        planted = [ "# planted by native Windows sidecar gate\n", "\n" ]
        for index in range( 300, 0, -1 ):
            planted.append( f"{( index * ARCH_MUL) & (( 1 << 64 ) - 1):016x}\n" )
        planted.extend( [ "1\n", "FF\n", "00000000DEADBEEF\n", "ffffffffffffffff\n", "0000000000000001\n" ] )
        sidecar.write_text( "".join( planted ), encoding="utf-8" )
        wanted_values = [ ( index * ARCH_MUL ) & (( 1 << 64 ) - 1) for index in range( 1, 301 ) ] + [ 1, 255, 0xDEADBEEF, ( 1 << 64 ) - 1 ]
        wanted = ARCH_HEADER + "".join( f"{ value:016x}\n" for value in sorted( set( wanted_values ) ) )
        result = self.writer( "archbaseline", tree, update=True )
        self.check( f"{label}/rows", len( wanted.splitlines() ) - 1 == 304, "canonical expectation has 304 distinct rows" )
        self.check( f"{label}/write", result is not None and result.returncode == 0 and sidecar.read_text( encoding="utf-8" ) == wanted, "baseline-update bytes are canonical and byte-identical" )

    def race_arm( self, kind: str ) -> None:
        label = f"{kind}-race"
        base = self.root / label
        tree = base / "tree"
        victim = base / "outside" / "victim.txt"
        self.make_tree( tree )
        victim.parent.mkdir( parents=True, exist_ok=True )
        victim.write_bytes( VICTIM_BYTES )
        sidecar = tree / self.sidecar_for( kind )
        stop = threading.Event()
        ready = threading.Event()

        def swap() -> None:
            while not stop.is_set():
                try:
                    self.symlink( victim, sidecar )
                    ready.set()
                except OSError:
                    pass
                try:
                    self.remove_path( sidecar )
                except OSError:
                    pass

        thread = threading.Thread( target=swap, name=f"ripwire-{label}-swap", daemon=True )
        thread.start()
        ready.wait( timeout=5.0 )
        self.check( f"{label}/guard", ready.is_set(), "native symlink swapper reached the writer window" )
        if not ready.is_set():
            stop.set()
            thread.join( timeout=5.0 )
            return
        refusals = writes = hits = 0
        for _ in range( 25 ):
            victim.write_bytes( VICTIM_BYTES )
            result = self.writer( kind, tree )
            if result is None:
                break
            if "refusing to write" in result.stderr.lower():
                refusals += 1
            if result.returncode == 0:
                writes += 1
            if victim.read_bytes() != VICTIM_BYTES:
                hits += 1
        stop.set()
        thread.join( timeout=5.0 )
        try:
            self.remove_path( sidecar )
        except OSError:
            pass
        self.check( f"{label}/window", refusals > 0 and writes > 0, f"observed {refusals} refusals and {writes} regular writes" )
        self.check( f"{label}/victim", hits == 0, f"victim survived all racing writes ({hits} corruptions)" )

    def intermediate_reparse_arm( self, kind: str ) -> None:
        label = f"{kind}-intermediate-reparse"
        base = self.root / label
        lexical = base / "tree"
        outside = base / "outside"
        outside_root = outside / "sub"
        if kind == "archbaseline":
            return
        else:
            self.make_tree( outside_root )
        lexical.mkdir( parents=True, exist_ok=True )
        root_link = lexical / "link"
        self.symlink( outside, root_link, directory=True )
        result = self.writer( kind, root_link / "sub" )
        outside_sidecar = outside_root / self.sidecar_for( kind )
        err = result.stderr.lower() if result is not None else ""
        self.check( f"{label}/guard", root_link.is_symlink(), "intermediate directory reparse point was planted" )
        self.check( f"{label}/rc", result is not None and result.returncode != 0, "writer refused the intermediate reparse path" )
        self.check( f"{label}/outside", not outside_sidecar.exists(), "writer did not create a sidecar outside the lexical root" )
        self.check( f"{label}/reason", "reparse" in err or "symlink" in err, "stderr discloses the intermediate reparse refusal" )

    def direct_volume_reparse_arm( self, kind: str ) -> None:
        label = f"{kind}-direct-volume-reparse"
        outside = Path( tempfile.mkdtemp( prefix="ripwire-sidecar-direct-" ) )
        real_tree = outside / "tree"
        root_link = Path( Path( self.binary.anchor ) / f"ripwire-sidecar-{os.getpid()}-{uuid.uuid4().hex}" )
        try:
            self.make_tree( real_tree )
            outside_sidecar = real_tree / self.sidecar_for( kind )
            seed = self.writer( kind, real_tree )
            if seed is None or seed.returncode != 0 or not outside_sidecar.is_file():
                self.check( f"{label}/seed", False, "could not create a valid sidecar before planting the direct-volume reparse point" )
                return
            pristine = outside_sidecar.read_bytes()
            self.symlink( real_tree, root_link, directory=True )
            if kind == "qualitybaseline":
                args = [ str( root_link ), "--quality-baseline", "--no-cache" ]
            elif kind == "notes":
                args = [ str( root_link ), f"--note-add=a.c: {READ_SENTINEL}", "--no-cache" ]
            else:
                args = [ str( root_link ), "--arch=rules.txt", "--baseline", "--no-cache" ]
            result = self.run( args )
            err = result.stderr.lower() if result is not None else ""
            self.check( f"{label}/guard", root_link.is_symlink(), "direct-volume directory reparse point was planted" )
            self.check( f"{label}/rc", result is not None and result.returncode != 0, "writer refused a reparse parent directly below the volume root" )
            self.check( f"{label}/outside", outside_sidecar.read_bytes() == pristine, "writer did not overwrite a sidecar through the direct-volume reparse point" )
            self.check( f"{label}/reason", "reparse" in err or "symlink" in err, "stderr discloses the direct-volume reparse refusal" )
        finally:
            self.remove_path( root_link )
            shutil.rmtree( outside, ignore_errors=True )

    def source_arm( self ) -> None:
        source = ( self.binary.parent.parent / "src" / "pathguard.h" )
        # build-win-merge/ripwire.exe lives one directory below the repository root.
        if not source.is_file():
            source = Path( __file__ ).resolve().parents[1] / "src" / "pathguard.h"
        try:
            text = source.read_text( encoding="utf-8" )
        except OSError as exc:
            self.check( "pathguard/source", False, f"could not read source: {exc}" )
            return
        requirements = {
            "openNoFollowTruncate": "openNoFollowTruncate" in text,
            "openNoFollowRead": "openNoFollowRead" in text,
            "win32-reparse": "FILE_FLAG_OPEN_REPARSE_POINT" in text and "GetFileType" in text,
            "nofollow": "O_NOFOLLOW" in text,
            "regular-check": "S_ISREG" in text,
            "no-advisory-guard": "refuseSymlinkWrite" not in text,
        }
        for name, condition in requirements.items():
            self.check( f"pathguard/{name}", condition, "Windows pathguard invariant is present" if condition else "required invariant is missing" )


def main() -> int:
    if os.name != "nt":
        print( "  FAIL  platform: this helper must run under native Windows Python" )
        return 2
    if len( sys.argv ) != 2:
        print( "usage: sidecarsymlinkcheck_windows.py RIPWIRE_BIN", file=sys.stderr )
        return 2
    binary = Path( sys.argv[1] ).resolve()
    if not binary.is_file():
        print( f"no ripwire binary at {binary}", file=sys.stderr )
        return 2

    with tempfile.TemporaryDirectory( prefix="ripwire-sidecars-windows-" ) as temporary:
        suite = Suite( Path( temporary ), binary )
        print( f"sidecarsymlinkcheck[windows]: BIN={binary} TMP={temporary}" )
        suite.source_arm()
        for kind in ( "qualitybaseline", "notes", "archbaseline" ):
            suite.write_symlink_arm( kind )
            suite.write_regular_arm( kind )
            suite.directory_arm( kind )
            suite.reparse_arm( kind )
            suite.intermediate_reparse_arm( kind )
            suite.direct_volume_reparse_arm( kind )
            suite.read_arm( kind )
            suite.race_arm( kind )
        suite.arch_bytes_arm()
        print( f"sidecarsymlinkcheck[windows]: checks={suite.checks} failures={suite.failures}" )
        if suite.failures:
            return 1
    print( "ALL PASS" )
    return 0


if __name__ == "__main__":
    raise SystemExit( main() )
