### Changed — the versions this change moves, stated once

`kParserVer` 259 → 283 (file tag 284). 283 (train 43b): Python registrar facts and TS/JS provider-record literal marks (their branch
carried 273–281), Python dotted-string and import-sink facts (their branch carried 274–275). 271 (file tag 272): the C++ member-pointer slot records (a `&Cls::m` value reference, a
`( o.*x.f )( … )` slot call, a C nested designated path or macro-cast slot call, a class body fact's scope path, and a C++
base that is a template parameter of the deriving class; 269 on main), the interface-receiver peel's records (a C++
smart-pointer alias carries its pointee, a member whose written type is a template parameter is marked, a Rust `&dyn T` /
`Box<dyn T>` / `impl T` result is recorded) and the TS/JS re-export specifier records each carried lower numbers on their
branches (257–262), so a cache written before them would replay the older rows. 271 sits above every live branch and
pull-request number (the string/literal records carry 263, 265 and 267 on theirs). `kCacheVersion` 46 → 48: a re-export
specifier is a new binding kind appended to the cache record (its branch carried 47). A cache written by 0.6.9 is re-parsed
once. The quality-snapshot scheme stays 24: no snapshot record changes shape. The session legend dictionary is `dictv=1ecb7eb9fe8418d2 entries=997`.

The history-walk cache's `kQChurnCacheScheme` moves 3 → 4 (#433: a blob written by a pre-fix binary holds the old line-frame reader's stream, which for the repositories the framing fix targets is the corrupted one, and no key component can tell that blob from a fresh read; every repository's history is walked once more after the upgrade, and on trees with ordinary names the walk produces the same stream, so the cost is one cold walk and no changed answer).
