#!/usr/bin/env bash
# rubyschemacheck.sh — parser version 122 gate: RUBY db/schema.rb COLUMNS ARE Section DEFS. The Rails
# schema capture: a Ruby file whose tree holds a `create_table "x", … do |t| … end` call is a rendered
# schema BY CONTENT (no path heuristic), and each `t.<type> "name"` / `t.<type> :name` receiver-call in
# the table block mints ONE SymKind::Section def at Lang::Ruby — the same data-kind slot as a doc
# heading / YAML key (model.h) — with span = the name token. Rails-generated attribute uses
# (`product.price`, pinned here as explicit-receiver model calls) then bind to the column def set and
# reach the call graph and PageRank: the "admission consequence" the PR body discloses. The DSL CALLS
# keep their reference posture exactly like the attr family (--uses=string/define/timestamps stay
# defs=0 external=1). The four id spellings and t.timestamps name columns too, per the rules below.
#
# Fixture test/rubyschemafix — schema text from a real, running Rails 8.1 app's `bin/rails
# db:schema:dump` (verified db:schema:load-able), with the original domain tables scrubbed to spike_*
# names; two spellings no dump ever emits are restored BY HAND and marked in-file: `id: :uuid` (the
# dump itself notes "Could not dump … Unknown type 'uuid'") and a literal `t.timestamps` (rendered
# schemas expand it to t.datetime pairs) — runtime-semantics and shape notes in USECASES.md beside the
# fixture.
#   name            the 9 `t.string "name"` columns (→ defs=19 with the 9 attr/def defs + the yaml key)
#   id              the multi-def floor: EVERY table carries its key — 14 (12 implicit + id: :uuid + …)
#   event_id        `primary_key: "event_id"` renames the key off `id`
#   ref             `id: false` table's only column; NO id def there
#   created_at/updated_at  both the rendered t.datetime pair AND the literal t.timestamps call
#   quote_symbol    t.string :name + t.references :owner (floor) + t.index ["name"] (floor) +
#                   helper.string "unbound_column" — a column call on a DIFFERENT bare identifier
#                   names nothing (the receiver must be the block parameter, `t`)
#   migration_string/migration_symbol/migration_columns  the migration INTERFERENCE floors: a
#     class-wrapped create_table (string- OR symbol-named) mints NOTHING — the schema is the only
#     source of column names, indexing a migration beside its schema would double every def and its
#     PageRank weight — and add_column/remove_column are argument data, never defs (a column added
#     then dropped never registers)
#   floor_case      where("name = ?") — a string fragment stays opaque, never a def or a use
#   all_four / pair_def_column / triple_*  the def+attr+column(+yaml) collision matrix; the picker
#     styles: `self.name` inside PairDefColumn pins its own def (locality), `rec.name` on a local and
#     `SingleColumn.new.name` on a rich receiver split over the whole def set (graph_ambiguous)
#   config/spike_names.yml  the cross-language name key (counted, never edgeable)
#
# Usage:  test/rubyschemacheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyschemacheck.sh
# Exit:   0 = clean · 1 = an arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/rubyschemafix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/rubyschemafix — fixture missing"; exit 2; }
echo "rubyschemacheck: BIN=$BIN  FIX=$FIX"

useshead(){ "$BIN" "$FIX" --uses="$1" --no-cache 2>/dev/null | grep -oE "of=\"[^\"]*\" defs=\"[0-9]+\" external=\"[0-9]+\" count=\"[0-9]+\"" | head -1; }
undefinable(){ "$BIN" "$FIX" --uses="$1" --no-cache 2>&1 | grep -q "matched no indexed definition"; }
callershead(){ "$BIN" "$FIX" --callers="$1" --no-cache 2>/dev/null | grep -oE "of=\"[^\"]*\" defs=\"[0-9]+\" count=\"[0-9]+\"" | head -1; }

# ── 1. CAPTURE: columns are Section defs; the id rule; the timestamps pair ──────────────────────────
[ "$( useshead name )"        = 'of="name" defs="19" external="0" count="3"' ] \
    && ok 'capture: name — 9 columns + 9 attr/def defs + 1 yaml key = 19; only the 3 consumers use it (the where() fragment is opaque)' \
    || no "capture: name: $( useshead name )"
