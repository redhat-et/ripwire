# Custom `--lint-rules` — writing your own AST-smell rules

Reference for `ctxpack-fresh-eyes` step 4 (AST smells). Load this when you're about to write a rule of your
own rather than rely on the built-ins.

`ctxpack <dir> --lint-rules=DIR` loads YAML ast-grep-style rules from `DIR` and runs them alongside (or
instead of) the built-ins; findings share the same `<f rule= sev= p= …>message</f>` shape as `--lint`.

Minimal working rule (verified against `test/lintrulesfix/`):
```yaml
# rules/no-printf.yml
- id: no-printf
  language: cpp
  severity: warn
  message: use LOG() instead of printf
  query: |
    (call_expression function: (identifier) @fn (#match? @fn "^printf$")) @hit
```

`query:` is a tree-sitter s-expression; the `@hit` capture is the finding's location (an `@fn`/predicate pair
like above narrows it). Three combinators refine a hit by AST containment, composed with `and` when a key
repeats:

- **`inside:`** — keep the hit only if it sits inside a node matching this query (e.g. scope it to function
  bodies: `inside: |` + `(function_definition) @a`).
- **`not-inside:`** — drop the hit if it sits inside a matching node (e.g. exclude a `skip*`-named scope).
- **`not-matches:`** — drop the hit if a companion capture matches a query (e.g. exclude `new Pool<T>` while
  keeping other `new` expressions).

Failure handling is per-rule, not per-run: a rule whose `query`/combinator doesn't compile, or a malformed
YAML file, alerts to stderr (file name + line for YAML) and is **skipped** — sibling rules still load and the
run still exits 0. `--lint-rules=DIR` on a directory that loads **zero** rules exits 1 with a clear message
(empty dir, or every rule malformed). Output is deterministic (byte-identical run-to-run) and xmllint-clean,
same as every other verb.
