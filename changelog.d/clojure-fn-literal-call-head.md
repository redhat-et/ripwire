### Fixed — Clojure: the call that is the whole body of `#(f %)` is recorded (#548, thanks @IG-ABHINAV)

An anonymous function literal reads as `(fn* [x] (f x))`, but its own head was never extracted as a call, so `(map #(cube %) xs)` left `cube` without that caller in `--callers`, `--callees`, `--impact` and `--uses`. A call nested inside the literal (`#(+ (square %1) %2)`) already worked, which hid the gap. The head is now a call, also under metadata (`^:once #(cube %)`). A quoted literal stays inert, a special-form head (`#(if % 1 2)`, `#(doto %)`) records nothing, and a parameter head (`#(%)`, `#(%1 %2)`) is never resolved to a definition. New arm 2 in `test/clojurecheck.sh`. On the fixtures only the outputs that name the two new callers of `cube` move (the map, `--tree`, and `--callers`, `--impact`, `--uses` of `cube`); the medley clone (weavejester/medley) is byte-identical.

Versions: `kParserVer` 342 -> 344 (rich file tag 345).
