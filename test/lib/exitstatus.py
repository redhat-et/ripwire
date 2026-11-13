#!/usr/bin/env python3
"""exitstatus.py -- does a shell script TEST the exit status of each command it runs under test?

The reusable half of test/gateexitcheck.sh arm (H). A gate that runs ripwire (or a harness it compiled) and
reads only the command's OUTPUT passes an absence arm, a count arm or a parity arm when the command crashed
after printing, or printed nothing: CodeRabbit drew that finding five times in one week (#615 x2: clonebandcheck
W1 read the uncapped harness's output and not its exit code, qdtype3oncecheck wrote each call's rc to a file and
compared no rc to 0; #616: fordemoteallcheck read a failed twin's empty answer as zero rows).

CONTRACT (stable; the qd shell-test facet reuses it, so change it only additively):

    scan( text, extra=() ) -> list[ Call ]
        text   the script's source.
        extra  more command-word patterns (fnmatch over the unquoted word) to treat as "under test".
    Call( line, cmd, verdict, how, kind )
        line     1-based line of the call (for a wrapper function, the line of the CALL SITE).
        cmd      the command word as written, plus " via NAME()" when reached through a wrapper.
        verdict  "checked" or "unchecked".
        how      why: "if", "|| X", "&& .. || X", "rc=$? compared", "set -e", "exit status", or, for an unchecked
                 call, what lost the status ("output only", "status discarded in a pipe", "$(...) argument", ...).
        kind     "ripwire" (the binary, or a variable naming a ripwire build), "harness" (a program this script
                 compiled, or a `harness` path), "extra" (matched `extra`) or "wrapper" (a shell function whose
                 status is one of those).

    A command is UNDER TEST when its command word is the ripwire binary (a variable named BIN, *_BIN, BIN_*,
    RIPWIRE, RW or HARNESS, or any variable assigned a value naming build/ripwire or $RIPWIRE_BIN), a harness the
    script compiled (the `-o` target of a c++/clang++/g++/cc/$CXX/$CC command, `$var` segments read as globs),
    a word containing `harness`, a word matching `extra`, or a shell function whose own status IS such a
    command's status (a wrapper; resolved to a fixpoint, so wrappers of wrappers count).

    "Tests its status" means one of: inside an if/elif/while/until condition; a later `||` in the same and-or
    list whose right side is not `true`/`:`; `$?` (or PIPESTATUS) read by the very next statement, directly in a
    test or into a variable / file that some test in the script compares; `set -e` (`-o errexit`) in effect where
    errexit can fire (not left of && / ||, not negated, not a non-final pipe stage without pipefail); or the
    command is the script's last statement (its status IS the gate's). A pipe stage counts only under pipefail.

    What it does NOT see: commands inside heredoc bodies (Python heredocs check their own subprocess calls),
    strings passed to `bash -c`, and a status lost inside a function reached only by `eval`. A positive OUTPUT
    assertion is not a status test: this matcher reports the status fact, and the caller decides what to gate.

CLI:  python3 test/lib/exitstatus.py FILE...   ->  one `file:line<TAB>verdict<TAB>how<TAB>cmd` row per call.
"""
import fnmatch, re, sys
from collections import namedtuple

Call = namedtuple( "Call", "line cmd verdict how kind" )

# ── lexer ─────────────────────────────────────────────────────────────────────────────────────────────────────
# Tokens: ( kind, text, line ). kind in WORD, OP, NL. A WORD keeps its raw text; command substitutions inside it
# are parsed separately (subs: list of ( raw_inner, line )).
OPS = [ "&&", "||", ";;&", ";;", ";&", "|&", "<<<", "<<-", "<<", ">>", "&>>", "&>", ">&", "<&", "<>", ">|",
        ";", "|", "&", "(", ")", "<", ">" ]
OPCHARS = frozenset( "&|;()<>" )                  # every operator in OPS starts with one of these
KEYWORDS = { "if", "then", "elif", "else", "fi", "while", "until", "do", "done", "for", "in", "case", "esac",
             "{", "}", "!", "function", "select" }

class Word:
    __slots__ = ( "text", "line", "subs" )
    def __init__( self, text, line, subs ):
        self.text, self.line, self.subs = text, line, subs
    def __repr__( self ): return "W(%r@%d)" % ( self.text, self.line )

def _skip_quote( s, i, q ):
    """s[i] is the opening quote q; return the index after the closing one."""
    i += 1
    while i < len( s ):
        c = s[i]
        if q == '"' and c == "\\": i += 2; continue
        if q == '"' and c == "$" and s.startswith( "$(", i ):
            i = _skip_paren( s, i + 1 ); continue
        if q == '"' and c == "`":
            j = s.find( "`", i + 1 ); i = len( s ) if j < 0 else j + 1; continue
        if c == q: return i + 1
        i += 1
    return i

