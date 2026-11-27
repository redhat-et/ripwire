#!/usr/bin/env bash
# failuredefaultcheck.sh — QD-FAILURE-DEFAULT: error-masking's facet="failure-default" (src/handlershape.h), a read,
# parse or spawn failure returned as an empty success. Report-only in every language, so every row it adds is
# sev="minor" and the delta exits 0.
#   positive  the aislop audit-js-parser.ts shape (JSON.parse in a try, `catch { return []; }`, Advisory[] result),
#             its promise form, a two-hop same-file parse helper, and the #614 C++ shape
#             (`readWholeFile( … ).value_or( std::string() )` in a function returning a struct) each print one row;
#   negative  the same TS handler in a function returning `Advisory[] | null`, a commented `catch { return false; }`
#             around fs.lstatSync, a handler that logs, a try with no read, ripwire's own
#             `if( !bytes ) { DISCLOSE(…) } … value_or( std::string() )`, a commented value_or line, an optional
#             result, a value_or whose next statement asks `.empty()`, and a local read by `has_value()` first print none. Each negative arm counts the
#             handlers or value_or sites it judged (premise) and FAILS on 0, so a parse that saw nothing is not a pass.
#   gating    (G) a failure-default catch made empty gates though the total count is unchanged; (A) an ack of the
#             report-only row does not hide that gating row (QD-ACK-GATING-SPLIT, CodeRabbit 4577036262 on #662).
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # absolutize BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  failuredefaultcheck (git not available)"; exit 0; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "failuredefaultcheck: BIN=$BIN  (temp corpora)"

qd_pair(){   # DIR FILE BASELINE EDIT → QD_OUT (the delta document) and QD_RC (its exit code)
    local d="$WORK/$1"
    mkdir -p "$d"
    ( cd "$d" && git init -q && git config user.email t@t && git config user.name t )
    printf '%s' "$3" > "$d/$2"
    ( cd "$d" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
    printf '%s' "$4" > "$d/$2"
    cmp -s <( printf '%s' "$3" ) "$d/$2" && no "$1: the edit did not take (fixture identical to its baseline)"
    QD_OUT="$( cd "$d" && "$BIN" . --quality-delta --no-cache --legend=full 2>/dev/null )"
    QD_RC=$?
}
qd_row(){ printf '%s' "$QD_OUT" | tr '>' '\n' | grep "<r kind=\"error-masking\" sym=\"$1\""; }   # SYM → the row, or nothing
fd_has(){   # LABEL SYM → PASS when SYM's row carries facet="failure-default", sev="minor" and no gating=
    local row; row="$( qd_row "$2" )"
    if printf '%s' "$row" | grep -q 'facet="failure-default"' && printf '%s' "$row" | grep -q 'sev="minor"' && ! printf '%s' "$row" | grep -q 'gating='; then
        ok "$1: a report-only failure-default row on $2"
    else
        no "$1: want one facet=\"failure-default\" sev=\"minor\" row on $2, got: ${row:-nothing}"; printf '%s\n' "$QD_OUT" | tr '>' '\n' | grep '<r '
    fi
}
fd_none(){  # LABEL SYM WHY
    if [ -z "$( qd_row "$2" )" ]; then ok "$1: no row on $2 ($3)"; else no "$1: a row on $2 is a false positive ($3): $( qd_row "$2" )"; fi
}
premise(){   # LABEL DIR SYM QUERY → FAIL unless the query hits at least once inside SYM
    local out rc n
    out="$( cd "$WORK/$2" && "$BIN" . --match="$4" --no-cache 2>/dev/null )"; rc=$?
    n="$( printf '%s' "$out" | tr '>' '\n' | grep -c "<m p=[^ ]* in=\"$3\"" )"
    if [ "$rc" -ne 0 ]; then no "$1: premise — --match exited $rc in $2"
    elif [ "${n:-0}" -gt 0 ]; then ok "$1: premise — $n site(s) judged in $3"; else no "$1: premise — 0 sites in $3 (the negative arm is vacuous)"; fi
}
exit0(){ if [ "$QD_RC" = 0 ]; then ok "$1: report-only rows exit 0"; else no "$1: want exit 0, got $QD_RC"; fi; }

