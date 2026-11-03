#!/usr/bin/env bash
# writtenspellingcheck.sh — a seed spelled the way the SOURCE spells it binds the one definition it names, and
# nothing else: graph.h resolveAllByWrittenSpelling, the last tier of resolveAllByNameQualified (lane qn-input).
#
# Three shapes answered "symbol not found" before the tier (RED-FIRST, recorded 2026-10-25 against the base binary
# 681b49e5: every BIND arm below failed rc=1, every REFUSE arm already refused, every KEEP arm already passed):
#   (1) a TS method as `Class.method` (TS records no Symbol::scope; the owner is read by containment);
#   (2) a module / crate / package prefix: Python `asyncio.run`, `json.dump`, Go `batcheval.Put`, Rust `my_crate::Buffer::edit`;
#   (3) a C++ owner the index keeps only the innermost label of: an out-of-line nested-class definition and a
#       namespace-qualified one.
# The REFUSE arms are the false-claim controls: an owner nothing encloses, two same-named classes, an import alias,
# a type alias, a namesake owner in another package/namespace, a prefix two crates both satisfy, and a module no
# path names. Each target calls its own helper, which is the discriminator the arms grep for.
#
# Usage:  test/writtenspellingcheck.sh [BIN]   (BIN falls back to RIPWIRE_BIN, then build/ripwire). Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/writtenspellingfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "writtenspellingcheck: BIN=$BIN  FIX=$FIX"

# bind SUB SPEC WANT [NOT...]: --callees=SPEC on FIX/SUB exits 0, names helper WANT, and names none of NOT
bind(){
    local sub="$1" spec="$2" want="$3"; shift 3
    local out rc bad=""
    out="$( cd "$FIX/$sub" && "$BIN" "$FIX/$sub" --no-cache --callees="$spec" 2>&1 )"; rc=$?
    for n in "$@"; do printf '%s' "$out" | grep -q "n=\"$n\"" && bad="$bad $n"; done
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "n=\"$want\"" && [ -z "$bad" ]; then
        ok "bind   $sub $spec -> $want"
    else
        no "bind   $sub $spec (rc=$rc, want $want, wrong:$bad)"; printf '%s\n' "$out" | tail -c 400; echo
    fi
}
# refuse SUB SPEC: --callees=SPEC on FIX/SUB exits 1 with found="0" (today's refusal, nothing bound)
refuse(){
    local sub="$1" spec="$2" out rc
    out="$( cd "$FIX/$sub" && "$BIN" "$FIX/$sub" --no-cache --callees="$spec" 2>&1 )"; rc=$?
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'found="0"'; then
        ok "refuse $sub $spec"
    else
        no "refuse $sub $spec bound something (rc=$rc)"; printf '%s\n' "$out" | tail -c 400; echo
    fi
}

echo "-- (1) TS Class.method by containment"
bind   ts 'RuntimeDriver.beginTransaction' tsBeginHelper tsOtherHelper
bind   ts 'RuntimeDriver::commitTransaction' tsCommitHelper
bind   ts 'Other.beginTransaction' tsOtherHelper tsBeginHelper
bind   ts 'src/driver/runtime-driver.ts:RuntimeDriver.beginTransaction' tsBeginHelper
refuse ts 'src/other.ts:RuntimeDriver.beginTransaction'
refuse ts 'DupAction.run'                      # two same-named classes: not one entity
refuse ts 'AliasDriver.beginTransaction'       # a value alias is not an owner
refuse ts 'Missing.beginTransaction'
refuse ts 'driver.RuntimeDriver.inner'         # no such member

echo "-- (1b) a JS/TS private member as the rows print it, Owner.#name (lane D2, readout-40 G; RED on train-40 1318069a: every bind arm rc=1)"
bind   ts 'RuntimeDriver.#dispatch' tsPrivHelper tsOtherPrivHelper
bind   ts 'Other.#dispatch' tsOtherPrivHelper tsPrivHelper
bind   ts 'src/driver/runtime-driver.ts:RuntimeDriver.#dispatch' tsPrivHelper tsOtherPrivHelper
bind   ts '#dispatch' tsPrivHelper                 # the bare name: both, as before (a union)
bind   ts '#dispatch' tsOtherPrivHelper            # ... and the other one too: a union names BOTH definitions' callees (CR 4408459940)
refuse ts 'Missing.#dispatch'                     # no owner of that name
refuse ts 'RuntimeDriver.#nope'                   # no such private member
refuse ts 'RuntimeDriver.dispatch'                # the '#' is part of the name: the unprefixed spelling names nothing
refuse ts 'src/other.ts:RuntimeDriver.#dispatch'  # the owner is not in that file