def _skip_paren( s, i ):
    """s[i] == '('; return the index after its matching ')' (quotes, nested $( ), case patterns approximated)."""
    depth = 0
    while i < len( s ):
        c = s[i]
        if c == "\\": i += 2; continue
        if c in "'\"":
            i = _skip_quote( s, i, c ); continue
        if c == "#" and ( i == 0 or s[i - 1] in " \t\n;(" ):
            j = s.find( "\n", i ); i = len( s ) if j < 0 else j; continue
        if c == "(": depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0: return i + 1
        i += 1
    return i

def _skip_brace( s, i ):
    """s[i] == '{' of a ${...}; return the index after the matching '}'."""
    depth = 0
    while i < len( s ):
        c = s[i]
        if c == "\\": i += 2; continue
        if c in "'\"": i = _skip_quote( s, i, c ); continue
        if c == "{": depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0: return i + 1
        i += 1
    return i

def _subs_in( raw, line ):
    """Command substitutions $( ... ) and ` ... ` inside one word (outside single quotes), with their lines."""
    out, i = [], 0
    while i < len( raw ):
        c = raw[i]
        if c == "\\": i += 2; continue
        if c == "'":
            i = _skip_quote( raw, i, "'" ); continue
        if raw.startswith( "$((", i ):
            i = _skip_paren( raw, i + 1 ); continue
        if raw.startswith( "$(", i ):
            j = _skip_paren( raw, i + 1 )
            out.append( ( raw[i + 2:j - 1], line + raw.count( "\n", 0, i ) ) ); i = j; continue
        if c == "`":
            j = raw.find( "`", i + 1 ); j = len( raw ) if j < 0 else j
            out.append( ( raw[i + 1:j], line + raw.count( "\n", 0, i ) ) ); i = j + 1; continue
        if c == '"':
            # descend: substitutions inside double quotes are live
            j = _skip_quote( raw, i, '"' )
            for inner, ln in _subs_in( raw[i + 1:j - 1].replace( "'", " " ), line + raw.count( "\n", 0, i ) ):
                out.append( ( inner, ln ) )
            i = j; continue
        i += 1
    return out

def lex( src, line0=1, bodies=None ):
    """Tokens of src. bodies, when given, collects the line numbers of heredoc BODIES (data, never commands)."""
    toks, i, line, n = [], 0, line0, len( src )
    pending = []                                    # heredoc delimiters waiting for the end of this line
    at_word_start = True
    while i < n:
        c = src[i]
        if c == "\n":
            toks.append( ( "NL", "\n", line ) ); line += 1; i += 1
            for strip, delim in pending:            # heredoc bodies are DATA
                while i < n:
                    j = src.find( "\n", i ); j = n if j < 0 else j
                    body = src[i:j]; i = j + 1
                    if bodies is not None: bodies.add( line )
                    line += 1
                    if ( body.lstrip( "\t" ) if strip else body ) == delim: break
            pending = []
            continue
        if c in " \t": i += 1; continue
        if c == "\\" and i + 1 < n and src[i + 1] == "\n": i += 2; line += 1; continue
        if c == "#":
            j = src.find( "\n", i ); i = n if j < 0 else j; continue
        op = next( ( o for o in OPS if src.startswith( o, i ) ), None ) if c in OPCHARS else None
        if op:
            if op in ( "<<", "<<-" ):
                k = i + len( op )
                while k < n and src[k] in " \t": k += 1
                m = re.match( r"""(['"]?)\\?([A-Za-z_][A-Za-z0-9_]*)\1""", src[k:] )
                if m:
                    pending.append( ( op == "<<-", m.group( 2 ) ) )
                    toks.append( ( "OP", "<<", line ) ); i = k + m.end(); continue
            if op == "(" and src.startswith( "((", i ):  # arithmetic command (( ... ))
                j = src.find( "))", i ); j = n if j < 0 else j + 2
                toks.append( ( "WORD", Word( src[i:j], line, [] ), line ) ); line += src.count( "\n", i, j ); i = j; continue
            toks.append( ( "OP", op, line ) ); i += len( op ); continue
        # a word
        start, sl = i, line
        if src.startswith( "[[", i ) and ( i + 2 >= n or src[i + 2] in " \t" ):
            j = src.find( "]]", i ); j = n if j < 0 else j + 2
            toks.append( ( "WORD", Word( src[i:j], sl, _subs_in( src[i:j], sl ) ), sl ) )
            line += src.count( "\n", i, j ); i = j; continue
        while i < n:
            c = src[i]
            if c in " \t\n": break
            if c == "\\": i += 2; continue
            if c in "'\"": i = _skip_quote( src, i, c ); continue
            if c == "`":
                j = src.find( "`", i + 1 ); i = n if j < 0 else j + 1; continue
            if c == "$" and src.startswith( "$(", i ): i = _skip_paren( src, i + 1 ); continue
            if c == "$" and src.startswith( "${", i ): i = _skip_brace( src, i + 1 ); continue
            if c == "(" and i > start and src[i - 1] == "=":   # array assignment X=( ... )
                i = _skip_paren( src, i ); continue
            if c in OPCHARS: break
            i += 1
        raw = src[start:i]
        line += raw.count( "\n" )
        toks.append( ( "WORD", Word( raw, sl, _subs_in( raw, sl ) ), sl ) )
    toks.append( ( "NL", "\n", line ) )
    return toks

