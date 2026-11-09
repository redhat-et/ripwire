### Added — Smali (`.smali`)

A `.smali` file is indexed from a vendored ABI-14 `tree-sitter-smali` grammar (tree-sitter-grammars, `fdfa6a1febc43c7467aa7e937b87b607956f2346`). A class is `Lcom/example/A;`. A method is that class, `->`, and the signature, including `<init>` and `<clinit>`, so a definition and an invoke share one spelling and the existing by-name resolver binds the edge. A second class that defines the same bare signature does not take the edge. An invoke whose class is not in the corpus stays unresolved. `test/smalicheck.sh` is the gate.

The crawl keys on the extension, so apktool's `smali/`, `smali_classes2/`, `smali_classes3/` and any other directory of `.smali` files are indexed. Fields, `const-string`, switches, annotations, `.super` and `.implements` are not captured. There is no import directive that names a file, so Smali stays file-edge unmeasured, the same as Java and Kotlin: the call graph is the structural view. It does not share a language with Java or Kotlin.

On the grammar's own test corpus, 22 of 22 examples indexed with `degraded_parse=0`. That is the grammar's tests, not a large public sample, and it measures parser completion, not how many invokes bind. `kParserVer` 303 → 304 (the mirror in `src/quality.h` is 304 too; 303 is the Protocol Buffers row already on main); an older cache rebuilds once. The cache format stays 50.