echo "-- (2) module / crate / package prefixes"
bind   py 'asyncio.run' py_asyncio_run_helper py_runner_method_helper py_app_run_helper
bind   py 'json.dump' py_json_dump_helper py_app_dump_helper
bind   py 'asyncio.Runner.run' py_runner_method_helper py_asyncio_run_helper
refuse py 'pickle.dump'                        # stdlib namesake: no path names the module, in-tree dump not bound
refuse py 'asyncio.dump'
refuse py 'self.run'                           # no owner, no module: never a bare-name pick
bind   go 'batcheval.Put' goPutHelper goOtherPutHelper
bind   go 'batcheval.Cmd.Eval' goEvalHelper
bind   go 'other.Put' goOtherPutHelper goPutHelper
refuse go 'be.Put'                             # an import alias names no directory
refuse go 'other.Cmd.Eval'                     # namesake owner absent from that package
bind   rs 'my_crate::Buffer::edit' rs_my_edit_helper rs_other_edit_helper
bind   rs 'othercrate::buf::Buffer::edit' rs_other_edit_helper rs_my_edit_helper
refuse rs 'crate::buf::Buffer::edit'           # both crates satisfy the prefix: not one entity
refuse rs 'language::Buffer::edit'
refuse rs 'my_crate::Alias::edit'              # a type alias is not peeled
refuse rs 'Buf::grow'                          # a CamelCase segment is a type, never the module buf.rs (no owner-less bind)
bind   rs 'my_crate::buf::grow' rs_free_grow_helper

echo "-- (3) C++ written qualifier + enclosing namespaces"
bind   cpp 'ConnectionManagerImpl::ActiveStream::decodeHeaders' cppStreamHelper cppRouterHelper cppUpstreamHelper
bind   cpp 'Envoy::Http::ConnectionManagerImpl::ActiveStream::decodeHeaders' cppStreamHelper cppRouterHelper
bind   cpp 'Router::Filter::decodeHeaders' cppRouterHelper cppUpstreamHelper cppStreamHelper
bind   cpp 'Upstream::Filter::decodeHeaders' cppUpstreamHelper cppRouterHelper
bind   cpp 'HttpConnectionManager::Utility::createSingletons' cppSingletonHelper
refuse cpp 'Http::Filter::decodeHeaders'       # namesake owner in another namespace
refuse cpp 'Router::ActiveStream::decodeHeaders'
refuse cpp 'Other::Utility::createSingletons'

echo "-- siblings: Ruby, and spellings earlier tiers own (unchanged)"
bind   rb 'Shop::Cart#total' rb_cart_total_helper
refuse rb 'Shopx::Cart#total'                 # a module no path names
bind   rb 'Cart#total' rb_cart_total_helper
bind   go 'Cmd.Eval' goEvalHelper
bind   cpp 'ActiveStream::decodeHeaders' cppStreamHelper cppRouterHelper

echo "-- review rv-qn-input: a spelling never binds a def it does not name"
refuse go 'batcheval.PutSub'                   # Go has no re-export: a sub-package's func is not batcheval's
refuse go 'r.PutSub'                           # a Go file stem is not a namespace
bind   go 'sub.PutSub' goSubPutHelper
refuse py 'nest.nested_fn'                     # a local def is not a module attribute
refuse ts 'Nest.localFn'                       # a function local to a method is not a member
refuse ts 'Nest.litFn'                         # an object literal returned by a method is not the class
refuse ts 'objlit.actFn'                       # an object-literal member is not a module export
refuse rs 'my_crate::buf::local_fn'            # a fn local to another fn is not a module item
refuse cpp 'Envoy::Stats::Sink::flush'         # the real def's chain is unreadable: unknown, never the namesake
refuse cpp 'Stats::Sink::flush'
refuse cpp 'Net::Pool::drain'                  # the prefix is the chain's contiguous tail
bind   cpp 'Conn::Pool::drain' cppDrainHelper
bind   py 'Dup.run' py_dup_a_helper            # KEEP: an earlier tier's union stays (skip-the-guard mutant turns this red)

