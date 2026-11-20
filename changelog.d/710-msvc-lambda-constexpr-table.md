### Fixed — the MSVC build reads the two `--for` route cue tables again (#710)

`src/forroute.h`'s `kSuffixes` (rule `\bcall(s|ed|ers?)?\b`) and `kPreps` (rule `\b(chain|path)s?\s+(from|between)\b`)
were function-local `constexpr` tables odr-used from *inside* a lambda. MSVC rejects that with
`error C2326: function cannot access 'kSuffixes'`, failing `src/main.cpp.obj` and stopping the `windows (cl, ninja)`
build; `clang-cl`, AppleClang and gcc all accept the same code, so the divergence was invisible outside the `cl` job.
Both tables are now `static constexpr`: a variable with static storage duration is never captured, so no implicit
capture is required of any compiler. No behaviour changes — the route rules, their cues and their order are untouched.

The other 19 function-local `constexpr` tables in `src/` are unaffected: each is passed as an *argument* to the
algorithm (`std::ranges::any_of( kWords, … )`), evaluated in the enclosing function's scope, so no lambda ever
accesses them. `cl` compiled all 19 in the same run that rejected these two.