[ "$( useshead id )"          = 'of="id" defs="14" external="0" count="1"' ] \
    && ok 'capture: id — the multi-def floor: 12 implicit + the id: :uuid pair + the id-pair… 14 keys on 14 tables (only id_false and the renamed table have none)' \
    || no "capture: id: $( useshead id )"
[ "$( useshead event_id )"    = 'of="event_id" defs="1" external="0" count="0"' ] \
    && ok 'capture: `primary_key: "event_id"` mints the renamed key def, and NO implicit id beside it' \
    || no "capture: event_id: $( useshead event_id )"
[ "$( useshead ref )"         = 'of="ref" defs="1" external="0" count="0"' ] \
    && ok 'capture: the `id: false` table'"'"'s own column mints; the table has NO id def' \
    || no "capture: ref: $( useshead ref )"
[ "$( useshead created_at )"  = 'of="created_at" defs="2" external="0" count="1"' ] \
    && ok 'capture: created_at — the rendered t.datetime column AND the literal t.timestamps call each mint one; the consumer call reaches them' \
    || no "capture: created_at: $( useshead created_at )"
[ "$( useshead updated_at )"  = 'of="updated_at" defs="2" external="0" count="0"' ] \
    && ok 'capture: updated_at — both spellings def; no consumer calls it (floor proof the count is per-row, not padded)' \
    || no "capture: updated_at: $( useshead updated_at )"

# ── 2. FLOORS: the DSL calls stay references; non-column DSL names no column ───────────────────────
undefinable owner \
    && ok 'floor: t.references :owner names no column — owner stays undefinable (references is the reference, its arg is data)' \
    || no 'floor: owner — t.references minted a def'
[ "$( useshead index )" = 'of="index" defs="0" external="1" count="1"' ] \
    && ok 'floor: t.index ["name"] — the CALL is an external reference (DSL posture), the array arg defines nothing' \
    || no "floor: index: $( useshead index )"
undefinable email \
    && ok 'migration: a CLASS-wrapped string-named create_table ("spike_migrated") mints nothing — the same columns the migration created are already minted from the rendered schema; indexing both would DOUBLE the defs+PageRank' \
    || no 'migration: email — a class-wrapped (string-named) migration table minted a def'
undefinable widget_name \
    && ok 'migration: a symbol-named migration table (create_table :spike_widgets) mints nothing — both the class-nest and the string-name gates refuse' \
    || no 'migration: widget_name — a symbol-named migration table minted a def'
undefinable bla \
    && ok 'migration: add_column "bla" is argument data — the DSL call is a reference, its args are not defs (only the schema is the source of names)' \
    || no 'migration: bla — add_column minted a def'
undefinable gonna_die \
    && ok 'migration: a column added then REMOVED never registers (remove_column is read nowhere)' \
    || no 'migration: gonna_die — a removed column minted a def'
undefinable unbound_column \
    && ok 'receiver: a column call on a DIFFERENT bare identifier (`helper.string "unbound_column"`) names no column — the receiver must BE the block parameter (`t`) the create_table call bound' \
    || no 'receiver: unbound_column — a non-t receiver minted a def'
for dsl in string define datetime timestamps create_table; do
    [ "$( useshead "$dsl" | grep -oE 'defs="[0-9]+" external="[0-9]+"' )" = 'defs="0" external="1"' ] \
        && ok "posture: the DSL call \`$dsl\` itself is still no def (reference capture posture)" \
        || no "posture: $dsl gained a def — the DSL call must stay a reference: $( useshead "$dsl" )"
done

# ── 3. BINDING: model call sites reach the column def set (the admission consequence) ───────────────
[ "$( callershead name )"       = 'of="name" defs="19" count="3"' ] \
    && ok 'bind: the 3 name call sites reach the 19-def set — columns admit call edges (the Lang::Ruby admission)' \
    || no "bind: name callers: $( callershead name )"
[ "$( callershead id )"         = 'of="id" defs="14" count="1"' ] \
    && ok 'bind: `IdDefault.new.id` sits on the 14-table implicit-id def set' \
    || no "bind: id callers: $( callershead id )"