# 1) TypeScript. The baseline parses with no handler; the edit wraps each body in the shape under test.
TSB='import * as fs from "fs";
interface Advisory { id: string }
const isRecord = ( v: unknown ): v is Record<string, unknown> => typeof v === "object" && v !== null;
export const parseAudit = ( output: string ): Advisory[] => {
	const parsed: unknown = JSON.parse( output );
	return isRecord( parsed ) ? [] : [];
};
export const parseNullable = ( output: string ): Advisory[] | null => {
	const parsed: unknown = JSON.parse( output );
	return isRecord( parsed ) ? [] : [];
};
export function isLink( p: string ): boolean {
	return fs.lstatSync( p ).isSymbolicLink();
}
export function logged( output: string ): Advisory[] {
	return JSON.parse( output ) as Advisory[];
}
export function noRead( xs: number[] ): number[] {
	return xs.map( ( x ) => x * 2 );
}
const loadText = ( p: string ): string => fs.readFileSync( p, "utf-8" );
const parseFile = ( p: string ): Record<string, string> => JSON.parse( loadText( p ) );
export function viaHelper( p: string ): Record<string, string> {
	return parseFile( p );
}
export async function fetchAll( url: string ): Promise<Advisory[]> {
	return ( await fetch( url ) ).json();
}
'
TSE='import * as fs from "fs";
interface Advisory { id: string }
const isRecord = ( v: unknown ): v is Record<string, unknown> => typeof v === "object" && v !== null;
export const parseAudit = ( output: string ): Advisory[] => {
	try {
		const parsed: unknown = JSON.parse( output );
		return isRecord( parsed ) ? [] : [];
	} catch {
		return [];
	}
};
export const parseNullable = ( output: string ): Advisory[] | null => {
	try {
		const parsed: unknown = JSON.parse( output );
		return isRecord( parsed ) ? [] : [];
	} catch {
		return null;
	}
};
export function isLink( p: string ): boolean {
	try {
		return fs.lstatSync( p ).isSymbolicLink();
	} catch {
		// a path that does not exist is not a link
		return false;
	}
}
export function logged( output: string ): Advisory[] {
	try {
		return JSON.parse( output ) as Advisory[];
	} catch ( e ) {
		console.warn( "bad audit output" );
		return [];
	}
}
export function noRead( xs: number[] ): number[] {
	try {
		return xs.map( ( x ) => x * 2 );
	} catch {
		return [];
	}
}
const loadText = ( p: string ): string => fs.readFileSync( p, "utf-8" );
const parseFile = ( p: string ): Record<string, string> => JSON.parse( loadText( p ) );
export function viaHelper( p: string ): Record<string, string> {
	try {
		return parseFile( p );
	} catch {
		return {};
	}
}
export async function fetchAll( url: string ): Promise<Advisory[]> {
	return fetch( url ).then( ( r ) => r.json() ).catch( () => [] );
}
'
qd_pair fd_ts audit.ts "$TSB" "$TSE"
fd_has  "failure-default (ts)" parseAudit
fd_has  "failure-default (ts, two-hop helper)" viaHelper
fd_has  "failure-default (ts, promise .catch)" fetchAll
fd_none "failure-default (ts)" parseNullable "Advisory[] | null carries the failure"
fd_none "failure-default (ts)" isLink        "the handler's comment says why"
fd_none "failure-default (ts)" noRead        "the try reads, parses and spawns nothing"
exit0   "failure-default (ts)"
# logged() gains a log-only handler (its own report-only shape) but no failure-default facet.
printf '%s' "$( qd_row logged )" | grep -q 'facet=' && no "failure-default (ts): logged() has a facet, but its handler logs" || ok "failure-default (ts): no facet on logged() (the handler logs)"
printf '%s' "$QD_OUT" | grep -q 'facet="failure-default" on an error-masking row' \
    && ok "failure-default (ts): the full legend defines facet=" || no "failure-default (ts): the full legend does not define facet="
