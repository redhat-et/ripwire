// delta.go — a fourth file whose tokens DON'T overlap the others, so a regex anchored on
// a token unique to one file narrows the candidate set to a single file (prefilter excludes
// the rest). Used to prove the prefilter is doing real work, not trivially scanning all.
package delta

func Quux() int { return 42 }      // 'Quux' appears nowhere else

// 'anchored' anchored-int line lives only in alpha.cpp; delta has none.
var notInt = "this line starts with whitespace before any int keyword"