# ── parser ────────────────────────────────────────────────────────────────────────────────────────────────────
class Simple:
    __slots__ = ( "words", "line", "assigns", "redirs" )
    def __init__( self, words, line, assigns, redirs=() ):
        self.words = words      # [ Word ]: the command words, after leading NAME=value assignments
        self.line = line        # 1-based source line of the first word
        self.assigns = assigns  # [ Word ]: the leading NAME=value words
        self.redirs = list( redirs )
class Compound:
    __slots__ = ( "kind", "conds", "bodies", "line", "name" )
    def __init__( self, kind, line, conds=(), bodies=(), name=None ):
        self.kind, self.line, self.conds, self.bodies, self.name = kind, line, list( conds ), list( bodies ), name
# a List is [ AndOr ]; an AndOr is [ ( op_before, Pipeline ) ]; a Pipeline is ( negated, [ cmd ] )

ASSIGN = re.compile( r'^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=' )
REDIR_OPS = { "<", ">", ">>", "&>", "&>>", ">&", "<&", "<>", ">|", "<<<", "<<" }

class Parser:
    def __init__( self, toks ): self.t, self.i = toks, 0
    def peek( self ): return self.t[self.i] if self.i < len( self.t ) else ( "EOF", "", 0 )
    def kw( self, *names ):
        k, v, _ = self.peek()
        return k == "WORD" and v.text in names
    def skip_nl( self ):
        while self.peek()[0] == "NL" or ( self.peek()[0] == "OP" and self.peek()[1] == ";" ): self.i += 1
    def parse_list( self, stops ):
        out = []
        while True:
            self.skip_nl()
            k, v, _ = self.peek()
            if k == "EOF": break
            if k == "WORD" and v.text in stops: break
            if k == "OP" and v in stops: break
            ao = self.parse_andor( stops )
            if ao: out.append( ao )
            else: self.i += 1                       # unparseable token: skip it, never loop
            k, v, _ = self.peek()
            if k == "OP" and v in ( ";", "&" ): self.i += 1
        return out
    def parse_andor( self, stops ):
        ao, op = [], None
        while True:
            p = self.parse_pipeline( stops )
            if p is None: break
            ao.append( ( op, p ) )
            k, v, _ = self.peek()
            if k == "OP" and v in ( "&&", "||" ):
                op = v; self.i += 1
                while self.peek()[0] == "NL": self.i += 1
                continue
            break
        return ao
    def parse_pipeline( self, stops ):
        neg = False
        if self.kw( "!" ): neg = True; self.i += 1
        cmds = []
        while True:
            c = self.parse_command( stops )
            if c is None: break
            cmds.append( c )
            k, v, _ = self.peek()
            if k == "OP" and v in ( "|", "|&" ):
                self.i += 1
                while self.peek()[0] == "NL": self.i += 1
                continue
            break
        return ( neg, cmds ) if cmds else None
    def parse_command( self, stops ):
        k, v, ln = self.peek()
        if k == "EOF": return None
        if k == "WORD" and v.text in stops: return None
        if k == "OP" and v in stops: return None
        if k == "OP" and v == "(":
            self.i += 1
            body = self.parse_list( { ")" } )
            if self.peek()[1] == ")": self.i += 1
            self.redirs(); return Compound( "subshell", ln, bodies=[ body ] )
        if k == "WORD":
            t = v.text
            if t == "{":
                self.i += 1; body = self.parse_list( { "}" } )
                if self.kw( "}" ): self.i += 1
                self.redirs(); return Compound( "group", ln, bodies=[ body ] )
            if t in ( "if", "while", "until" ):
                return self.parse_if_loop( t, ln )
            if t in ( "for", "select" ):
                self.i += 1
                while not ( self.kw( "do" ) or self.peek()[0] == "EOF" ): self.i += 1
                self.i += 1; body = self.parse_list( { "done" } )
                if self.kw( "done" ): self.i += 1
                self.redirs(); return Compound( "for", ln, bodies=[ body ] )
            if t == "case":
                return self.parse_case( ln )
            if t == "function":
                self.i += 1; name = self.peek()[1].text if self.peek()[0] == "WORD" else "?"; self.i += 1
                if self.peek()[1] == "(" : self.i += 2
                while self.peek()[0] == "NL": self.i += 1
                body = self.parse_command( stops )
                return Compound( "func", ln, bodies=[ [ [ ( None, ( False, [ body ] ) ) ] ] if body else [] ], name=name )
            # name() { ... }
            nxt = self.t[self.i + 1] if self.i + 1 < len( self.t ) else None
            nxt2 = self.t[self.i + 2] if self.i + 2 < len( self.t ) else None
            if re.match( r'^[A-Za-z_][\w.:-]*$', t ) and nxt and nxt[1] == "(" and nxt2 and nxt2[1] == ")":
                self.i += 3
                while self.peek()[0] == "NL": self.i += 1
                body = self.parse_command( stops )
                return Compound( "func", ln, bodies=[ [ [ ( None, ( False, [ body ] ) ) ] ] if body else [] ], name=t )
            if t in ( "then", "do", "done", "fi", "else", "elif", "esac", "}" ):
                return None
        return self.parse_simple()
    def redirs( self ):
        while self.peek()[0] == "OP" and self.peek()[1] in REDIR_OPS:
            self.i += 1
            if self.peek()[0] == "WORD": self.i += 1
        while self.peek()[0] == "WORD" and re.match( r'^\d*[<>]', self.peek()[1].text ):
            self.i += 1
    def parse_simple( self ):
        words, assigns, redirs, ln = [], [], [], self.peek()[2]
        while True:
            k, v, _ = self.peek()
            if k == "WORD":
                if not words and ASSIGN.match( v.text ): assigns.append( v )
                else: words.append( v )
                self.i += 1; continue
            if k == "OP" and v in REDIR_OPS:
                self.i += 1
                if self.peek()[0] == "WORD":
                    tw = self.peek()[1]; self.i += 1
                    redirs.append( v + " " + tw.text )
                    # a redirect target's substitutions still run: keep them as ARGUMENT subs
                    if tw.subs: words.append( Word( "", tw.line, tw.subs ) )
                continue
            break
        if not words and not assigns: return None
        return Simple( words, ln, assigns, redirs )
    def parse_if_loop( self, t, ln ):
        self.i += 1
        if t == "if":
            conds, bodies = [], []
            conds.append( self.parse_list( { "then" } ) ); self.i += 1
            bodies.append( self.parse_list( { "elif", "else", "fi" } ) )
            while self.kw( "elif" ):
                self.i += 1; conds.append( self.parse_list( { "then" } ) ); self.i += 1
                bodies.append( self.parse_list( { "elif", "else", "fi" } ) )
            if self.kw( "else" ):
                self.i += 1; bodies.append( self.parse_list( { "fi" } ) )
            if self.kw( "fi" ): self.i += 1
            self.redirs(); return Compound( "if", ln, conds, bodies )
        cond = self.parse_list( { "do" } ); self.i += 1
        body = self.parse_list( { "done" } )
        if self.kw( "done" ): self.i += 1
        self.redirs(); return Compound( "loop", ln, [ cond ], [ body ] )
    def parse_case( self, ln ):
        self.i += 1
        subject = self.peek()[1].text if self.peek()[0] == "WORD" else ""
        while not ( self.kw( "in" ) or self.peek()[0] == "EOF" ): self.i += 1
        self.i += 1; bodies = []
        while True:
            self.skip_nl()
            if self.kw( "esac" ) or self.peek()[0] == "EOF": break
            while not ( ( self.peek()[0] == "OP" and self.peek()[1] == ")" ) or self.peek()[0] == "EOF" ):
                if self.peek()[0] == "WORD": subject += " " + self.peek()[1].text   # patterns: `*" $rc "*)` tests $rc
                self.i += 1
            self.i += 1
            bodies.append( self.parse_list( { ";;", ";&", ";;&", "esac" } ) )
            if self.peek()[0] == "OP" and self.peek()[1] in ( ";;", ";&", ";;&" ): self.i += 1
        if self.kw( "esac" ): self.i += 1
        self.redirs(); return Compound( "case", ln, bodies=bodies, name=subject )