echo "-- review rv-qn-input-delta (C5): a file stem is not a namespace where a file is never one (Swift, Kotlin, Java)"
refuse swift 'Foo.bar'                          # the extension member is owner-less in the index; Foo.swift's top-level bar is not Foo.bar
bind   swift 'Kls.go' swGoHelper
refuse kt 'Reg.top'                             # a Kotlin top-level fun in Reg.kt is not Reg.top
refuse java 'Outer.Loose.m'                     # a second top-level class in Outer.java is com.x.Loose, never Outer.Loose
bind   java 'com.x.Outer.Inner.m' javaInnerHelper

echo "-- review rv-qn-input-delta (C6): a declaration never joins a body on another owner chain"
refuse cpp 'Http::Codec::h'                     # Core's decl + Ext's body: two owner chains, not one entity
bind   cpp 'Ext::Http::Codec::h' cppCodecWrongHelper

echo "-- review rv-qn-input-delta (D2): a TS namespace member or object-literal member is unplaced, so a stem namesake never binds"
refuse tsns 'Zone.f'                            # f lives in `namespace Zone` (holder.ts); Zone.ts's f is not it
refuse tsns 'NSX.Inner.act'                     # Inner is inside `namespace NSX` (a.ts); NSX.ts's Inner is not it
refuse tsns 'Api.run'                           # run is an object-literal member (obj.ts); Api.ts's run is not it
bind   tsns 'Fine.fine' tsnsFineHelper tsnsWrongHelper
bind   tsns 'Svc.serve' tsnsSvcHelper tsnsOtherHelper    # an owner-hit still binds beside an object-literal and a namespace `serve` the spelling does not name

echo "-- cr-prepass-37b: an anonymous-namespace candidate is a spelling's namesake, so a plain namesake never binds alone"
refuse cpp 'Anon::Box::put'                     # plain.cc's Anon::Box::put beside hidden.cc's Anon::(anonymous)::Box::put: a spelling that skips the unnamed namespace names both (a namespace-scope free function is the scope tier's, not this one's)
bind   cpp 'Plain::Pad::put' cppSoloHelper      # KEEP: no anonymous namesake of Plain::Pad, the chain tail still binds
refuse cpp 'Solo::Pad::put'                     # the only Solo::Pad is in an unnamed namespace: refused, as an unreadable chain is

echo "-- round trip: every member row --callees prints binds back to the same definition"
# cr-harvest-444 (CR 4383991762): a failed enumeration or --callers run, or a sub with no seeds, is a FAIL, never a silent PASS
for sub in ts py go rs cpp rb; do
    rows="$( cd "$FIX/$sub" && "$BIN" "$FIX/$sub" --no-cache 2>/dev/null )"; rc=$?
    if [ "$rc" -ne 0 ]; then no "round trip $sub enumeration failed (rc=$rc)"; continue; fi
    seeds="$( printf '%s\n' "$rows" | grep -oE '<s t="(method|fn)" n="[^"]+"( sc="[^"]+")?' | sed -E 's/.* n="([^"]+)"( sc="([^"]+)")?/\3::\1/; s/^:://' | sort -u )"
    if [ -z "$seeds" ]; then no "round trip $sub enumerated no member rows"; continue; fi
    while IFS= read -r seed; do
        got="$( cd "$FIX/$sub" && "$BIN" "$FIX/$sub" --no-cache --callers="$seed" 2>&1 )"; rc=$?
        if [ "$rc" -ne 0 ]; then no "round trip $sub $seed failed (rc=$rc)"
        elif printf '%s' "$got" | grep -q 'found="0"'; then no "round trip $sub $seed refused"; fi
    done <<< "$seeds"
done
[ "$fail" -eq 0 ] && ok "round trip: every printed sc::n / n resolves again (none refused)"

[ "$fail" -eq 0 ] && echo "writtenspellingcheck: PASS" || echo "writtenspellingcheck: FAIL"
exit "$fail"
