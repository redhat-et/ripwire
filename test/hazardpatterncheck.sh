#!/usr/bin/env bash
# hazardpatterncheck.sh — could today's crashes have been caught before they shipped? Five hazard shapes that
# are visible in source, each a STATIC rule run with ripwire's own structural query (--match) over src/. The behaviour
# each fix changes is proven in the verb's own gate: cachefuzzcheck.sh Part 3 (rule D), withprofilecheck.sh arm 8
# (rule C's atoi), skillevalcheck.sh / codexwrapcheck.sh on lane/crash-fixes-parsers (rule C's filesystem throws).
#
# SCOPE, and what it leaves to other gates. crashsweepcheck.sh owns three shapes (S1 an allocation sized by a
# decoded count, S2 fopen/open/fdopen/openat/opendir/open_memstream/popen accounted for, S3 thread bodies that do
# not throw); cachefuzzcheck.sh owns the mutated-blob behaviour; regexbombcheck/regexguardcheck own user regex.
# This gate holds the classes nobody else does:
#
#   (A) AN ENUM BUILT FROM A BYTE READER. `SymKind( r.u8() )`, `static_cast<E>( r.u8() )`, a C-style cast, or a
#       cast of a local assigned from a reader call earlier in the same function. An enum with a fixed underlying
#       type holds any byte, so nothing fails at the cast; the damage is downstream (#241: a stack write past
#       search.h's tier array, a shift by 255 in clones.h). The spelling that validates is ByteR::enumU8<E>( count ).
#       Enum names are DERIVED from every enum_specifier under src/, not listed here.
#   (B) EXCEPTIONS. (B1) every catch handler is read; one that records nothing — no assignment, no stored flag,
#       no returned value, no emitted line — is a swallow, and one whose only statement is DISCLOSE is
#       a swallow in every Release binary (NDEBUG empties the macro). crashsweepcheck's S3 already requires every
#       thread body to be noexcept or one try block; B reads the handlers themselves, wherever they are. Each must be registered with why the dropped
#       work does not change an answer, or with the finding it is. (B2) every `throw` in src/: one with no `try`
#       around it in its own function leaves the function, and must be registered as a permitted seam.
#   (C) A THROWING STANDARD CALL WHERE NOTHING MAY THROW. std::sto*, .at( ), optional .value( ), the atoi family
#       (undefined on overflow), a std::filesystem call without its std::error_code overload, a directory_entry
#       query without one, a directory_iterator constructed without one, and a range-for over a directory
#       iterator (its operator++ throws filesystem_error; only increment( ec ) does not). Registered with why the
#       input cannot make it throw, or the site is replaced by the non-throwing spelling.
#       Red on the base: 6 sites. skilleval.h's discoverSkills (3) and wrap.h's skill scan (1) are the `--eval-skills`
#       and `ripwire wrap` aborts (exit 134 on a skills tree holding an unreadable skill, reproduced) that
#       lane/crash-fixes-parsers fixes, so they are PENDING rows here until it lands; planlint.h's
#       std::filesystem::absolute fallback now takes an error_code; verbs_lint.h's std::atoi read a --with-profile
#       line of 2^32+33 as 33 and joined a finding to a site that is not there (withprofilecheck.sh arm 8).
#   (D) A DECODED VALUE NARROWED WITHOUT A CHECK. `std::uint16_t( r.u32() )`: a cast to a narrower integer of a
#       reader call (or a local assigned from one, with no comparison on it in between). The writer never stores a
#       value the field cannot hold, so one that does not fit is corruption, refused by ByteR::u16Of32( ) (fitsBelow is a bound). Red on
#       the base: readDef's five u16 fields and readRef's argCount.
#   (E) RAW ACQUISITIONS crashsweepcheck's S2 does not name: descriptors (socket, ::accept, pipe, dup, kqueue …),
#       heap (malloc family, a non-placement `new`), and tree-sitter handles (ts_parser_new, ts_query_new,
#       ts_query_cursor_new, ts_parser_parse*, ts_tree_copy, ts_tree_cursor_new). A call made inside a type whose
#       destructor releases it (the ParserGuard / ChildCursor shape) is owned and needs no row; every other site is
#       in the registry below with the fact that releases it. A new site fails: give it an RAII owner, or register it.
#
# REGISTRIES. Every row is (file, function, key, count, reason). The src/ verdict is EXACT: a site the registry
# does not hold fails, a count that moved fails, and a row that matches no site fails — the list cannot rot into
# permission for code that is gone. Rows tagged FINDING are real defects in files other lanes hold; they are
# listed so the gate is green on the tree as it is, and each names what fixes it. A row whose reason starts with
# PENDING names a fix already written on another branch: it may match no site (the fix landed) and then prints a
# NOTE asking for its deletion instead of failing, so the two lanes can land in either order.
#
# NON-VACUITY. The rules run twice: over src/ (the verdict) and over a synthetic probe tree holding one violation
# and one compliant twin per rule, where every violation must fire and no twin may. A scan that reached the
# engine's hit cap, or a binary that answered nothing, FAILS as partial — never reads as a clean tree. The src/
# scan must also have examined a population large enough to be real (see "reached the source").
#
# CATCHES the shapes above as they are spelled. MISSES a reader primitive not in the list (the list is in the
# scan), a derivation deeper than one assignment, a swallow disguised as a recording statement that records
# nothing an answer reads, a throwing call through a helper, `.substr( pos )` past the end (727 call sites — the
# reader fuzzers in test/fuzz/ are the check for that one), and an owner type whose destructor is in another file.
#
# Usage:  bash test/hazardpatterncheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
SRC="${RIPWIRE_HAZARD_SRC:-$ROOT/src}"   # the tree the static rules read; a red-first run points it at a base checkout
TMP="$( mktemp -d )"; trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
note(){ printf '  NOTE  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "hazardpatterncheck: BIN=$BIN  SRC=$SRC"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== static rules A-E (ripwire --match over the source) ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
cat > "$TMP/scan.py" <<'SCANPY'
# hazardpatterncheck static scan driver: python3 hazscan.py BIN SRC OUT
# Every rule reads ripwire's own structural query (--match) over SRC, then re-reads the source text around each hit
# with comments and string literals blanked. Output: one TSV per rule under OUT; the gate judges them.
import html, os, re, subprocess, sys
from collections import Counter, defaultdict

BIN, SRC, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(OUT, exist_ok=True)
queriesRun = 0


def match(query):
    """One --match over SRC -> [(file, line, fn, text)]. A partial or failed scan exits 3, never an empty list."""
    global queriesRun
    proc = subprocess.run([BIN, SRC, "--match=" + query, "--limit=5000"], capture_output=True, text=True)
    root = re.search(r"<match [^>]*>", proc.stdout)
    if proc.returncode != 0 or root is None:
        print("SCANFAIL rc=%d query=%s stderr=%s" % (proc.returncode, query[:100], proc.stderr[:300]))
        sys.exit(3)
    if 'hits_capped="1"' in root.group(0) or 'capped="1"' in root.group(0):
        print("SCANFAIL the scan is partial (a cap was reached): " + query[:100])
        sys.exit(3)
    queriesRun += 1
    rows = []
    for p, fn, text in re.findall(r'<m p="([^"]*)" in="([^"]*)">(.*?)</m>', proc.stdout, re.S):
        f, _, ln = p.rpartition(":")
        rows.append((f, int(ln), html.unescape(fn), html.unescape(text)))
    return rows


def tuples(rows, n):
    """A query binding n captures yields n rows per match, in capture order; regroup them and refuse a torn stream."""
    if len(rows) % n:
        print("SCANFAIL row count %d is not a multiple of %d captures" % (len(rows), n))
        sys.exit(3)
    out = []
    for i in range(0, len(rows), n):
        grp = rows[i:i + n]
        if len({r[0] for r in grp}) != 1:
            print("SCANFAIL a %d-capture match spans files: %r" % (n, grp))
            sys.exit(3)
        out.append((grp[0][0], grp[0][1], grp[0][2]) + tuple(r[3] for r in grp))
    return out


# ── source text with comments, string and char literals blanked (same length, newlines kept) ─────────────────────
_code = {}


def code_of(f):
    if f in _code:
        return _code[f]
    with open(os.path.join(SRC, f), encoding="utf-8", errors="replace") as fh:
        s = fh.read()
    out = list(s)
    i, n = 0, len(s)

    def blank(a, b):
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        c = s[i]
        if s.startswith("//", i):
            j = s.find("\n", i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
        elif s.startswith("/*", i):
            j = s.find("*/", i + 2)
            j = n if j < 0 else j + 2
            blank(i, j)
            i = j
        elif c == 'R' and i + 1 < n and s[i + 1] == '"' and (i == 0 or not (s[i - 1].isalnum() or s[i - 1] == '_')):
            m = re.match(r'R"([^(\s]{0,16})\(', s[i:])
            if m:
                end = s.find(")" + m.group(1) + '"', i + m.end())
                end = n if end < 0 else end + len(m.group(1)) + 2
                blank(i + 1, end)
                i = end
            else:
                i += 1
        elif c == '"' or (c == "'" and not (i > 0 and s[i - 1].isalnum())):   # 1'000 digit separators are not chars
            j = i + 1
            while j < n and s[j] != c and s[j] != "\n":
                j += 2 if s[j] == "\\" else 1
            blank(i + 1, min(j, n))
            i = j + 1
        else:
            i += 1
    text = "".join(out)
    starts = [0]
    for m in re.finditer("\n", text):
        starts.append(m.end())
    _code[f] = (text, starts)
    return _code[f]


def line_of(f, pos):
    import bisect
    return bisect.bisect_right(code_of(f)[1], pos)


def balanced(text, openPos):
    """Index one past the brace/paren that closes text[openPos]."""
    pairs = {"{": "}", "(": ")", "[": "]"}
    want, depth = pairs[text[openPos]], 0
    for k in range(openPos, len(text)):
        if text[k] == text[openPos]:
            depth += 1
        elif text[k] == want:
            depth -= 1
            if depth == 0:
                return k + 1
    return len(text)


fnStarts = defaultdict(list)
fnDefsRows = match('(function_definition declarator: (function_declarator declarator: (_) @name))')
for f, ln, fn, name in fnDefsRows:
    fnStarts[(f, name.split("::")[-1])].append(ln)


def fn_span(f, fn, ln):
    """(startPos, endPos) of the function body enclosing line ln, or a 200-line window when it cannot be found."""
    text, starts = code_of(f)
    cands = [s for s in fnStarts.get((f, fn.split("::")[-1]), []) if s <= ln]
    if cands:
        pos = starts[max(cands) - 1]
        brace = text.find("{", pos)
        if brace >= 0:
            end = balanced(text, brace)
            if line_of(f, end) >= ln:
                return brace, end
    return starts[max(0, ln - 200)], starts[min(len(starts) - 1, ln + 1)]


READER = r"\b(u8|u16|u32|u64|i8|i16|i32|i64|pod|varint|readVarint|lenDelim|getU8|getU16|getU32|getU64)\s*(<[^()<>]*>)?\s*\(\s*\)"
WIDTH_OF_READER = {"u8": 8, "i8": 8, "u16": 16, "i16": 16, "u32": 32, "i32": 32, "u64": 64, "i64": 64, "varint": 64,
                   "readVarint": 64, "lenDelim": 64, "getU8": 8, "getU16": 16, "getU32": 32, "getU64": 64}
WIDTH_OF_TYPE = {"uint8_t": 8, "int8_t": 8, "char": 8, "unsigned char": 8, "signed char": 8, "uint16_t": 16, "int16_t": 16,
                 "short": 16, "unsigned short": 16, "uint32_t": 32, "int32_t": 32, "int": 32, "unsigned": 32, "unsigned int": 32}


def reader_width(expr):
    m = re.search(READER, expr)
    if not m:
        return 0
    if m.group(1) == "pod" and m.group(2):
        return WIDTH_OF_TYPE.get(re.sub(r"^<\s*(std::)?|\s*>$", "", m.group(2)), 64)
    return WIDTH_OF_READER[m.group(1)]


def derived_reader_width(f, fn, ln, ident):
    """The width of the reader call an identifier was assigned from earlier in the same function, and whether a
    comparison on it sits between that assignment and line ln (a bound). (0, False) when it is not reader-derived."""
    text, starts = code_of(f)
    a, _ = fn_span(f, fn, ln)
    body = text[a:starts[ln - 1]]
    castLine = text[starts[ln - 1]:starts[ln] if ln < len(starts) else len(text)]   # `fits( v ) ? T( v ) : 0` checks on the cast's own line
    width, bounded = 0, False
    idRx = r"\b" + re.escape(ident) + r"\b"
    for m in re.finditer(idRx + r"\s*(=|\{|\()\s*([^;]*);", body):
        w = reader_width(m.group(2))
        if w:
            width = w
            tail = body[m.end():] + castLine
            bounded = bool(re.search(idRx + r"\s*(<=|>=|<(?![<=])|>(?![>=])|==|!=)|(<=|>=|[^<>-]<|[^<>-]>|==|!=)\s*" + idRx, tail)
                           or re.search(r"\b(fitsBelow|countFits|qsnapCountFits|min|clamp)\s*\([^;]*" + idRx, tail))
    return width, bounded


def argument_width(f, fn, ln, arg):
    w = reader_width(arg)
    if w:
        return w, "direct"
    if re.fullmatch(r"\s*[A-Za-z_]\w*\s*", arg):
        w, bounded = derived_reader_width(f, fn, ln, arg.strip())
        if w and not bounded:
            return w, "derived:" + arg.strip()
    return 0, ""


def tsv(name, rows):
    with open(os.path.join(OUT, name), "w") as out:
        for r in rows:
            out.write("\t".join(str(x) for x in r) + "\n")


# ── (A) an enum built from a byte reader outside ByteR::enumU8 ───────────────────────────────────────────────────
enums = sorted({t.strip() for f, ln, fn, t in match('(enum_specifier name: (type_identifier) @n)')})
enumRx = "^(rw::)?(%s)$" % "|".join(re.escape(e) for e in enums) if enums else "^$"
casts = []
casts += [(f, ln, fn, t, a) for f, ln, fn, t, a in tuples(match('(call_expression function: [(identifier) (qualified_identifier)] @t arguments: (argument_list . (_) @a .) (#match? @t "%s"))' % enumRx), 2)]
casts += [(f, ln, fn, t, a) for f, ln, fn, _c, t, a in tuples(match('(call_expression function: (template_function name: (identifier) @_c arguments: (template_argument_list . (type_descriptor) @t .)) arguments: (argument_list . (_) @a .) (#eq? @_c "static_cast") (#match? @t "%s"))' % enumRx), 3)]
casts += [(f, ln, fn, t, a) for f, ln, fn, t, a in tuples(match('(cast_expression type: (type_descriptor) @t value: (_) @a (#match? @t "%s"))' % enumRx), 2)]
armA = Counter()
for f, ln, fn, t, a in casts:
    w, how = argument_width(f, fn, ln, a)
    if w:
        armA[(f, fn, re.sub(r"^rw::", "", t.strip()))] += 1
tsv("a.tsv", [(f, fn, e, n) for (f, fn, e), n in sorted(armA.items())])

# ── (D) a decoded value narrowed into a smaller integer with no check ────────────────────────────────────────────
narrowRx = r"^(std::)?(u?int(8|16|32)_t|char|unsigned char|signed char|short|unsigned short|int|unsigned|unsigned int)$"
ncasts = []
ncasts += [(f, ln, fn, t, a) for f, ln, fn, t, a in tuples(match('(call_expression function: [(identifier) (qualified_identifier) (primitive_type)] @t arguments: (argument_list . (_) @a .) (#match? @t "%s"))' % narrowRx), 2)]
ncasts += [(f, ln, fn, t, a) for f, ln, fn, _c, t, a in tuples(match('(call_expression function: (template_function name: (identifier) @_c arguments: (template_argument_list . (type_descriptor) @t .)) arguments: (argument_list . (_) @a .) (#eq? @_c "static_cast") (#match? @t "%s"))' % narrowRx), 3)]
ncasts += [(f, ln, fn, t, a) for f, ln, fn, t, a in tuples(match('(cast_expression type: (type_descriptor) @t value: (_) @a (#match? @t "%s"))' % narrowRx), 2)]
armD = Counter()
for f, ln, fn, t, a in ncasts:
    target = WIDTH_OF_TYPE.get(re.sub(r"^std::", "", t.strip()), 64)
    w, how = argument_width(f, fn, ln, a)
    if w > target:
        armD[(f, fn, "%s<-%d" % (re.sub(r"^std::", "", t.strip()), w))] += 1
tsv("d.tsv", [(f, fn, k, n) for (f, fn, k), n in sorted(armD.items())])

# ── (B1) catch handlers that record nothing ──────────────────────────────────────────────────────────────────────
# DISCLOSE is arity-sensitive, so it is NOT in this alternation: the sink form DISCLOSE( sink, why[, "msg"] ) calls
# sink.disclose( why ) in every build and genuinely records something (the trailing comma-before-`,` clause below
# catches it), but the one-argument DISCLOSE( "msg" ) is a debug-only trace — nothing in Release — so it must fall
# through to the alert-only classification a few lines down, the same as the old one-argument degrade-alert macro did.
RECORDS = re.compile(r"(?<![=!<>])=(?!=)|\.store\s*\(|\breturn\s+[^;\s]|\+\+|--|\b(emitTo|emitRaw|fprintf|fputs|fail|PANIC|push_back|emplace_back|append)\s*\(|\bthrow\b|\bDISCLOSE\s*\([^)]*,")
catchRows = match('(catch_clause) @c')
perLine = defaultdict(int)
armB1, recorded = Counter(), 0
for f, ln, fn, _t in catchRows:
    text, starts = code_of(f)
    lineText = text[starts[ln - 1]:starts[ln] if ln < len(starts) else len(text)]
    hits = [m.start() for m in re.finditer(r"\bcatch\s*\(", lineText)]
    k = perLine[(f, ln)]
    perLine[(f, ln)] += 1
    if k >= len(hits):
        print("SCANFAIL catch row %s:%d has no catch token #%d on its line" % (f, ln, k))
        sys.exit(3)
    pos = starts[ln - 1] + hits[k]
    paren = text.find("(", pos)
    brace = text.find("{", balanced(text, paren))
    body = text[brace + 1:balanced(text, brace) - 1]
    if RECORDS.search(body):
        recorded += 1
        continue
    cls = "alert-only" if re.search(r"\bDISCLOSE\s*\(", body) else "silent"
    armB1[(f, fn, cls)] += 1
tsv("b1.tsv", [(f, fn, c, n) for (f, fn, c), n in sorted(armB1.items())])

# ── (B2) a throw with no try around it in its own function ───────────────────────────────────────────────────────
armB2 = Counter()
throwRows = match('(throw_statement) @t')
perLine = defaultdict(int)
for f, ln, fn, _t in throwRows:
    text, starts = code_of(f)
    lineText = text[starts[ln - 1]:starts[ln] if ln < len(starts) else len(text)]
    hits = [m.start() for m in re.finditer(r"\bthrow\b", lineText)]
    k = perLine[(f, ln)]
    perLine[(f, ln)] += 1
    pos = starts[ln - 1] + hits[min(k, len(hits) - 1)] if hits else starts[ln - 1]
    a, _ = fn_span(f, fn, ln)
    stack = []
    for m in re.finditer(r"[{}]", text[a:pos]):
        if m.group(0) == "{":
            before = text[a:a + m.start()].rstrip()
            stack.append(before.endswith("try") and not re.search(r"\w$", before[:-3]))
        elif stack:
            stack.pop()
    if not any(stack):
        armB2[(f, fn)] += 1
tsv("b2.tsv", [(f, fn, n) for (f, fn), n in sorted(armB2.items())])

# ── (C) a throwing (or overflow-undefined) standard call in code that must not throw ─────────────────────────────
armC = Counter()
for f, ln, fn, name in match('(call_expression function: [(identifier) (qualified_identifier)] @f (#match? @f "^(std::)?(stoi|stol|stoll|stoul|stoull|stof|stod|stold|atoi|atol|atoll|atof)$"))'):
    armC[(f, fn, name.strip().replace("std::", ""))] += 1
for f, ln, fn, name, args in tuples(match('(call_expression function: (field_expression field: (field_identifier) @f) arguments: (argument_list) @a (#match? @f "^(at|value)$"))'), 2):
    if name == "value" and args.replace(" ", "") != "()":
        continue
    armC[(f, fn, "." + name)] += 1
FS_THROWING = ("absolute|canonical|weakly_canonical|relative|proximate|copy|copy_file|copy_symlink|create_directory|create_directories|"
               "create_hard_link|create_symlink|create_directory_symlink|current_path|equivalent|exists|file_size|hard_link_count|"
               "is_block_file|is_character_file|is_directory|is_empty|is_fifo|is_other|is_regular_file|is_socket|is_symlink|"
               "last_write_time|permissions|read_symlink|remove|remove_all|rename|resize_file|space|status|symlink_status|temp_directory_path")
FS_STATUS_OVERLOAD = {"exists", "is_block_file", "is_character_file", "is_directory", "is_fifo", "is_other", "is_regular_file", "is_socket", "is_symlink"}


def args_on_line(f, ln, nameRx, fallback):
    """The full argument text of the first `name(` call on source line ln, read from the blanked source (a capture's
    row text is whitespace-collapsed and cut at ~120 characters, so a long argument list must be re-read)."""
    text, starts = code_of(f)
    lineEnd = starts[ln] if ln < len(starts) else len(text)
    m = re.search(nameRx + r"\s*(\w+\s*)?\(", text[starts[ln - 1]:lineEnd])
    if not m:
        return fallback
    open_ = starts[ln - 1] + m.end() - 1
    return text[open_:balanced(text, open_)]


def ec_names(f):
    text, _ = code_of(f)
    return set(re.findall(r"\berror_code\s*&?\s*([A-Za-z_]\w*)", text))


def status_names(f):
    text, _ = code_of(f)
    return set(re.findall(r"\bfile_status\s*&?\s*([A-Za-z_]\w*)", text))


fsCalls = 0
for f, ln, fn, name, args in tuples(match('(call_expression function: (qualified_identifier) @f arguments: (argument_list) @a (#match? @f "^((std::)?filesystem|fs)::(%s)$"))' % FS_THROWING), 2):
    fsCalls += 1
    short = name.split("::")[-1]
    args = args_on_line(f, ln, re.escape(short), args)
    idents = set(re.findall(r"\b[A-Za-z_]\w*\b", args))
    if idents & ec_names(f):
        continue
    inner = args.strip()[1:-1].strip()
    if short in FS_STATUS_OVERLOAD and (inner in status_names(f) or re.match(r"^(\w+::)*(status|symlink_status)\s*\(", inner) or re.search(r"\.(status|symlink_status)\s*\(", inner)):
        continue
    armC[(f, fn, "fs::" + short + " without error_code")] += 1
for f, ln, fn, t, args in tuples(match('(call_expression function: (qualified_identifier) @t arguments: (argument_list) @a (#match? @t "directory_iterator$"))'), 2) + \
        tuples(match('(declaration type: (qualified_identifier) @t declarator: (init_declarator value: (argument_list) @a) (#match? @t "directory_iterator$"))'), 2):
    args = args_on_line(f, ln, r"directory_iterator", args)
    if args.replace(" ", "").replace("\n", "") == "()":
        continue        # a default-constructed end iterator is noexcept
    if not (set(re.findall(r"\b[A-Za-z_]\w*\b", args)) & ec_names(f)):
        armC[(f, fn, "directory_iterator without error_code")] += 1
for f, ln, fn, rng in match('(for_range_loop right: (_) @r)'):
    if "directory_iterator" in rng:
        armC[(f, fn, "range-for over a directory_iterator (operator++ throws)")] += 1
for f, ln, fn, name, args in tuples(match('(call_expression function: (field_expression field: (field_identifier) @f) arguments: (argument_list) @a (#match? @f "^(is_directory|is_regular_file|is_symlink|is_fifo|is_socket|is_other|is_block_file|is_character_file|file_size|hard_link_count|last_write_time|symlink_status|refresh|exists|status)$"))'), 2):
    if args.replace(" ", "") == "()":
        armC[(f, fn, "." + name + "() without error_code")] += 1
dirIterFiles = {f for f, ln, fn, t in fnDefsRows if "directory_iterator" in code_of(f)[0]}
for f in sorted(dirIterFiles):
    text, starts = code_of(f)
    for decl in re.finditer(r"directory_iterator\s+([A-Za-z_]\w*)\s*[({;]", text):
        name = decl.group(1)
        depth, k = 0, decl.start()
        while k > 0 and depth >= 0:          # walk back to the brace that opens the declaring block
            k -= 1
            depth += {"}": 1, "{": -1}.get(text[k], 0)
        scopeEnd = balanced(text, k) if text[k] == "{" else len(text)
        for m in re.finditer(r"\+\+\s*" + re.escape(name) + r"\b(?!\s*(->|\.))|\b" + re.escape(name) + r"\s*\+\+", text[decl.end():scopeEnd]):
            armC[(f, "?", "++ on directory_iterator " + name)] += 1
tsv("c.tsv", [(f, fn, k, n) for (f, fn, k), n in sorted(armC.items())])

# ── (E) raw acquisitions crashsweepcheck's S2 does not name (fopen/open/popen/opendir/fdopen/open_memstream are its) ─
# src/infra/os.h is THE seam (see its own header comment): socket/accept/pipe/dup/kqueue now reach a call site as
# os::X or rw::os::X, so ACQ accepts that prefix on every name (accept keeps its own alternative since it is also
# reached bare as ::accept4?). dirwatch_open (kqueue()'s only caller) has no bare-libc name of its own, so it is
# listed directly. os.h's OWN wrapper DEFINITIONS are the one place the bare libc call still appears — but ONLY
# for the PURE PASSTHROUGH shape: a whole function body that is one `return (::)?NAME( args );`, forwarding its
# own parameters and nothing else. That shape, and only that shape, is exempt inside os.h — the exemption is by
# shape, not by file name, so a helper that does real work there is scanned like any other file.
OS_SEAM_HEADER = "infra/os.h"
ACQ = ("^(::|std::|os::|rw::os::)?(socket|pipe|pipe2|dup|kqueue|dirwatch_open|epoll_create|epoll_create1|inotify_init1|eventfd|mkstemp|mkdtemp|malloc|calloc|realloc|"
       "strdup|strndup|posix_memalign|aligned_alloc|ts_parser_new|ts_query_new|ts_query_cursor_new|ts_tree_copy|ts_parser_parse|"
       "ts_parser_parse_string|ts_parser_parse_string_encoding|ts_tree_cursor_new|ts_tree_cursor_copy)$|^(::|os::|rw::os::)accept4?$")
destructorOf = {}


def has_destructor(f, typeName):
    key = (f, typeName)
    if key not in destructorOf:
        destructorOf[key] = bool(re.search(r"~\s*" + re.escape(typeName) + r"\s*\(", code_of(f)[0]))
    return destructorOf[key]


def _param_name(p):
    m = re.search(r"([A-Za-z_]\w*)\s*(?:\[[^\]]*\])?$", p.strip())
    return m.group(1) if m else p.strip()


def os_seam_passthrough(f, ln):
    if f != OS_SEAM_HEADER:
        return False
    line = code_of(f)[0].split("\n")[ln - 1]
    m = re.search(r"\(([^()]*)\)\s*\{\s*return\s+(?:::)?[A-Za-z_]\w*\s*\(([^()]*)\)\s*;\s*\}\s*$", line.strip())
    if not m:
        return False
    params = [_param_name(p) for p in m.group(1).split(",") if p.strip()]
    args = [a.strip() for a in m.group(2).split(",") if a.strip()]
    return params == args


armE, owned = Counter(), 0
for f, ln, fn, name in match('(call_expression function: [(identifier) (qualified_identifier)] @f (#match? @f "%s"))' % ACQ):
    if os_seam_passthrough(f, ln):
        continue
    if has_destructor(f, fn.split("::")[-1]):
        owned += 1      # acquired inside a type whose destructor releases it (the ParserGuard / ChildCursor shape)
        continue
    armE[(f, fn, name.strip().replace("rw::os::", "").replace("os::", "").replace("std::", "").lstrip(":"))] += 1
for f, ln, fn, t in match('(new_expression) @n'):
    if re.match(r"^new\s*\(", t.strip()):
        continue        # placement new constructs into storage someone else owns
    armE[(f, fn, "new")] += 1
tsv("e.tsv", [(f, fn, k, n) for (f, fn, k), n in sorted(armE.items())])

print("SCANOK queries=%d enums=%d enum_casts=%d narrow_casts=%d catches=%d recorded=%d throws=%d fs_calls=%d owned_acq=%d" %
      (queriesRun, len(enums), len(casts), len(ncasts), len(catchRows), recorded, len(throwRows), fsCalls, owned))
SCANPY

# ── registries: file, function, key, count, reason ─────────────────────────────────────────────────────────────
cat > "$TMP/reg_a.tsv" <<'REGA'
gitoracle.h	loadOracleCache	Fate	1	range-checked against kFateTable in the same record's guard, before the record enters the index; Fate's underlying type is uint8_t, so the construction itself is defined
REGA
cat > "$TMP/reg_b1.tsv" <<'REGB1'
infra/emit.h	emitTo	silent	1	not an answer path: std::print's failed write is made silent to keep fputs's contract, which the header documents
ingest_astquery.h	astQueryGrouped	silent	1	FINDING: a file whose query walk throws drops out of --match/--lint hits with no disclosure in any build; file held by the regexguard and crash-fixes lanes
ingest_astquery.h	spanTiersOfFiles	alert-only	1	FINDING (disclosure lane): a tier worker that throws leaves its files unclassified for --grep-in, silent in Release
ingest_docpass.h	runDocPostPass	alert-only	1	FINDING (disclosure lane): a doc post-pass throw skips that document, silent in Release
mcpindex.h	maybePrefetchHeadSnapshot	silent	1	not an answer path: optional background prefetch of the HEAD snapshot; a request recomputes whatever it did not fill (§2b rule 3)
REGB1
cat > "$TMP/reg_b2.tsv" <<'REGB2'
alloccount.cpp	operator new	2	the one throw seam CONTRIBUTING §3 permits: operator new under RIPWIRE_ALLOC_COUNT, an A/B instrument no shipped build links
infra/dynamic_map.hpp	at	1	vendored container API; no ripwire call site reaches it (rule C lists its one caller, the container's own non-const at)
regexguard.h	throwIfMatchFaultInjected	1	the RIPWIRE_FAULT_REGEX_MATCH fault switch, off unless the variable is set; its three call sites are the first statement inside GuardedRegex's search, search and forEachMatch try blocks, which catch std::regex_error by type and return Exhausted
REGB2
cat > "$TMP/reg_c.tsv" <<'REGC'
infra/dynamic_map.hpp	at	.at	1	the non-const at forwards to the const at of the same container; no ripwire caller
ingest_astquery.h	nearestNodeKindHint	.at	1	the key was just read out of this same map by nearestNameByEditDistance, so it is present
REGC
cat > "$TMP/reg_d.tsv" <<'REGD'
REGD
cat > "$TMP/reg_e.tsv" <<'REGE'
alloccount.cpp	countedAlloc	malloc	1	the counting allocator's own storage, freed by its operator delete (A/B instrument, never shipped)
alloccount.cpp	operator new	aligned_alloc	1	the counting allocator's aligned storage, freed by its operator delete (A/B instrument, never shipped)
infra/dynamic_map.hpp	compact	new	4	the rebuilt pools replace the old ones (delete[] before the swap, owned by ~dynamic_map after it); the two scratch arrays are delete[]d before the return
infra/dynamic_map.hpp	dynamic_map	new	2	the constructor's pools, owned by ~dynamic_map
infra/os_win32.cpp	getline	realloc	1	Windows body of os::getline: POSIX getline's contract hands the grown *line buffer to the caller, who frees it (pathguard.h NoFollowRead frees its lineBuf)
infra/os_win32.cpp	open_memstream	malloc	1	Windows body of os::open_memstream: POSIX hands *buffer to the caller, who frees it (rw::MemoryStream's destructor)
infra/os_win32.cpp	publishMemoryStream	realloc	1	Windows os::fflush / os::fclose republishing a memstream's *buffer: the caller's pointer is replaced in place and the caller frees it, as with POSIX open_memstream
infra/os_win32.cpp	realpath	malloc	1	Windows body of os::realpath( path, nullptr ): POSIX returns malloc'd storage the caller frees
infra/profileScope.h	alloc	new	1	profiling build only: pushed into RecordArena::m_blocks, deleted by ~RecordArena
infra/profileScope.h	create	new	1	profiling build only: registered in m_threads, deleted when the thread retires
infra/profileScope.h	registry	new	1	profiling build only: the registry core is leaked on purpose so retire() is safe during static destruction
infra/svector.h	grow	new	1	the spilled buffer is owned by the svector: delete[] on every regrow, clear and destruction
ingest_astquery.h	astQueryGrouped	ts_parser_parse_string	1	the tree is deleted by hand in the same block after the walk
ingest_astquery.h	astQueryGrouped	ts_query_cursor_new	1	deleted by hand after the file loop; the per-file catch keeps a throw from leaving the loop early
ingest_astquery.h	astQueryGrouped	ts_query_new	1	a compile probe, deleted inside the same if
ingest_astquery.h	collectGatedLocalNames	ts_parser_new	1	deleted before each of the three returns
ingest_astquery.h	collectGatedLocalNames	ts_parser_parse_string	1	deleted before the final return
ingest_astquery.h	compileGrammarQueries	ts_query_new	2	moved into GrammarQueries (or deleted when the combined query does not add up); astQueryGrouped deletes every one by hand after the pass
ingest_astquery.h	computeGrammarDisclosure	ts_query_new	1	a compile probe, deleted inside the same if
ingest_astquery.h	spanTiersOfFiles	ts_parser_parse_string	1	the tree is deleted right after the walk
ingest_crawl.h	compileQueryStandalone	ts_query_new	1	returned into the process-lifetime CompiledQueryCache, whose destructor deletes every query
ingest_parsepool.h	runParseWorker	ts_query_cursor_new	1	deleted at the end of the worker; the returns in between belong to lambdas
ingest_sidecap.h	parseTree	ts_parser_parse_string	1	returned to the caller, which adopts it into TreeGuard
jsrunner.h	hasNodeTestImport	ts_parser_new	1	deleted right after the parse, before the null-tree return
jsrunner.h	hasNodeTestImport	ts_parser_parse_string	1	the tree is deleted by hand after the whole-tree walk, before the return
jsrunner.h	relativeImportsResolvable	ts_parser_new	1	deleted right after the parse, before the null-tree return
jsrunner.h	relativeImportsResolvable	ts_parser_parse_string	1	deleted on the has-error return and right after the specifier walk
main.cpp	runWithCompactLegend	dup	1	closed on the failure path and after the restore on the success path
mcpindex.h	arm	dirwatch_open	1	owned	held by the FS watcher, closed by its reset and its destructor
mcpserver.h	runMcpHttp	accept	1	each accepted connection is closed after its one request
mcpserver.h	runMcpHttp	socket	1	the listening socket is closed before every return
pattern.h	compileFor	ts_parser_new	1	deleted right after the parse, and on the null-language return
pattern.h	compileFor	ts_parser_parse_string	1	deleted before each return
pythonrunner.h	topLevelEvidence	ts_parser_new	1	deleted on the grammar-refused return and right after the parse
pythonrunner.h	topLevelEvidence	ts_parser_parse_string	1	the tree is deleted by hand after the top-level walk, before the return
slice.h	sliceBuildParentIndex	ts_tree_cursor_new	1	deleted before the only return, where the cursor walk ends
slice.h	sliceScanDefinition	ts_parser_new	1	deleted before each return
slice.h	sliceScanDefinition	ts_parser_parse_string	1	deleted before the final return
verbs_change.h	runCommandCapture	pipe	1	both ends closed in the child, the write end in the parent at once and the read end after the drain
verbs_doctor.h	doctorParseProbe	ts_parser_new	1	deleted before the return
verbs_doctor.h	doctorParseProbe	ts_parser_parse_string	1	deleted inside the same if
verbs_doctor.h	doctorProbeGrammars	ts_query_new	1	a compile probe, deleted inside the same if
REGE

judge_static(){   # $1 = scan output dir, $2 = label (src | probe); echoes one line per violation
    python3 - "$1" "$TMP" "$2" <<'JUDGEPY'
import os, sys
out, tmp, label = sys.argv[1], sys.argv[2], sys.argv[3]
def rows(path):
    if not os.path.exists(path):
        return None
    return [l.rstrip("\n").split("\t") for l in open(path) if l.strip()]
WHAT = {"a": "builds an enum from a byte reader — use ByteR::enumU8<E>( count )",
        "b1": "has a catch handler that records nothing",
        "b2": "throws with no try around it in its own function",
        "c": "calls a throwing (or overflow-undefined) standard API — use the error_code / from_chars spelling",
        "d": "narrows a decoded value with no check — use a checked reader (ByteR::u16Of32)",
        "e": "acquires a raw resource with no RAII owner — give it one"}
for rule, keyCols in (("a", 3), ("b1", 3), ("b2", 2), ("c", 3), ("d", 3), ("e", 3)):
    seen = rows(os.path.join(out, rule + ".tsv"))
    if seen is None:
        print("%s\tthe scan wrote no %s.tsv — the rule did not run" % (rule.upper(), rule))
        continue
    found = {tuple(r[:keyCols]): int(r[keyCols]) for r in seen}
    if label != "src":
        for key, n in sorted(found.items()):
            print("%s\t%s %s: %d site(s) %s" % (rule.upper(), key[0], " ".join(key[1:]), n, WHAT[rule]))
        continue
    reg = {tuple(r[:keyCols]): int(r[keyCols]) for r in rows(os.path.join(tmp, "reg_" + rule + ".tsv"))}
    for key, n in sorted(found.items()):
        if reg.get(key) != n:
            print("%s\t%s %s: %d site(s) %s (registry says %s)" % (rule.upper(), key[0], " ".join(key[1:]), n, WHAT[rule], reg.get(key, 0)))
    pending = {tuple(r[:keyCols]) for r in rows(os.path.join(tmp, "reg_" + rule + ".tsv")) if r[keyCols + 1].startswith("PENDING")}
    for key in sorted(reg):
        if key not in found:
            if key in pending:
                print("NOTE\t%s registry row %s is PENDING and matches no site — its fix has landed; delete the row" % (rule.upper(), " / ".join(key)))
            else:
                print("%s\tregistry row %s matches no site any more — delete the row" % (rule.upper(), " / ".join(key)))
JUDGEPY
}

# The probe tree: one violation and one compliant twin per rule.
PROBE="$TMP/probe"; mkdir -p "$PROBE"
cat > "$PROBE/probe_hazard.h" <<'PROBEH'
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <system_error>
#include <vector>
enum class ProbeKind : std::uint8_t { First, Second };
inline constexpr std::size_t kProbeKindCount = 2;
struct ProbeReader
{
    const char* p; const char* end; bool ok = true;
    std::uint8_t  u8();
    std::uint32_t u32();
    std::uint16_t u16Of32();
    template<class E> E enumU8( std::size_t count );
};
inline ProbeKind probeEnumDirect( ProbeReader& r ) { return ProbeKind( r.u8() ); }
inline ProbeKind probeEnumStatic( ProbeReader& r ) { return static_cast<ProbeKind>( r.u8() ); }
inline ProbeKind probeEnumDerived( ProbeReader& r )
{
    const std::uint8_t k = r.u8();
    return ProbeKind( k );
}
inline ProbeKind probeEnumChecked( ProbeReader& r ) { return r.enumU8<ProbeKind>( kProbeKindCount ); }
inline std::uint16_t probeNarrowDirect( ProbeReader& r ) { return std::uint16_t( r.u32() ); }
inline std::uint16_t probeNarrowBounded( ProbeReader& r )
{
    const std::uint32_t v = r.u32();
    if( v > 0xFFFF ) { r.ok = false; return 0; }
    return std::uint16_t( v );
}
inline std::uint16_t probeNarrowChecked( ProbeReader& r ) { return r.u16Of32(); }
inline std::uint16_t probeNarrowHelper( ProbeReader& r )
{
    const std::uint32_t w = r.u32();
    return fitsBelow( w, 0x10000u ) ? std::uint16_t( w ) : std::uint16_t( 0 );
}
inline void probeThrowBare( int x ) { if( x ) { throw x; } }
inline int  probeThrowInTry( int x ) { try { if( x ) { throw x; } } catch( ... ) { return 1; } return 0; }
inline void probeCatchSilent() { try { probeThrowBare( 1 ); } catch( ... ) { } }
inline void probeCatchAlertOnly() { try { probeThrowBare( 1 ); } catch( ... ) { DISCLOSE( "probe" ); } }
inline bool probeCatchRecords() { try { probeThrowBare( 1 ); } catch( ... ) { return false; } return true; }
inline int  probeAtoi( const char* s ) { return std::atoi( s ); }
inline int  probeAt( const std::vector<int>& v ) { return v.at( 3 ); }
inline bool probeFsThrows( const std::string& path ) { return std::filesystem::exists( path ); }
inline bool probeFsNoThrow( const std::string& path ) { std::error_code probeEc; return std::filesystem::exists( path, probeEc ); }
inline int  probeDirRangeFor( const std::string& path )
{
    std::error_code rangeEc;
    int n = 0;
    for( const std::filesystem::directory_entry& e : std::filesystem::directory_iterator( path, rangeEc ) ) { n += e.is_directory() ? 1 : 0; }
    return n;
}
inline int  probeDirIncrement( const std::string& path )
{
    std::error_code incEc;
    int n = 0;
    for( std::filesystem::directory_iterator it( path, incEc ), end; !incEc && it != end; it.increment( incEc ) ) { n += it->is_directory( incEc ) ? 1 : 0; }
    return n;
}
inline void* probeRawAlloc() { return std::malloc( 8 ); }
struct ProbeOwner
{
    void* p = std::malloc( 8 );
    ~ProbeOwner() { std::free( p ); }
};
namespace os { int socket( int domain, int type, int protocol ); }   // stands in for rw::os::socket
inline int probeOsAcquire() { return os::socket( 0, 0, 0 ); }   // os::-spelled site, unregistered: E must still catch it
PROBEH
if ! python3 "$TMP/scan.py" "$BIN" "$PROBE" "$TMP/probe_out" >"$TMP/probe_scan.txt" 2>&1; then
    no "static rules: the probe scan did not complete: $( tail -1 "$TMP/probe_scan.txt" )"
else
    judge_static "$TMP/probe_out" probe >"$TMP/probe_verdict.txt"
    expect_probe(){   # $1 rule, $2 regex that must match exactly $3 verdict lines of that rule, $4 label
        local got; got="$( grep -c "^$1	.*$2" "$TMP/probe_verdict.txt" )"
        if [ "$got" -eq "$3" ]; then ok "$1 probe: $4"; else no "$1 probe: $4 — expected $3 matching verdict(s), got $got"; sed 's/^/          /' "$TMP/probe_verdict.txt"; fi
    }
    expect_probe A 'probeEnumDirect ProbeKind: 1'   1 "a functional cast of r.u8() to an enum fires"
    expect_probe A 'probeEnumStatic ProbeKind: 1'   1 "a static_cast of r.u8() to an enum fires"
    expect_probe A 'probeEnumDerived ProbeKind: 1'  1 "a cast of a local assigned from r.u8() fires"
    expect_probe A 'probeEnumChecked'               0 "ByteR::enumU8<E>( count ) does not fire"
    expect_probe D 'probeNarrowDirect uint16_t<-32: 1' 1 "std::uint16_t( r.u32() ) fires"
    expect_probe D 'probeNarrowBounded'            0 "a local compared against its bound before the cast does not fire"
    expect_probe D 'probeNarrowChecked'            0 "a checked reader (u16Of32) does not fire"
    expect_probe D 'probeNarrowHelper'             0 "a local passed through a bound helper (fitsBelow) on the cast's own line does not fire"
    expect_probe B1 'probeCatchSilent silent: 1'    1 "an empty catch fires as silent"
    expect_probe B1 'probeCatchAlertOnly alert-only: 1' 1 "a catch whose only statement is DISCLOSE fires as alert-only"
    expect_probe B1 'probeCatchRecords'             0 "a catch that returns a value does not fire"
    expect_probe B2 'probeThrowBare: 1'             1 "a throw with no try in its function fires"
    expect_probe B2 'probeThrowInTry'               0 "a throw inside a local try does not fire"
    expect_probe C 'probeAtoi atoi: 1'              1 "std::atoi fires"
    expect_probe C 'probeAt .at: 1'                 1 ".at( ) fires"
    expect_probe C 'probeFsThrows fs::exists without error_code: 1' 1 "std::filesystem::exists( p ) fires"
    expect_probe C 'probeFsNoThrow'                 0 "std::filesystem::exists( p, ec ) does not fire"
    expect_probe C 'probeDirRangeFor range-for'     1 "a range-for over a directory_iterator fires"
    expect_probe C 'probeDirRangeFor .is_directory() without error_code: 1' 1 "directory_entry::is_directory( ) fires"
    expect_probe C 'probeDirIncrement'              0 "increment( ec ) and is_directory( ec ) do not fire"
    expect_probe E 'probeRawAlloc malloc: 1'        1 "a bare malloc fires"
    expect_probe E 'ProbeOwner'                     0 "a malloc inside a type whose destructor frees it does not fire"
    expect_probe E 'probeOsAcquire socket: 1'       1 "an os::-spelled unregistered site still fires (the seam's own spelling is not a free pass)"
    [ "$( grep -c . "$TMP/probe_verdict.txt" )" -eq 14 ] \
        && ok "probe: exactly the 14 planted violations fire, nothing else" \
        || { no "probe: expected exactly 14 verdict lines, got $( grep -c . "$TMP/probe_verdict.txt" )"; sed 's/^/          /' "$TMP/probe_verdict.txt"; }
fi

if ! python3 "$TMP/scan.py" "$BIN" "$SRC" "$TMP/src_out" >"$TMP/src_scan.txt" 2>&1; then
    no "static rules: the src/ scan did not complete: $( tail -1 "$TMP/src_scan.txt" )"
else
    SUMMARY="$( grep '^SCANOK' "$TMP/src_scan.txt" )"
    read -r enums casts ncasts catches throws fscalls <<<"$( sed -E 's/.*enums=([0-9]+) enum_casts=([0-9]+) narrow_casts=([0-9]+) catches=([0-9]+) .*throws=([0-9]+) .*fs_calls=([0-9]+).*/\1 \2 \3 \4 \5 \6/' <<<"$SUMMARY" )"
    if [ "${enums:-0}" -ge 50 ] && [ "${casts:-0}" -ge 10 ] && [ "${ncasts:-0}" -ge 500 ] && [ "${catches:-0}" -ge 15 ] \
        && [ "${throws:-0}" -ge 3 ] && [ "${fscalls:-0}" -ge 40 ]; then
        ok "static rules reached the source ($SUMMARY)"
    else
        no "static rules found almost nothing to judge ($SUMMARY) — a broken query reads as a clean tree"
    fi
    judge_static "$TMP/src_out" src >"$TMP/src_verdict.txt"
    for rule in A B1 B2 C D E; do
        if grep -q "^$rule	" "$TMP/src_verdict.txt"; then
            no "$rule: $( grep -c "^$rule	" "$TMP/src_verdict.txt" ) violation(s):"
            grep "^$rule	" "$TMP/src_verdict.txt" | cut -f2 | sed 's/^/          /'
        else
            ok "$rule: every site under ${SRC#"$ROOT"/} is registered, and every registry row still matches a site"
        fi
    done
    grep '^NOTE	' "$TMP/src_verdict.txt" | cut -f2 | while IFS= read -r line; do note "$line"; done
    note "FINDING rows carried by the registries (real defects in files other lanes hold): $( cat "$TMP"/reg_*.tsv | grep -c 'FINDING' ); PENDING rows (fixed on another branch): $( cat "$TMP"/reg_*.tsv | grep -c 'PENDING' )"
fi

echo
[ "$fail" -eq 0 ] && { echo "hazardpatterncheck: ALL PASS"; exit 0; } || { echo "hazardpatterncheck: SOME CHECKS FAILED"; exit 1; }