def heredoc_lines( src ):
    """1-based line numbers inside heredoc bodies (their delimiter lines included): data, not commands."""
    out = set(); lex( src, 1, out ); return out

_PARSED = {}
def parse( src, line0=1 ):
    """The statement tree of src. Memoised: the wrapper fixpoint walks a script up to six times, and every walk
    re-parses each $( ... ) it meets; the tree is never mutated after it is built."""
    key = ( src, line0 )
    if key not in _PARSED:
        if len( _PARSED ) > 200000: _PARSED.clear()
        _PARSED[key] = _parse( src, line0 )
    return _PARSED[key]

def _parse( src, line0=1 ):
    p = Parser( lex( src, line0 ) )
    out = []
    while p.peek()[0] != "EOF":
        out += p.parse_list( set() )
        if p.peek()[0] != "EOF": p.i += 1          # a stray closer: skip it
    return out

# ── what is "under test" ──────────────────────────────────────────────────────────────────────────────────────
HARNESSVAR = re.compile( r'^[A-Z_]*HARNESS[A-Z_0-9]*$' )
BINVAR  = re.compile( r'^(?:[A-Z0-9_]*_)?BIN(?:_?[A-Z0-9]*)?$|^RIPWIRE$|^RW$|^[A-Z_]*HARNESS[A-Z_0-9]*$' )
COMPILER = re.compile( r'^(?:c\+\+|g\+\+|clang\+\+|clang|cc|gcc|cl|clang-cl|xcrun|\$\{?CXX\}?|\$\{?CC\}?)$' )

