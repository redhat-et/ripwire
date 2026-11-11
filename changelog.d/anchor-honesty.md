### Fixed — a short "what does X call" `--for` question keeps its source anchor, and "anchor has no source definition" is printed only when true

When a name-exact task spells an identifier that has a source definition (`what does Injector.loadProvider call`, `what does Model.save call`, `where concurrent.futures.ThreadPoolExecutor is defined`):

- the words `call`, `calls`, `invoke` and `invokes` and the question words leave the route, and `route=` names them (`; dropped: call(15-defs)`). A test-only `call` no longer vetoes the anchor into a ranked word list, and a source `invoke` elsewhere no longer anchors the answer and heads it with a callers block for the wrong symbol;
- an anchor that the whole-name index bound to a non-source definition (a Sphinx `.. method:: Model.save` section, a `.github/` copy) is re-bound to the source definition, so the body and the callers are the code's, not the docs page's;
- the identifier's source definition vouches for the route, so the "anchor has no source definition" note no longer fires beside one;
- WH-WORD-GUARD: the question words (`where`, `what`, `which`, `how` and the other question leads) no longer score as whole names, so `Icon.where` no longer heads `where concurrent.futures.ThreadPoolExecutor is defined`.

A task whose identifier has no source definition keeps every word and every note. CLI `--for` and MCP `for` share the rule. Cards ANCHOR-HONESTY and WH-WORD-GUARD from the Fable ideas pass; `test/anchorhonestycheck.sh` pins them and their negatives.
