### Added — page 1 of a who-calls `--for` answer ends early when its callers block proves itself complete

When the default page 1 of an unrouted `--for` answer leads with `<callers by="subject">` and that block shows every caller it
counts (`shown=` equals `total=`, nothing capped) and no evidence of a miss is found, the page ends right after the block:
`early="proven"`, `withheld_bytes=` and `deferred=` say what it leaves out, and `next=` is the full page 1. Gate:
`test/forverbroutecheck.sh`. Confirmed once on a fresh held-out set (52 questions): 2 pages ended early, each
still complete, about 16 KB down to about 2 KB; no answer lost an item.