NOTBIN = re.compile( r'^(?:CC|CXX|C|CLANG|GCC|COMPILER|PY|PYTHON|GIT|REALGIT)_BIN$|^[A-Z_]*(?:CC|CXX)_BIN$' )

def unq( s ):
    return re.sub( r"""["']""", "", s )

def binvars( src ):
    out = set()
    for m in re.finditer( r'^\s*(?:local\s+|export\s+|readonly\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$', src, re.M ):
        name, val = m.group( 1 ), m.group( 2 )
        if "$(" in val or "`" in val:
            continue                                # a value that RUNS the binary is its output, not its path
        if NOTBIN.match( name ): continue
        if BINVAR.match( name ) or re.search( r'build[^ ]*/ripwire\b|RIPWIRE_BIN|^"?\$\{?BIN\}?"?$', val ) and not re.search( r'/ripwire/|\.(?:xml|out|txt|log)\b', val ):
            out.add( name )
    return out

def _cmdword( s ):
    """The command word of a simple command, skipping env/timeout/command/exec/nice/time/sudo/stdbuf prefixes."""
    words = [ w.text for w in s.words ]
    k = 0
    while k < len( words ):
        w = unq( words[k] )
        if w in ( "env", "command", "exec", "nice", "time", "nohup", "stdbuf", "caffeinate" ):
            k += 1
            while k < len( words ) and ( words[k].startswith( "-" ) or ASSIGN.match( words[k] ) or ( w == "env" and "=" in unq( words[k] ).split( "/" )[0] ) ):
                if words[k] in ( "-u", "-C", "-S" ) and k + 1 < len( words ): k += 1
                k += 1
            continue
        if w in ( "timeout", "gtimeout" ) or re.match( r'^\$\{?[A-Z_]*TIMEOUT[A-Z_]*\}?$', w ):
            k += 1
            while k < len( words ) and words[k].startswith( "-" ): k += 1
            k += 1; continue                          # the duration
        if ASSIGN.match( words[k] ): k += 1; continue
        if re.match( r'^"?\$\{?(?:@|\*|[A-Za-z_]\w*\[[@*]\])\}?"?$', words[k] ) and k + 1 < len( words ):
            k += 1; continue                          # "${ENV[@]}" "$BIN" / "$@" "$BIN": an env or wrapper prefix
        return words[k], k
    return None, None

# ── the status walk ───────────────────────────────────────────────────────────────────────────────────────────
TRIVIAL_OR = re.compile( r'^\s*(?:true|:)\s*$' )

def _text( node ):
    """Rough source text of a pipeline / command for $? and PIPESTATUS detection."""
    if isinstance( node, Simple ):
        return " ".join( [ w.text for w in node.assigns + node.words ] + node.redirs )
    if isinstance( node, Compound ):
        return " ".join( _list_text( l ) for l in node.conds + node.bodies )
    return ""
def _list_text( lst ):
    return " ; ".join( " ".join( _text( c ) for _op, ( _n, cmds ) in ao for c in cmds ) for ao in lst )

# The text of an and-or list's first pipeline: the one whose `$?` is the previous statement's status. A redirect after a compound
# (`( cd d && "$BIN" . ) 2>/dev/null || { rc=$?; … }`) parses as a pipeline of its own; it is skipped, as the shell applies it to
# the compound before the `||` runs.
_BARE_REDIRECT = re.compile( r'^\s*(?:\d*\s*>+\s*&?\s*\S+\s*|\d*\s*<\s*\S+\s*)+$' )
def _first_pipeline_text( ao ):
    for m in range( len( ao ) ):
        t = _list_text( [ ao[m:m + 1] ] )
        if not _BARE_REDIRECT.match( t ): return t
    return ""

_COMPARED = {}