for s in parseNullable isLink logged noRead; do premise "failure-default (ts)" fd_ts "$s" '(catch_clause) @m'; done

# 1b) A report-only handler made gating (CodeRabbit 4577036262, #662). The ts fixture's loadAll() returns [] from a
#     failure-default catch; the edit empties the catch. (G) baseline WITH that catch: the total count stays 1, the gating
#     count grows 0 -> 1, so a gating row and exit 2 (red before: no row, exit 0). (A) baseline without a handler, the
#     report-only row ACKED, then the catch emptied: the gating row at the same count is not hidden by that ack (red
#     before: suppressed, exit 0); a re-run before the edit stays acked (the ack still covers its own report-only row).
FD_ONE='import * as fs from "fs";
interface Advisory { id: string }
export function loadAll( p: string ): Advisory[] {
	try {
		return JSON.parse( fs.readFileSync( p, "utf-8" ) ) as Advisory[];
	} catch {
		return [];
	}
}
'
FD_EMPTY='import * as fs from "fs";
interface Advisory { id: string }
export function loadAll( p: string ): Advisory[] {
	try {
		return JSON.parse( fs.readFileSync( p, "utf-8" ) ) as Advisory[];
	} catch {
	}
	return [];
}
'
FD_NONE='import * as fs from "fs";
interface Advisory { id: string }
export function loadAll( p: string ): Advisory[] {
	return JSON.parse( fs.readFileSync( p, "utf-8" ) ) as Advisory[];
}
'
gating_row(){ local row; row="$( qd_row loadAll )"; [ -n "$row" ] && ! printf '%s' "$row" | grep -q 'sev="minor"' && [ "$QD_RC" = 2 ]; }
qd_pair fd_gate load.ts "$FD_ONE" "$FD_EMPTY"
if gating_row; then ok "(G) failure-default -> empty catch: a gating row at the same total, exit 2"; else no "(G) want a gating loadAll row and exit 2, got rc $QD_RC: $( qd_row loadAll )"; fi
qd_pair fd_ack load.ts "$FD_NONE" "$FD_ONE"
fd_has "(A) premise" loadAll
( cd "$WORK/fd_ack" && "$BIN" . --quality-delta --no-cache --quality-ack="report-only failure-default accepted" >/dev/null 2>&1 ) || no "(A) --quality-ack exited $?"
if grep -q '^ack error-masking:report-only ' "$WORK/fd_ack/.ripwire_quality_acks" 2>/dev/null; then ok "(A) the report-only row was acked as error-masking:report-only"; else no "(A) no error-masking:report-only row in the ledger: $( grep error-masking "$WORK/fd_ack/.ripwire_quality_acks" 2>/dev/null | cut -c1-60 )"; fi
QD_OUT="$( cd "$WORK/fd_ack" && "$BIN" . --quality-delta --no-cache --legend=full 2>/dev/null )"; QD_RC=$?
if [ -z "$( qd_row loadAll )" ] && [ "$QD_RC" = 0 ]; then ok "(A) the ack suppresses its own report-only row"; else no "(A) after the ack: rc $QD_RC, row: $( qd_row loadAll )"; fi
printf '%s' "$FD_EMPTY" > "$WORK/fd_ack/load.ts"
QD_OUT="$( cd "$WORK/fd_ack" && "$BIN" . --quality-delta --no-cache --legend=full 2>/dev/null )"; QD_RC=$?
if gating_row; then ok "(A) a report-only ack does not hide the gating row at the same count (exit 2)"; else no "(A) the report-only ack hid the gating row (rc $QD_RC): $( qd_row loadAll )"; fi

