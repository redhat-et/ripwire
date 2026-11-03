"""Native Windows cache ACL regression; invoked by cacheisolationcheck.sh.

Observe NTFS ChangeTime, not timing thresholds: reapplying an unchanged DACL
changes it and propagates inheritable ACEs through the entire cache tree.
"""
import ctypes
from ctypes import wintypes
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


class FileBasicInfo(ctypes.Structure):
    _fields_ = [(name, ctypes.c_longlong) for name in
                ("creation", "access", "write", "change")] + [("attributes", wintypes.DWORD)]


def change_time(path):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                  ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.GetFileInformationByHandleEx.argtypes = [wintypes.HANDLE, ctypes.c_int,
                                                   ctypes.c_void_p, wintypes.DWORD]
    kernel.GetFileInformationByHandleEx.restype = wintypes.BOOL
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.CloseHandle.restype = wintypes.BOOL
    handle = kernel.CreateFileW(str(path), 0x80, 7, None, 3, 0x02000000, None)
    if handle == wintypes.HANDLE(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        info = FileBasicInfo()
        if not kernel.GetFileInformationByHandleEx(handle, 0, ctypes.byref(info), ctypes.sizeof(info)):
            raise ctypes.WinError(ctypes.get_last_error())
        return info.change
    finally:
        if not kernel.CloseHandle(handle):
            raise ctypes.WinError(ctypes.get_last_error())


def dacl_sddl(path):
    security = ctypes.WinDLL("advapi32", use_last_error=True)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    security.GetNamedSecurityInfoW.argtypes = [wintypes.LPWSTR, ctypes.c_int, wintypes.DWORD,
                                             ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p,
                                             ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
    security.GetNamedSecurityInfoW.restype = wintypes.DWORD
    security.ConvertSecurityDescriptorToStringSecurityDescriptorW.argtypes = [
        ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(wintypes.LPWSTR), ctypes.c_void_p]
    security.ConvertSecurityDescriptorToStringSecurityDescriptorW.restype = wintypes.BOOL
    kernel.LocalFree.argtypes = [ctypes.c_void_p]
    kernel.LocalFree.restype = ctypes.c_void_p
    descriptor = ctypes.c_void_p()
    error = security.GetNamedSecurityInfoW(str(path), 1, 4, None, None, None, None,
                                          ctypes.byref(descriptor))
    if error:
        raise ctypes.WinError(error)
    text = wintypes.LPWSTR()
    try:
        if not security.ConvertSecurityDescriptorToStringSecurityDescriptorW(
                descriptor, 1, 4, ctypes.byref(text), None):
            raise ctypes.WinError(ctypes.get_last_error())
        return text.value
    finally:
        if text:
            kernel.LocalFree(ctypes.cast(text, ctypes.c_void_p))
        kernel.LocalFree(descriptor)


# isOwnerClassSid in os_win32.cpp: OWNER RIGHTS, CREATOR OWNER, Administrators, SYSTEM and this user.
OWNER_CLASS_TRUSTEES = {"OW", "CO", "BA", "SY"}
# FILE_LIST_DIRECTORY | FILE_ADD_FILE | FILE_ADD_SUBDIRECTORY | FILE_TRAVERSE | FILE_DELETE_CHILD
# (POSIX `w` on a directory covers removing and renaming entries, and the cache saves by temp + rename).
OWNER_RWX_MASK = 0x0001 | 0x0002 | 0x0004 | 0x0020 | 0x0040
SDDL_RIGHTS = {
    "GA": OWNER_RWX_MASK, "FA": OWNER_RWX_MASK,
    "GR": 0x0001, "FR": 0x0001, "CC": 0x0001,
    "GW": 0x0006, "FW": 0x0006, "DC": 0x0002, "LC": 0x0004,
    "GX": 0x0020, "FX": 0x0020, "WP": 0x0020, "DT": 0x0040,
}


def current_user_sid():
    result = subprocess.run(["whoami.exe", "/user", "/fo", "csv", "/nh"],
                            capture_output=True, text=True, check=True, timeout=30)
    return result.stdout.strip().split(",")[-1].strip('"')


def sddl_mask(rights):
    if rights.lower().startswith("0x"):
        mask = int(rights, 16)
        if mask & 0x10000000:
            mask |= OWNER_RWX_MASK
        if mask & 0x80000000:
            mask |= 0x0001
        if mask & 0x40000000:
            mask |= 0x0006
        if mask & 0x20000000:
            mask |= 0x0020
        return mask
    mask = 0
    for index in range(0, len(rights), 2):
        mask |= SDDL_RIGHTS.get(rights[index:index + 2], 0)
    return mask


def owner_only(path):
    """Windows counterpart of mode 0700: protected DACL whose allow ACEs name only
    owner-class principals and whose effective owner ACEs grant rwx, the same rule
    os_win32.cpp readOwnerAndMode applies."""
    sddl = dacl_sddl(path)
    dacl = sddl[sddl.index("D:"):] if "D:" in sddl else ""
    if not dacl.startswith("D:P"):
        return False, sddl
    user_sid = current_user_sid()
    trustees = OWNER_CLASS_TRUSTEES | {user_sid}
    owner_trustees = {"OW", user_sid} | ({"BA"} if ctypes.windll.shell32.IsUserAnAdmin() else set())
    owner_mask = 0
    for ace in re.findall(r"\(([^)]*)\)", dacl):
        fields = ace.split(";")
        if len(fields) != 6:
            return False, sddl
        ace_type, ace_flags, rights, _, _, trustee = fields
        applies_to_self = "IO" not in ace_flags
        if ace_type == "D":
            # Fail closed like os_win32.cpp: a self-applying deny on a required bit is not 0700,
            # whichever SID it names (CheckTokenMembership is FALSE for a deny-only group).
            if applies_to_self and sddl_mask(rights) & OWNER_RWX_MASK:
                return False, sddl
            continue
        if ace_type != "A" or trustee not in trustees:
            return False, sddl
        if applies_to_self and trustee in owner_trustees:
            owner_mask |= sddl_mask(rights)
    return (owner_mask & OWNER_RWX_MASK) == OWNER_RWX_MASK, sddl


class CacheLadderWindows(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ripwire-acl-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.shared = self.root / "shared"
        self.shared.mkdir()
        self.fixture = self.root / "fixture"
        self.fixture.mkdir()
        (self.fixture / "code.ts").write_text("export function alphaOne() { return 42; }\n")
        self.env = {**os.environ, "TMPDIR": str(self.shared), "RIPWIRE_CACHE_STATS": "1"}
        self.cache = self.shared / "ripwire"

    def query(self):
        result = subprocess.run([BINARY, str(self.fixture), "--grep=alphaOne", "--legend=compact"],
                                env=self.env, capture_output=True, text=True, timeout=30, check=True)
        self.assertIn("alphaOne", result.stdout)
        return result

    def prime(self):
        self.query()
        warm = self.query()
        self.assertIn("reparsed=0 reused=1", warm.stderr)
        return warm.stdout

    def test_warm_private_cache_does_not_reapply_acl(self):
        expected = self.prime()
        before = change_time(self.cache)
        result = self.query()
        self.assertEqual(result.stdout, expected)
        self.assertIn("reparsed=0 reused=1", result.stderr)
        self.assertEqual(change_time(self.cache), before,
                         "warm cache rewrote directory metadata (inheritable ACL propagation)")

    def test_permissive_cache_is_repaired_once(self):
        expected = self.prime()
        subprocess.run(["icacls.exe", str(self.cache), "/grant", "*S-1-1-0:(OI)(CI)RX"],
                       capture_output=True, text=True, check=True, timeout=30)
        before = change_time(self.cache)
        self.assertEqual(self.query().stdout, expected)
        self.assertNotEqual(change_time(self.cache), before, "permissive ACL was not repaired")
        repaired = dacl_sddl(self.cache)
        self.assertTrue(repaired.startswith("D:P"), repaired)
        self.assertNotIn(";;;WD)", repaired, "Everyone still has cache access")
        stable = change_time(self.cache)
        self.query()
        self.assertEqual(change_time(self.cache), stable)

    def assert_repaired_once(self, icacls_args, why):
        shutil.rmtree(self.cache, ignore_errors=True)
        self.cache.mkdir()
        subprocess.run(["icacls.exe", str(self.cache), "/inheritance:r", *icacls_args],
                       capture_output=True, text=True, check=True, timeout=30)
        self.assertFalse(owner_only(self.cache)[0], dacl_sddl(self.cache))
        before = change_time(self.cache)
        first = self.query()
        self.assertNotIn("cannot write", first.stderr)
        self.assertNotIn("rename failed", first.stderr)
        self.assertNotEqual(change_time(self.cache), before, why)
        self.assertTrue(owner_only(self.cache)[0], dacl_sddl(self.cache))
        stable = change_time(self.cache)
        warm = self.query()
        self.assertIn("reparsed=0 reused=1", warm.stderr)
        self.assertEqual(change_time(self.cache), stable)

    def test_owner_only_without_add_file_is_repaired_once(self):
        user_sid = current_user_sid()
        for grant in ("(OI)(CI)RX", "(OI)(CI)(RX,WA,WDAC)"):
            with self.subTest(grant=grant):
                self.assert_repaired_once(["/grant:r", f"*{user_sid}:{grant}"],
                                          "owner-only DACL without FILE_ADD_FILE was not repaired")

    def test_owner_only_without_delete_child_is_repaired_once(self):
        # Mask 0x27: list, add file, add subdirectory, traverse, but no right to rename an entry.
        self.assert_repaired_once(["/grant:r", f"*{current_user_sid()}:(OI)(CI)(RD,WD,AD,X)"],
                                  "owner-only DACL without FILE_DELETE_CHILD was not repaired")

    def test_deny_on_required_bit_is_repaired_once(self):
        # Full grant plus a deny on the deny-only Administrators group (the UAC-filtered default),
        # for which CheckTokenMembership says "not a member" although the access check applies the deny.
        self.assert_repaired_once(["/grant:r", f"*{current_user_sid()}:(OI)(CI)F",
                                   "/deny", "*S-1-5-32-544:(OI)(CI)(AD,WD)"],
                                  "owner-only DACL with a deny on a required bit was not repaired")

    def test_junction_cache_is_refused_without_touching_target(self):
        target = self.root / "target"
        target.mkdir()
        # No command shell: a temp path holding cmd.exe metacharacters (&, ^) stays one argument.
        import _winapi  # Windows-only CPython module; the platform guard runs before the tests
        _winapi.CreateJunction(str(target), str(self.cache))
        self.addCleanup(self.cache.rmdir)
        before = (change_time(target), dacl_sddl(target))
        result = self.query()
        self.assertIn("reparsed=1 reused=0", result.stderr)
        self.assertEqual((change_time(target), dacl_sddl(target)), before)
        self.assertEqual(list(target.iterdir()), [])


if __name__ == "__main__":
    if sys.platform != "win32":
        raise SystemExit("This regression requires native Windows Python")
    if len(sys.argv) == 3 and sys.argv[1] == "--owner-only":
        private, sddl = owner_only(sys.argv[2])
        print(sddl)
        raise SystemExit(0 if private else 1)
    BINARY = str(Path(sys.argv.pop(1)).resolve())
    unittest.main()