class Walker:
    def __init__( self, src, extra ):
        self.src, self.extra = src, list( extra )
        self.vars = binvars( src )
        self.targets = []                          # fnmatch patterns of compiled harnesses
        self.errexit = False; self.pipefail = False; self.subst_depth = 0
        self.calls = []                            # ( line, cmd, consumer, via )
        self.funcs = {}                            # name -> Compound
        self.wrappers = {}                         # name -> ( line, cmd ) of the call whose status IS the function's
        if src not in _COMPARED: _COMPARED.clear(); _COMPARED[src] = self._compared_names( parse( src ) )
        self.compared = _COMPARED[src]
    @staticmethod
    def _compared_names( tree ):
        """Variables, and rc-file suffixes, that some TEST in the script reads: `[ ]`, `[[ ]]`, `test`, `(( ))`, a
        `case` subject, `exit`/`return`, or a bare argument handed to a function the script defines (a checker
        such as `expect "C4" "$C4RC" 1`). A variable printed inside a message string is NOT a test of it."""
        funcs, rcfuncs, names = set(), {}, set()
        def simples( lst, fn=None ):
            for ao in lst:
                for _op, ( _n, cmds ) in ao:
                    for c in cmds:
                        if isinstance( c, Simple ):
                            yield c, fn
                            for w in c.words + c.assigns:
                                for inner, ln in w.subs: yield from simples( parse( inner, ln ), fn )
                        elif isinstance( c, Compound ):
                            if c.kind == "func": funcs.add( c.name )
                            if c.kind == "case" and c.name: yield Simple( [ Word( "case", c.line, [] ), Word( c.name, c.line, [] ) ], c.line, [] ), fn
                            for l in c.conds + c.bodies: yield from simples( l, c.name if c.kind == "func" else fn )
        allc = list( simples( tree ) )
        for c, fn in allc:
            if fn and c.words and unq( c.words[0].text ) == "cat":
                m = re.search( r'\.([A-Za-z0-9_]+)"?$', c.words[-1].text )
                if m: rcfuncs[fn] = m.group( 1 )
        VREF = re.compile( r'\$\{?([A-Za-z_][A-Za-z0-9_]*)' )
        for c, _fn in allc:
            if not c.words: continue
            cw = unq( c.words[0].text )
            text = " ".join( w.text for w in c.words )
            if cw in ( "[", "test", "case", "exit", "return" ) or cw.startswith( "[[" ) or cw.startswith( "((" ):
                names.update( VREF.findall( text ) )
                if cw.startswith( "((" ): names.update( re.findall( r'\b([A-Za-z_][A-Za-z0-9_]*)\b', text ) )
                for suf in re.findall( r'\bcat\s+[^)]*?\.([A-Za-z0-9_]+)"?\s*\)', text ): names.add( "file:" + suf )
                for fn, suf in rcfuncs.items():
                    if re.search( r'\$\(\s*%s\b' % re.escape( fn ), text ): names.add( "file:" + suf )
            elif cw in funcs:
                for w in c.words[1:]:
                    m = re.match( r'^"?\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?"?$', w.text )
                    if m: names.add( m.group( 1 ) )
                    elif w.text.startswith( "'" ): names.update( VREF.findall( w.text ) )   # code the checker evals
        # an alias `rcFull=$rcDef` hands the status on: a test of the alias is a test of the original
        alias = {}
        for c, _fn in allc:
            for a in c.assigns:
                m = re.match( r'^([A-Za-z_][A-Za-z0-9_]*)="?\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?"?$', a.text )
                if m: alias.setdefault( m.group( 2 ), set() ).add( m.group( 1 ) )
                m = re.match( r'^([A-Za-z_][A-Za-z0-9_]*)="?\$\(\s*cat\s+[^)]*?\.([A-Za-z0-9_]+)"?\s*\)"?$', a.text )
                if m: alias.setdefault( "file:" + m.group( 2 ), set() ).add( m.group( 1 ) )   # rc1=$( cat "$E/e1.rc" )
        for _round in range( 4 ):
            for src_, dsts in alias.items():
                if dsts & names: names.add( src_ )
        return names
    def under_test( self, word ):
        """None, or the kind of command `word` names (see Call.kind). A compiled target wins over a name."""
        w = unq( word )
        if any( w == p or fnmatch.fnmatchcase( w, p ) for p in self.targets ): return "harness"
        if "harness" in w.lower() and ( "/" in w or "$" in w ): return "harness"   # a path, not a function name
        m = re.match( r'^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$', w )
        if m and not NOTBIN.match( m.group( 1 ) ) and ( m.group( 1 ) in self.vars or BINVAR.match( m.group( 1 ) ) ):
            return "harness" if HARNESSVAR.match( m.group( 1 ) ) else "ripwire"
        if re.search( r'(?:^|/)build[^/ ]*/ripwire$', w ): return "ripwire"
        if any( w == p or fnmatch.fnmatchcase( w, p ) for p in self.extra ): return "extra"
        return None
    def collect_targets( self, lst ):
        for ao in lst:
            for _op, ( _n, cmds ) in ao:
                for c in cmds:
                    if isinstance( c, Simple ):
                        cw, k = _cmdword( c )
                        if cw is not None and COMPILER.match( unq( cw ) ):
                            ws = [ unq( w.text ) for w in c.words ]
                            for j, w in enumerate( ws ):
                                tgt = ws[j + 1] if w == "-o" and j + 1 < len( ws ) else ( w[2:] if w.startswith( "-o" ) and len( w ) > 2 else None )
                                if tgt and not re.search( r'\.(?:o|obj|ll|s|bc|pch|gch|d)$|^/dev/null$', tgt ):
                                    pat = re.sub( r'\$\{?[A-Za-z_0-9@*#?]+\}?', "*", tgt )
                                    # a target spelled only by variables ("$GOLD", "$WORK/$name") is matched literally:
                                    # as a glob its basename would be `*` and match every command in the script
                                    self.targets.append( tgt if not re.search( r'[^*/]', pat.rsplit( "/", 1 )[-1] ) else pat )
                        for w in c.words + c.assigns:
                            for inner, ln in w.subs: self.collect_targets( parse( inner, ln ) )
                    elif isinstance( c, Compound ):
                        for l in c.conds + c.bodies: self.collect_targets( l )
    # consumer: ( verdict, how ) or ( "fn", name )
    def walk_list( self, lst, consumer, toplevel=False ):
        for k, ao in enumerate( lst ):
            last = k == len( lst ) - 1
            if last and consumer is not None:
                self.walk_andor( ao, consumer )
                continue
            if last and toplevel:
                self.walk_andor( ao, ( "checked", "exit status (the script's last statement)" ) ); continue
            nxt = _list_text( [ lst[k + 1] ] ) if not last else ""
            cap = self.capture( nxt, _first_pipeline_text( lst[k + 1] ) if not last else "" )
            self.walk_andor( ao, cap if cap else ( "errexit", None ) )
    def capture( self, nxt, first ):
        head = nxt.split( " ; " )[0]
        if "PIPESTATUS" in head: return ( "checked", "PIPESTATUS read" )
        if "$?" not in head and "${?}" not in head: return None
        m = re.match( r'\s*(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)=["]?\$\??\??', head )
        if m and re.match( r'\s*(?:local\s+)?[A-Za-z_][A-Za-z0-9_]*="?\$\{?\?', head ):
            v = m.group( 1 )
            return ( "checked", "%s=$? compared" % v ) if v in self.compared else ( "unchecked", "%s=$? captured, never compared" % v )
        m = re.search( r'echo\s+"?\$\??"?\s*>+\s*"?[^"\s]*?\.([A-Za-z0-9_]+)"?', head )
        if m:
            return ( "checked", "rc file .%s compared" % m.group( 1 ) ) if "file:" + m.group( 1 ) in self.compared else ( "unchecked", "rc file .%s written, never compared" % m.group( 1 ) )
        # a status only PRINTED in a message is not tested (CodeRabbit #626 4548924371): `echo "exit $?"`, `printf 'rc=%s\n' $?`
        # to the terminal. Everything else that reads $? next -- a test, `echo $?` alone as the output (rc=$( cmd; echo $? )),
        # $? written to a file, $? handed to a checker function, $? printed into a $( ) the gate captures (OUT="$( cmd; echo
        # "rc=$?" )") -- counts as the next statement testing it.
        # CodeRabbit #633 4557724184: only the FIRST pipeline of the next and-or list sees the call's status (in `[ -s o ] || no
        # "rc=$?"` the `$?` is the test's), and a redirect to &1, &2 or /dev/null prints, it writes no file.
        # `first` is the next and-or list's first pipeline; the rendered text spells `>&2` as `>& 2`.
        if "$?" not in first and "${?}" not in first: return None
        to_file = re.search( r'(?<![&>])>+(?!\s*&\s*[12]\b)(?!\s*/dev/null\b)\s*\S', first )
        if re.match( r'\s*(?:echo|printf)\b', first ) and not to_file and not self.subst_depth \
                and not re.match( r'\s*(?:echo|printf\s+(?:\'%s\'|"%s"|%s))\s+"?\$\{?\?\}?"?\s*$', first ):
            return ( "unchecked", "$? printed, not tested" )
        return ( "checked", "$? tested by the next statement" )
    def walk_andor( self, ao, consumer ):
        n = len( ao )
        for j, ( _op, pipe ) in enumerate( ao ):
            ors = [ ao[m] for m in range( j + 1, n ) if ao[m][0] == "||" ]
            if ors:
                rhs = _list_text( [ [ ors[0] ] ] )
                c = ( "unchecked", "discarded by || %s" % rhs.strip() ) if TRIVIAL_OR.match( rhs ) else \
                    ( "checked", "&& .. || X" if any( ao[m][0] == "&&" for m in range( j + 1, n ) ) and ao[j + 1][0] == "&&" else "|| X" )
            elif j < n - 1:
                # followed only by && links: a failure here IS the list's status, but errexit never fires here
                c = ( "unchecked", "left of && (errexit does not fire)" ) if consumer[0] == "errexit" else consumer
            else:
                c = consumer
            self.walk_pipeline( pipe, c )
    def walk_pipeline( self, pipe, consumer ):
        neg, cmds = pipe
        if neg and consumer[0] == "errexit": consumer = ( "unchecked", "negated (errexit does not fire)" )
        for j, c in enumerate( cmds ):
            if j < len( cmds ) - 1 and not self.pipefail:
                cc = ( "unchecked", "status discarded in a pipe (no pipefail)" )
            else:
                cc = consumer
            self.walk_cmd( c, cc )
    def resolve( self, consumer ):
        if consumer[0] == "errexit":
            return ( "checked", "set -e" ) if self.errexit else ( "unchecked", "output only" )
        return consumer
    def walk_cmd( self, c, consumer ):
        if isinstance( c, Compound ):
            if c.kind == "func":
                self.funcs[c.name] = c
                saved = ( self.errexit, self.pipefail )
                for l in c.bodies: self.walk_list( l, ( "fn", c.name ) )
                self.errexit, self.pipefail = saved
                return
            for l in c.conds: self.walk_list( l, ( "checked", "if" ) if c.kind == "if" else ( "checked", "while/until" ) )
            for l in c.bodies:
                self.walk_list( l, consumer if c.kind in ( "if", "case", "subshell", "group", "loop", "for" ) else ( "errexit", None ) )
            return
        words = [ w.text for w in c.words ]
        if words and unq( words[0] ) == "set":
            for a in words[1:]:
                a2 = unq( a )
                if re.match( r'^-[a-zA-Z]*e', a2 ): self.errexit = True
                if re.match( r'^\+[a-zA-Z]*e', a2 ): self.errexit = False
            if "pipefail" in " ".join( words ):
                self.pipefail = any( re.match( r'^-[a-z]*o$', unq( a ) ) for a in words[1:] ) and "+o" not in words
            for j, a in enumerate( words[1:], 1 ):
                if unq( a ) == "-o" and j + 1 < len( words ) and unq( words[j + 1] ) == "errexit": self.errexit = True
                if unq( a ) == "+o" and j + 1 < len( words ) and unq( words[j + 1] ) == "errexit": self.errexit = False
        cw, k = _cmdword( c )
        # substitutions: an assignment-only command carries its $( )'s status; anywhere else it is discarded
        assign_only = cw is None and not any( w.text == "" for w in c.words )
        local_assign = words and unq( words[0] ) in ( "local", "export", "declare", "readonly", "typeset" )
        for w in c.assigns + c.words:
            for inner, ln in w.subs:
                if assign_only and w in c.assigns: sc = consumer
                elif local_assign: sc = ( "unchecked", "%s x=$(...) (status masked)" % unq( words[0] ) )
                else: sc = ( "unchecked", "$(...) argument (status discarded)" )
                self.subst_depth += 1
                self.walk_list( parse( inner, ln ), sc )
                self.subst_depth -= 1
        if cw is None: return
        # errexit resolves HERE, against set -e as it stands at this call (CodeRabbit #626 4548924380), not at the end
        if consumer[0] == "errexit": consumer = self.resolve( consumer )
        kind = self.under_test( cw )
        if kind:
            self.calls.append( ( c.line, cw, consumer, kind ) )
        elif unq( cw ) in self.funcs or unq( cw ) in self.wrappers:
            self.calls.append( ( c.line, unq( cw ), consumer, "wrapper" ) )