# 2) C++: the #614 shape, and ripwire's own refused house pattern.
CXB='#include <optional>
#include <string>
struct SpecEntry { int kind = 0; };
std::optional<std::string> readWholeFile( const std::string& path );
void disclose( const char* why );
SpecEntry resolveSpec( const std::string& path )
{
    SpecEntry out;
    std::string text = path;
    out.kind = text.find( "pkg" ) == std::string::npos ? 0 : 1;
    return out;
}
SpecEntry guardedSpec( const std::string& path )
{
    SpecEntry out;
    std::string text = path;
    out.kind = text.find( "pkg" ) == std::string::npos ? 0 : 1;
    return out;
}
SpecEntry flooredSpec( const std::string& path )
{
    SpecEntry out;
    std::string text = path;
    out.kind = text.find( "pkg" ) == std::string::npos ? 0 : 1;
    return out;
}
std::optional<std::string> carriedSpec( const std::string& path )
{
    return path;
}
int lineCount( const std::string& path )
{
    return static_cast<int>( path.size() );
}
bool hasMarker( const std::string& path, bool& failed )
{
    failed = path.empty();
    return path.rfind( "#!" ) == 0;
}
'
CXE='#include <optional>
#include <string>
struct SpecEntry { int kind = 0; };
std::optional<std::string> readWholeFile( const std::string& path );
void disclose( const char* why );
SpecEntry resolveSpec( const std::string& path )
{
    SpecEntry out;
    std::string text = readWholeFile( path ).value_or( std::string() );
    out.kind = text.find( "pkg" ) == std::string::npos ? 0 : 1;
    return out;
}
SpecEntry guardedSpec( const std::string& path )
{
    SpecEntry out;
    std::optional<std::string> bytes = readWholeFile( path );
    if( !bytes )
    {
        disclose( "unreadable" );
    }
    std::string text = std::move( bytes ).value_or( std::string() );
    out.kind = text.find( "pkg" ) == std::string::npos ? 0 : 1;
    return out;
}
SpecEntry flooredSpec( const std::string& path )
{
    SpecEntry out;
    std::string text = readWholeFile( path ).value_or( std::string() );   // unreadable => no evidence, never a guess
    out.kind = text.find( "pkg" ) == std::string::npos ? 0 : 1;
    return out;
}
std::optional<std::string> carriedSpec( const std::string& path )
{
    return readWholeFile( path ).value_or( std::string() );
}
int lineCount( const std::string& path )
{
    const std::string text = readWholeFile( path ).value_or( std::string() );
    if( text.empty() )
    {
        return -1;
    }
    int lines = 0;
    for( char c : text ) { lines += c == 10 ? 1 : 0; }
    return lines;
}
bool hasMarker( const std::string& path, bool& failed )
{
    std::optional<std::string> bytes = readWholeFile( path );
    failed = !bytes.has_value();
    return std::move( bytes ).value_or( std::string() ).rfind( "#!" ) == 0;
}
'
qd_pair fd_cxx spec.cpp "$CXB" "$CXE"
fd_has  "failure-default (c++, the #614 shape)" resolveSpec
fd_none "failure-default (c++)" guardedSpec "an if tests the read before the value_or"
fd_none "failure-default (c++)" flooredSpec "the line's comment documents the floor"
fd_none "failure-default (c++)" carriedSpec "an optional result carries the failure"
fd_none "failure-default (c++)" lineCount "the next statement tests the empty text"
fd_none "failure-default (c++)" hasMarker "the optional is read (has_value) before the value_or"
exit0   "failure-default (c++)"
for s in guardedSpec flooredSpec carriedSpec lineCount hasMarker; do premise "failure-default (c++)" fd_cxx "$s" '((field_identifier) @m (#eq? @m "value_or"))'; done

# 3) Determinism and well-formedness of the delta that carries the facet.
AGAIN="$( cd "$WORK/fd_cxx" && "$BIN" . --quality-delta --no-cache --legend=full 2>/dev/null )"; AGAIN_RC=$?
if [ "$AGAIN_RC" = "$QD_RC" ] && [ "$QD_OUT" = "$AGAIN" ]; then
    ok "failure-default: byte-identical run-to-run (rc $AGAIN_RC)"
else
    no "failure-default: non-deterministic (rc $QD_RC then $AGAIN_RC)"
fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$QD_OUT" | xmllint --noout - 2>/dev/null; then ok "failure-default: xml well-formed"; else no "failure-default: xml malformed"; fi
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
