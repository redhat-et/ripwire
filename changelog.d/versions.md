### Changed — the versions this change moves, stated once

`kParserVer` 259 → 269 (file tag 270): the C++ member-pointer slot records (a `&Cls::m` value reference, a
`( o.*x.f )( … )` slot call, a C nested designated path or macro-cast slot call, a class body fact's scope path, and a C++
base that is a template parameter of the deriving class) carried 257 (258), 259 and 260 on their branch, so a cache written
before them would replay the older slot rows. 269 sits above every live branch and pull-request number (the interface-receiver
peel carries 259, the alias-import records 261 and the string/literal records 263, 265 and 267 on theirs); the next train goes
above 269 and 270. A cache written by 0.6.9 is re-parsed once. `kCacheVersion` stays 46 and the quality-snapshot scheme stays 24:
no record changes shape. The session legend dictionary is `dictv=1d522ffeeb3f37c2 entries=981`.