[ "$( callershead created_at )" = 'of="created_at" defs="2" count="1"' ] \
    && ok 'bind: `Timestamps.new.created_at` reaches BOTH created_at defs (rendered column + literal call)' \
    || no "bind: created_at callers: $( callershead created_at )"

# ── 4. AMBIGUITY + LOCALITY: the resolver splits honestly, pins on evidence ─────────────────────────
"$BIN" "$FIX" --uses=name --no-cache 2>/dev/null >"$TMP/uses_name"
grep -q 'of="name" defs="19" external="0" count="3"' "$TMP/uses_name" \
    && grep -q 'graph_ambiguous="4"' "$TMP/uses_name" \
    && ok 'ambiguity: the name graph_ambiguous gauge counts exactly the 4 splitting sites (rich/new/rec receivers + id + created_at), never a silent pin' \
    || no 'ambiguity: name gauge/rows wrong'
grep -q 'p="consumer_ambiguous.rb:8"' "$TMP/uses_name" \
    && ok 'ambiguous arm: rec.name on a plain local SPLITS over the whole def set (its row is in the gauge)' \
    || no 'ambiguous arm: consumer_ambiguous.rb:8 row missing'
grep -q 'p="pair_def_column.rb:15"' "$TMP/uses_name" \
    && ok 'locality arm: self.name inside PairDefColumn pins the in-class def — its row exists and is NOT in the ambiguous gauge' \
    || no 'locality arm: pair_def_column.rb:15 row missing'
grep -q 'p="column_consumers.rb:6"' "$TMP/uses_name" \
    && ok 'binding arm: SingleColumn.new.name is a real use row (explicit model receiver)' \
    || no 'binding arm: column_consumers.rb:6 row missing'

# ── 5. MAP KINDS: the defs carry t="sec" with the DSL row family merged by name ─────────────────────
"$BIN" "$FIX" --no-cache 2>/dev/null >"$TMP/map"
# The schema.rb file block, extracted once; every kind arm asserts INSIDE it (the yaml Section key is a
# different file and must never satisfy a schema assertion).
python3 - "$TMP/map" >"$TMP/schema_block" <<'PYEOF'
import re, sys
xml = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'<f p="schema\.rb"[^>]*>(.*?)</f>', xml, re.S)
sys.stdout.write(m.group(1) if m else "")
PYEOF
grep -q '<s t="sec" n="name"' "$TMP/schema_block" \
    && ok 'kind: schema.rb holds a t="sec" n="name" row (the 9 columns; the yaml Section key is a different file and cannot satisfy this arm)' \
    || no 'kind: schema.rb name section row missing'
grep -q '<s t="sec" n="name" overloads="9"' "$TMP/schema_block" \
    && ok 'kind: the 9 schema name defs are one overloads="9" row — every column counts, none hidden' \
    || no 'kind: schema.rb name overloads != 9'
grep -q '<s t="sec" n="id"' "$TMP/schema_block" \
    && ok 'kind: the 14 keys merge as one t="sec" n="id" row — the multi-def floor is visible, not hidden' \
    || no 'kind: schema.rb id section row missing'
grep -q '<s t="sec" n="event_id"' "$TMP/schema_block" \
    && ok 'kind: the primary_key rename def is a Section row too' \
    || no 'kind: event_id section row missing'
grep -q '<s t="method" n="name" sc="PairDefColumn"' "$TMP/map" && grep -q '<s t="sec" n="name"' "$TMP/schema_block" \
    && ok 'collision: the method def and the column def share the NAME, never the identity — both stand' \
    || no 'collision: method/column name defs lost one side'

# ── 6. determinism, warm == cold, well-formed XML ───────────────────────────────────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/m1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/m2" 2>/dev/null
if cmp -s "$TMP/m1" "$TMP/m2"; then ok "deterministic (two --no-cache runs byte-identical)"; else no "non-deterministic"; fi
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
if cmp -s "$TMP/cold" "$TMP/warm"; then ok "warm == cold (schema defs survive the cache round-trip)"; else no "warm != cold"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/m1" 2>/dev/null; then ok "xml well-formed"; else no "xml malformed"; fi
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }