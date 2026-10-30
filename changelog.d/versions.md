### Changed — the versions this change moves, stated once

`kParserVer` 259 → 269 (file tag 270): the C++ member-pointer slot records (a `&Cls::m` value reference, a
`( o.*x.f )( … )` slot call, a C nested designated path or macro-cast slot call, a class body fact's scope path, and a C++
base that is a template parameter of the deriving class) carried 257 (258), 259 and 260 on their branch, so a cache written
before them would replay the older slot rows. 269 sits above every live branch and pull-request number (the interface-receiver
peel carries 259, the alias-import records 261 and the string/literal records 263, 265 and 267 on theirs); the next train goes
above 269 and 270. A cache written by 0.6.9 is re-parsed once. `kCacheVersion` stays 46 and the quality-snapshot scheme stays 24:
no record changes shape. The session legend dictionary is `dictv=1d522ffeeb3f37c2 entries=981`.

The history-walk cache's `kQChurnCacheScheme` moves 3 → 4 (#433: a blob written by a pre-fix binary holds the old line-frame reader's stream, which for the repositories the framing fix targets is the corrupted one, and no key component can tell that blob from a fresh read; every repository's history is walked once more after the upgrade, and on trees with ordinary names the walk produces the same stream, so the cost is one cold walk and no changed answer).
