### Fixed — a served body starts where its declaration starts: `export`, a decorator, `template<…>` and an attribute run are no longer cut off

Several grammars put the start of a declaration outside the node a symbol's span starts at: an outer node wraps it, or its attributes sit in front of it as siblings. Every body a verb printed started at the inner node, so the first line of the text came back without its prefix:

| written | was served as |
|---|---|
| `export function f() {}` | `function f() {}` |
| `@cache` / `def f(): ...` | `def f(): ...` (a different function) |
| `template<typename T>` / `T f( T a )` | `T f( T a )` (does not compile) |
| `#[inline]` / `fn f() {}` | `fn f() {}` |

Measured on 103 language × form rows over 22 languages, 45 lost their first line or its leading keyword: TypeScript, TSX and JavaScript `export` (function, default, async, class, interface, type, enum, const arrow), TypeScript `declare` and decorators, Python decorators (single, stacked, class, `@property`, `@staticmethod`), C++ and CUDA `template<…>` (function, class, member, nested, alias) and one-declaration `extern "C"`, Rust `#[…]` attributes, Ruby `private def` and a macro-wrapped `def`, Dart and GDScript annotations, Lua `local f = function`. Java, Kotlin, C#, Swift and PHP annotations and modifiers, Rust `pub`, Go, Objective-C, Bash and Clojure were already whole and are unchanged.

A body element (`--expand`, the `--for` body fold and auto bodies, `--pack-task`, `--from-trace`, `--exemplar`, the MCP `fetch_body`) now starts at the declaration's first byte. **The symbol does not move:** `l=` is still the line of its name, signature rows, ranking and every analysis are byte-for-byte what they were, and no cache is invalidated. The start is found when the body is cut, by re-parsing that one file with the grammar the index used; when the re-parse has no node at the symbol's start, the body is what it was before.

The edit verbs splice the span `--expand` prints, so they move with it. `--replace-symbol-body` replaces the wrapper too (a body replaced with the text it was served leaves the file byte-identical). **`--insert-before-symbol` on a decorated definition used to put the payload between the decorators and the function**, which silently re-attached them to the inserted code; it now lands above them.

On the 89 GA1 DEV questions (page 1 of the default `--for`), 9 of the 114 served bodies carry a wrapper, all of them TypeScript `export`; the body rung goes from 18 to 21 with no cell lost, at +63 bytes over the 89 answers. Gate: `test/wrapperprefixcheck.sh`.
