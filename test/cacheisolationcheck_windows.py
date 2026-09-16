import ctypes
import os
import sys
from ctypes import wintypes


ADVAPI32 = ctypes.WinDLL("advapi32", use_last_error=True)
KERNEL32 = ctypes.WinDLL("kernel32", use_last_error=True)

SE_FILE_OBJECT = 1
DACL_SECURITY_INFORMATION = 0x00000004
OWNER_SECURITY_INFORMATION = 0x00000001
PROTECTED_DACL_SECURITY_INFORMATION = 0x80000000
SE_DACL_PROTECTED = 0x1000
ACCESS_ALLOWED_ACE_TYPE = 0
FILE_ALL_ACCESS = 0x001F01FF
GENERIC_ALL = 0x10000000
OBJECT_INHERIT_ACE = 0x01
CONTAINER_INHERIT_ACE = 0x02
INHERIT_ONLY_ACE = 0x08
TokenUser = 1
TOKEN_QUERY = 0x0008

PSID = ctypes.c_void_p
PACL = ctypes.c_void_p
PSECURITY_DESCRIPTOR = ctypes.c_void_p

ADVAPI32.GetNamedSecurityInfoW.argtypes = [
    wintypes.LPCWSTR,
    wintypes.DWORD,
    wintypes.DWORD,
    ctypes.POINTER(PSID),
    ctypes.POINTER(PSID),
    ctypes.POINTER(PACL),
    ctypes.POINTER(PACL),
    ctypes.POINTER(PSECURITY_DESCRIPTOR),
]
ADVAPI32.GetNamedSecurityInfoW.restype = wintypes.DWORD
ADVAPI32.GetSecurityDescriptorControl.argtypes = [
    PSECURITY_DESCRIPTOR,
    ctypes.POINTER(wintypes.WORD),
    ctypes.POINTER(wintypes.DWORD),
]
ADVAPI32.GetSecurityDescriptorControl.restype = wintypes.BOOL
ADVAPI32.GetSecurityDescriptorDacl.argtypes = [
    PSECURITY_DESCRIPTOR,
    ctypes.POINTER(wintypes.BOOL),
    ctypes.POINTER(PACL),
    ctypes.POINTER(wintypes.BOOL),
]
ADVAPI32.GetSecurityDescriptorDacl.restype = wintypes.BOOL
ADVAPI32.GetAclInformation.argtypes = [
    PACL,
    ctypes.c_void_p,
    wintypes.DWORD,
    wintypes.DWORD,
]
ADVAPI32.GetAclInformation.restype = wintypes.BOOL
ADVAPI32.GetAce.argtypes = [PACL, wintypes.DWORD, ctypes.POINTER(ctypes.c_void_p)]
ADVAPI32.GetAce.restype = wintypes.BOOL
ADVAPI32.ConvertSidToStringSidW.argtypes = [PSID, ctypes.POINTER(wintypes.LPWSTR)]
ADVAPI32.ConvertSidToStringSidW.restype = wintypes.BOOL
ADVAPI32.OpenProcessToken.argtypes = [wintypes.HANDLE, wintypes.DWORD, ctypes.POINTER(wintypes.HANDLE)]
ADVAPI32.OpenProcessToken.restype = wintypes.BOOL
ADVAPI32.GetTokenInformation.argtypes = [
    wintypes.HANDLE,
    wintypes.DWORD,
    ctypes.c_void_p,
    wintypes.DWORD,
    ctypes.POINTER(wintypes.DWORD),
]
ADVAPI32.GetTokenInformation.restype = wintypes.BOOL
KERNEL32.GetCurrentProcess.restype = wintypes.HANDLE
KERNEL32.CloseHandle.argtypes = [wintypes.HANDLE]
KERNEL32.LocalFree.argtypes = [wintypes.HLOCAL]


class AclSizeInformation(ctypes.Structure):
    _fields_ = [("AceCount", wintypes.DWORD), ("AclBytesInUse", wintypes.DWORD), ("AclBytesFree", wintypes.DWORD)]


