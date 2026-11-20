### Fixed — a C++ call no longer binds to a same-named base class in another namespace

`connection_.state()` on a `Network::Connection&` printed `Http::FilterManager::state` as a resolved callee
(envoy: 36 callers listed for that method, the sampled ones all wrong). Two things went wrong together. The
base walk reads a table of method BODIES, so it passed the pure virtual `Connection::state` that ends C++'s
lookup; and it followed the base clause `: public FilterManager` by its bare name into the unrelated
`Http::FilterManager`. A bare call inside a member function went wrong the same way through the ladder's
"the caller's class reaches it" proof.

Both now read the base the deriving class names: the scope its clause is written in (a qualifier, the class it
is nested in, the namespaces its file defines things in), then the base the implementors map proved, then the
one same-named class its file includes. A class that declares the member with no body ends the walk, and the
call goes to the interface tier (one implementor is the edge; several decline with `gate="iface"`). A base
name that stays two classes is not bound: the call is hedged `via="name"` or declined, never a plain row. A
bare call to a name the class or a base declares with no body no longer falls to a free function of that name.

Measured on envoy with `--pin-census` before and after (321,956 call sites): 326 sites change.
`--callers` of `Http::FilterManager::state` goes from 36 callers (33 unhedged) to 8 (3 unhedged), and those 3
are its own (`UpstreamFilterManager::sendLocalReply`, `::isAborted`, `ActiveStreamDecoderFilter::injectDecodedData`).
ninja: 1 site of 5,765 (`DiskInterface::MakeDirs` no longer binds the pure virtual `MakeDir` call to the file's
free function). Only the C-family walk changed; the waybar and htop maps are byte-identical.

What it does NOT mean: a class's namespace is still not in the index. Where a base name has two classes and
neither the clause's scope nor the includes single one out, the call is hedged, not resolved. The walk still
starts from the receiver type's final name segment (`prov="final-segment"` discloses that), and a field read
from a base class is still found by the base's name.
