### Changed — a call site's callee name counts once in the BM25 document, however many candidates it split over

The lexical ranker adds each caller's callee names to its BM25 document. It used to add one name per resolved edge, so a
by-name call the resolver split over N candidates put the name in the document N times: axum's
`Body::from(self).into_response()` wrote `into_response` 31 times into every `IntoResponse` impl that calls it. In
pydantic, where test modules each define their own `class Model`, the split `Model(...)` calls added more than half a
million such copies. Edges sharing a callee name now count as many times as the caller's own references spell that
name, at most. A name the caller never spells (a Ruby `new` reaching `initialize`, an FFI binding) keeps the old count.
Ranking moves in every language where calls split. It also stops depending on how many splits the resolver leaves, so
an edge fix that resolves a split no longer moves the scores of files that have nothing to do with it.