class AceHeader(ctypes.Structure):
    _fields_ = [("AceType", wintypes.BYTE), ("AceFlags", wintypes.BYTE), ("AceSize", wintypes.WORD)]


def sid_string(sid):
    value = wintypes.LPWSTR()
    if not ADVAPI32.ConvertSidToStringSidW(sid, ctypes.byref(value)):
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        return value.value
    finally:
        KERNEL32.LocalFree(value)


def check(path):
    owner = PSID()
    group = PSID()
    dacl = PACL()
    sacl = PACL()
    descriptor = PSECURITY_DESCRIPTOR()
    result = ADVAPI32.GetNamedSecurityInfoW(
        str(path),
        SE_FILE_OBJECT,
        OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION,
        ctypes.byref(owner),
        ctypes.byref(group),
        ctypes.byref(dacl),
        ctypes.byref(sacl),
        ctypes.byref(descriptor),
    )
    if result:
        raise ctypes.WinError(result)
    try:
        control = wintypes.WORD()
        revision = wintypes.DWORD()
        if not ADVAPI32.GetSecurityDescriptorControl(descriptor, ctypes.byref(control), ctypes.byref(revision)):
            raise ctypes.WinError(ctypes.get_last_error())
        if not control.value & SE_DACL_PROTECTED:
            raise AssertionError("DACL inheritance is enabled")
        present = wintypes.BOOL()
        defaulted = wintypes.BOOL()
        if not ADVAPI32.GetSecurityDescriptorDacl(descriptor, ctypes.byref(present), ctypes.byref(dacl), ctypes.byref(defaulted)) or not present.value or not dacl:
            raise AssertionError("directory has no explicit DACL")
        info = AclSizeInformation()
        if not ADVAPI32.GetAclInformation(dacl, ctypes.byref(info), ctypes.sizeof(info), 2):
            raise ctypes.WinError(ctypes.get_last_error())
        allowed = {"S-1-3-4", "S-1-5-32-544"}
        seen = set()
        sid_flags = {sid: [] for sid in allowed}
        for index in range(info.AceCount):
            ace = ctypes.c_void_p()
            if not ADVAPI32.GetAce(dacl, index, ctypes.byref(ace)):
                raise ctypes.WinError(ctypes.get_last_error())
            header = AceHeader.from_address(ace.value)
            mask = wintypes.DWORD.from_address(ace.value + ctypes.sizeof(AceHeader)).value
            sid = sid_string(ctypes.c_void_p(ace.value + 8))
            if header.AceType != ACCESS_ALLOWED_ACE_TYPE:
                raise AssertionError("directory DACL contains a non-allow ACE")
            if header.AceFlags not in (0, OBJECT_INHERIT_ACE | CONTAINER_INHERIT_ACE, OBJECT_INHERIT_ACE | CONTAINER_INHERIT_ACE | INHERIT_ONLY_ACE):
                raise AssertionError("directory DACL ACE inheritance flags are not owner-only")
            if (mask & FILE_ALL_ACCESS != FILE_ALL_ACCESS) and (mask & GENERIC_ALL != GENERIC_ALL):
                raise AssertionError("directory DACL ACE is not full-control")
            if sid not in allowed:
                raise AssertionError(f"unexpected DACL principal: {sid}")
            seen.add(sid)
            sid_flags[sid].append(header.AceFlags)
        valid_forms = all(
            sorted(flags) in ([OBJECT_INHERIT_ACE | CONTAINER_INHERIT_ACE], [0, OBJECT_INHERIT_ACE | CONTAINER_INHERIT_ACE | INHERIT_ONLY_ACE])
            for flags in sid_flags.values()
        )
        if seen != allowed or not valid_forms:
            raise AssertionError(f"DACL principals are {sorted(seen)!r}, expected protected owner-rights/admin ACE forms")
    finally:
        if descriptor:
            KERNEL32.LocalFree(descriptor)


def main():
    try:
        check(sys.argv[1])
    except Exception as exc:
        print(f"acl_probe=fail: {exc}")
        return 1
    print("acl_probe=owner-admin-protected")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