def scan( text, extra=() ):
    tree = parse( text )
    w = Walker( text, extra )
    w.collect_targets( tree )
    # fixpoint over wrappers: a function whose status IS an under-test command's status is itself under test
    wrappers = set()
    for _round in range( 6 ):
        w2 = Walker( text, extra ); w2.targets = w.targets
        w2.funcs = { n: None for n in wrappers }
        w2.walk_list( tree, None, toplevel=True )
        new = set( wrappers )
        for line, cmd, cons, via in w2.calls:
            if cons[0] == "fn" and ( via != "wrapper" or cmd in wrappers ): new.add( cons[1] )
        if new == wrappers: break
        wrappers = new
    out = []
    for line, cmd, cons, via in w2.calls:
        if via == "wrapper" and cmd not in wrappers: continue
        if cons[0] == "fn":
            if cons[1] in wrappers: continue       # reported at the wrapper's call sites instead
            cons = ( "unchecked", "output only" )
        v, how = w2.resolve( cons )
        out.append( Call( line, "%s()" % cmd if via == "wrapper" else cmd, v, how, via ) )
    return sorted( out )

if __name__ == "__main__":
    rc = 0
    for f in sys.argv[1:]:
        try:
            src = open( f, encoding="utf-8", errors="surrogateescape" ).read()
        except OSError as e:
            print( "%s:0\terror\t%s\t-" % ( f, e ) ); rc = 2; continue
        for c in scan( src ):
            print( "%s:%d\t%s\t%s\t%s" % ( f, c.line, c.verdict, c.how, c.cmd ) )
    sys.exit( rc )
