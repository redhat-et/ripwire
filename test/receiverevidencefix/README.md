# receiverevidencefix — calls bound by name alone (test/receiverevidencecheck.sh)

Each directory is its own root (the gate indexes one at a time). Every root holds member calls (or, in an
implicit-receiver language, bare calls) whose receiver nothing proves to be the class of the same-named
definition beside them, plus near-miss calls whose receiver IS proven and whose edges must stay plain.

- `js/` — `ctx.onerror()` (plain and optional-chained) in the file that defines `Application.onerror`; a
  constructor-assigned `this.bucket` (a `Schemas`) beside the caller's own `listSchemas`; WeakMap `.set/.get`
  beside same-file accessors; Promise `.then` beside `Reply.prototype.then`; a stream's `.on` beside a test
  double; an outside router's `.all` and a Set's `.delete` beside instance shorthands; URLSearchParams `.append`
  beside `Response.append`; a `done` parameter beside another file's closure; `context.handler()` beside a free
  `handler`; an object-literal module's `this.ctx.get()` beside its own `get` (the true target is the request
  delegate's `get`); an alias `const onerror = ctx.onerror` and a destructured `const { onerror } = ctx`; the
  globals `Reflect.get` / `Atomics.add` beside in-repo `get` / `add`. Kept: `this.onerror()`, a same-file bare call, a relative module receiver, a closure called in its
  own function, `new Application()` / `new Schemas()` deciding between same-named methods, `super.listSchemas()`,
  a class-name receiver `Application.create()`, a relative module bound to the name `Reflect`, `new Reply().send()`;
  `reply.send()` / `reply.code()` on a parameter are the name-only true edges the gate wants kept AND marked.
  `serve` (via respond) and `both` (via direct and respondWith) give `--impact` its d=2 rows.
- `ts/` — a loop variable over `Router<T>[]` beside `SmartRouter.add`; WHATWG `headers.get()` beside
  `Context.get` / `Cache.get`; the global `Atomics.add`; `Date#getTime` beside an in-repo `Clock.getTime`, and the
  global `Response` beside an in-repo `Response` class. Kept: an annotated parameter, construction through an import alias, a
  constructed local.
- `py/` (src layout) — dict/set/list/str receivers in files that import `Styles` / `Content`; an argument's
  `.animate`; an asyncio handle's `.cancel`; an outside package's parser `.write`; `self._send` holding a passed
  callable beside a nested `_send`; non-self receivers in `App`'s own file (`screen` is a property);
  `from json import dumps as stringify` beside in-repo `stringify` / `dumps`; `append` on a list literal; `read = os.read` and
  `feed = parser.feed` called from a nested def; `add_widget = widgets.append` beside a nested `add_widget`.
  Kept: `self.update()`, a constructor-assigned field through the class cone, a typed parameter, construction,
  an import alias, an imported function beside same-named methods, `cls.default_rules()`, `Styles.copy(x)`, a
  constructed `Content`'s `append`, the
  `XTermParser.feed` the alias really reaches; `pump.call_later()` on a parameter is kept and marked.
- `go/` — an item's typed `text util.Chars` field, a typed parameter, a typed local through an aliased import
  and an embedded field, all beside `Merger.Get/Length` in the caller's package; an outside `tcell.Screen`'s
  `Size` and an outside value's `Runes` beside a renderer's methods; a field / local named `log` of an outside type
  beside the in-repo `log.Errorf`; exec's `Cmd.Output` beside an in-repo `Output` (with `fmt.Errorf` and
  `strings.Split`). Kept: `m := &Merger{}`, the method receiver itself, a real import of the in-repo log package,
  a constructed in-repo `Tool`.
- `java/ kt/ cs/ cpp/ swift/ rb/` — a bare call inside a class whose base is outside the tree (or whose name
  comes from an outside import) beside an unrelated class's method of that name. Kept: own members (private
  too), an in-repo superclass's member (and Java `super.flush()`), a free / top-level function, a Ruby top-level
  def; a Ruby included module's method is resolved or hedged (the contract only: Ruby's own lookup is separate work).

Sides of a class lookup (js/lib/sides.js, ts/src/sides.ts, kt/src/app/Sides.kt): a call on the class object reaches
its static (companion) members, a call on an instance the others. A fallback hook only after a miss
(py/src/tui/ghost.py): `__getattr__` leaves a defined member's call resolved.

The names are paraphrases of graded false rows; the code is minimal and is never built.
- `scope/{java,cs,kt,swift,ts,js,py,go}` — review B4: Tank and Barrel both define `spill`, and the class's field (or the
  function's outer parameter / local) named `tank` is a Tank. Each method binds `tank` again — a loop, lambda, catch,
  resource, pattern, `case`, `out var`, destructuring, `if`/`guard`/`while let`, `with`/`except`/walrus/`match`, a Go
  range / if / type-switch variable, a reassignment — and calls `tank.spill()`, which must never prove Tank's spill;
  `nestedBlock` / `lambdaOutside` / `blockOutside` call it past the block that hid it, which must never prove Barrel's. A
  generic whose type parameter is spelled `Tank` (method and class, a field of that type) must never prove class Tank.
  Kept: the field itself, a typed local, a typed loop / lambda variable's own class, a typed parameter.
- `superroot/{py,js,ts,go,java,kt,swift,cs,cpp,rb}` — CR 5469474915: `Panel` extends `Base`; `Base` and `Widget` both
  define `render`. `typed` binds a local spelled `base` (C#: `super`) to a `Widget`, `untyped` to a value nothing types
  (Python and Go also a local `super`), then calls `render` on it: never Base's render through the bases-only lookup.
  Kept: `super.render()`, Python `super().render()`, Go's promoted `p.Render()`, the typed local's own class. C#
  `base.Render()` is visible only (no C# tree reads `base` as a receiver root yet).
