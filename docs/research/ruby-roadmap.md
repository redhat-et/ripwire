# Ruby roadmap: what is still wrong, measured, and the order to fix it

**Status: PLAN, 2026-10-31, against `main` at `bf412fb6` (0.6.9 plus train 42b).** Every number below was produced by
running the binary built from that commit; the method is in [Corpora and method](#corpora-and-method). This is
not a claim surface. A number here is local evidence for a round that has not been written yet, and nothing in it
is quoted on `README.md`.

Since September, ripwire has learned to resolve a Ruby call by Ruby's own method lookup: bare calls, mixins, typed and class-object receivers, RSpec targets, declared callbacks and `send`. What it still gets
wrong is concentrated in one place. **The single-definition tier binds a framework method to the one in-tree
method that shares its name.** On app B that is 12,460 verified wrong edges on three names, 16% of every Ruby
call the graph binds there.

---

## 1. Where Ruby stands

**On `main`** (the full ledger is in `CHANGELOG.md`; each line names the PR that landed it):

- Definitions: scope and setters (#47), the class-level attribute DSL as `Var` symbols (#310), `db/schema.rb`
  columns as `Section` definitions (#339), `.rake` and `.jbuilder` files (#373).
- Structure: constant references, receivers, arguments and `rescue` classes as dependency edges (#57, #65, #139),
  `class Child < Parent` as an inheritance edge (#325), mixins on the shared base-relations path (#400, #401, #412).
- Calls: a constant receiver pins the call (#267), RSpec's `described_class` (#338), and #373's method lookup
  (self, mixins, typed receivers, class objects, RSpec targets and matcher chains, declared callbacks, `send`).
- Name answers: one ordering tower for every multi-definition name (#432); the Ruby DSL capture lane extracted into
  `src/ingest_ruby.h` (#396).

**Open, and touching Ruby:** #440 (mpapis, the language-first tower and `@lang` selectors; name answers, not call
edges), #471 (lennix1337, slice 6c: per-language receiver and comment columns in `src/langfacts.h`), #426 (conka8,
#355: the tags pass evaluates string predicates).

**Already fixed, re-measured:** the September note that #338's `described_class` path was cubic in nesting depth
(400 nested groups took 11 s) no longer holds. The same 400-deep fixture indexes in 0.26 s.

## 2. The baseline

`--pin-census` on four corpora, Ruby call sites only (`bench/ruby/census.py`). A census row is a site the resolver
decided. The **unique** tier is the one that bound a site because only one in-tree definition carries the name.

| corpus | Ruby files | Ruby rows | receiver-rule | unique | split | external |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ActiveRecord 7.2.3.2 `lib/` | 395 | 13,113 | 6,851 | 3,792 (28.9%) | 1,304 | 1,166 |
| ActiveSupport 7.2.3.2 `lib/` | 281 | 4,331 | 2,044 | 951 (22.0%) | 380 | 955 |
| Rails app A | 3,618 | 77,651 | 21,214 | 15,842 (20.4%) | 1,250 | 39,341 |
| Rails app B | 3,555 | 149,421 | 24,854 | 49,589 (33.2%) | 2,151 | 72,827 |

Rows are a floor on call sites: a name with no in-tree definition writes no row. App B is a live repository and has
nearly doubled since the September measurements (1,895 Ruby files then), so its numbers are only comparable to a
run on the same day.

### 2.1 Verified wrong: receiver-less calls in example groups

Every site below was read through its target: the definition's kind and scope cannot be in an example group's
method lookup.

| corpus | name | sites (unique tier) | what Ruby runs | what the graph binds |
| --- | --- | ---: | --- | --- |
| app B | `create` | 7,075 | FactoryBot's, through `config.include FactoryBot::Syntax::Methods` | an instance method of an application service |
| app B | `allow` | 3,748 | rspec-mocks' builder | a module's singleton method (`def self.allow`) |
| app B | `describe` | 1,637 | RSpec's nested example group | an instance method of an application service |

The `to` that follows `allow( x )` is already answered as RSpec's: #373's RSpec targets type it, and all 34,604 of
app B's `to` census rows are `external=`. The builder call itself is not: it falls to the name tier because an example
group's `self` has no lookup.

### 2.2 Suspect, not yet sampled: framework methods on untyped receivers

Each name below has exactly one in-tree definition, and that definition absorbs every untyped call to it.

| corpus | names (sites in the unique tier) | the one definition lives in |
| --- | --- | --- |
| app B | `where` 1,307, `pluck` 1,077, `blank?` 1,127, `present?` 1,035 | a mailer-preview stub (`where`, `pluck`), an application service (`blank?`, `present?`) |
| app A | `where` 569, `blank?` 442, `now` 344 | a model, a search-index class, a `lib/` value class |
| app A | `click` 549, all from feature specs | a controller action (Capybara's `click` is the one Ruby runs) |

These are suspects because nothing has been sampled yet. Round 0 samples them before Round 2 is written.

**Status, 2026-11-01: sampled.** On app B the `where`, `pluck`, `blank?` and `present?` bindings were wrong 20 of 20; on
app A the `where`, `blank?` and `now` ones 18 of 20. Round 2 acts on them.

## 3. Rules every round follows

1. **The gate is written first and shown red on `main`.** A wrong answer the round does not fix gets a known-gap arm
   that asserts today's behaviour and names the round that will flip it. When that arm fails, the gap has moved:
   flip it, never delete it.
2. **Byte-identical on every other language.** `test/langidentitycheck.sh BASE HEAD --langs=ruby` plus one
   non-Ruby repository. A difference outside Ruby is waived only by an `--intended` row that names the arm pinning it.
3. **Common stays common** (`CONTRIBUTING.md` §3). New lookup code goes in a Ruby-owned file behind a named hook, a
   difference in value goes into a table, and no round adds a `Lang::Ruby` comparison to a shared file. The
   `langidentitycheck` ratchet may only fall. Today `src/graph.h` has 27 `Lang::Ruby` mentions,
   `src/ingest_relations.h` 13, `src/resolve.h` and `src/ingest_binds.h` 9 each.
4. **Measured on all four corpora**, before and after built back to back (app B moves daily), with 20 sampled sites
   per changed category, read by hand.
5. **Client corpora publish aggregates and framework names only.** No application class, module, path or commit
   subject from app A or B appears in a gate fixture, a comment, a CHANGELOG fragment or a commit message. #373
   needed a history rewrite after eight rounds of drift; this rule is cheaper.
6. **The train owns the shared pins.** A round keeps its own honest one-step `kParserVer` bump and does not chase
   `main`'s number, the gate count or `test/qschemetrip.hash`.
7. **One round, one PR, claimed first** in an issue, as the slices of #358 were claimed.

## 4. The rounds

### R0: instruments (S; no behaviour change)

- `bench/ruby/census.py`, committed with this plan: the Ruby slice of `--pin-census`, mechanism mix and top names,
  aggregates only.
- A sampling protocol: for each changed category, 20 sites drawn by a fixed seed, each labelled right, wrong or
  open-lookup by reading the target. Run it once now on §2.2's suspects, to turn them into verified rows or drop
  them.
- **Ruby's row of the language feature matrix** (`CONTRIBUTING.md` §3, "Feature families"): one 3–10 line fixture per
  Ruby form, family by family, each with the one call that answers the matrix's four questions. Most fixtures exist
  in the 19 `test/ruby*check.sh` gates; this collects them and finds the forms nobody pinned.
- `docs/LIMITS.md` has no Ruby row. The floors #373 pinned, (a) to (k), become rows through `docs/limits_build.py`,
  so a reader can see what Ruby does not do without reading gate headers.

### R1: an example group's `self` has a lookup (M; the largest verified mass)

**Status, 2026-10-31: done on `feat/ruby-rails-lookup`** (kParserVer placeholder 273, gate
`test/rubygroupselfcheck.sh`, `changelog.d/ruby-example-group-self.md`). Measured against `main`: app B 15,302 bound sites
became `external=` (12,301 of them the three names of §2.1) and 14,226 declined ones did too; app A 874 and 19,311. Gains,
where a call now binds the `config.include` helper Ruby runs: 548 on B, 55 on A. Sampled 20 of 20 losses right on each app,
the gains 10 of 10 and 8 of 8; ActiveRecord and ActiveSupport byte-identical; `langidentitycheck` 0 DIFF. Measuring found
four rules the first cut lacked, each now an arm. A def written inside ANOTHER spec file's group is not this group's
(`organization`, 1,990 sites, had bound one other spec file's `def`). A shared group's defs are everyone's. Another language's
function is out of reach (app A's JavaScript `create` had turned 5,714 declines into `unresolved=`). A helper spec mixes in
the module it describes. Floors kept: `type:` filters are not read, a `let` is not an indexed definition, and a
`FactoryBot.define` block is still read by name.

**Ruby's rule.** Inside `RSpec.describe … do`, the block is class-evaluated on a new `RSpec::Core::ExampleGroup`
subclass; an `it`, `before` or `let` block runs on an instance of it. That instance looks a method up in this order:
`def`s and `let`s written in the group and its parents, modules mixed in by `config.include M` (optionally filtered by
`type:` metadata), RSpec's own modules, then `Object`, where a top-level `def` lives.

**Shape.**

- Ingest: read `RSpec.configure { |c| c.include M, type: :t }` as an inclusion fact, and give each spec file its
  type the way `infer_spec_type_from_file_location!` does (`spec/requests/` is `:request`). Both are new captures
  in `queries/ruby/tags.scm` where the vocabulary allows, `src/ingest_ruby.h` otherwise.
- Resolve: a receiver-less call in an example group walks that ancestry. An in-tree hit binds. A miss that reaches an
  out-of-tree module (FactoryBot, Capybara, rspec-mocks) is `external=`, the same answer #373 gives a class whose
  lookup leaves the tree. The tree-wide namesake is never consulted. A nested bare `describe`, `context`, `it` or
  `let` is RSpec's.
- `kRspecTargets` keeps its job: typing the value a builder returns. The builder call itself now resolves through the
  group's lookup.

**Expected, to be confirmed by the gate:** app B −12,460 on the three names of §2.1; app A's feature-spec `click`
(549) if Capybara's DSL is included for `type: :feature`. A minitest class (`< ActiveSupport::TestCase`) is an ordinary
class; R1 measures whether #373's class lookup already answers it.

### R2: framework methods on untyped receivers (M)

**Status, 2026-11-02: done on `feat/ruby-rails-lookup`** (no parser bump: the gate reads the tree at
graph time; gate `test/rubyframeworknamescheck.sh`, `changelog.d/ruby-framework-names.md`). Two tables generated from the
Rails 8.1.4 gems by one recorded command, in `src/externalnames.h`: ActiveSupport's `Object` extensions and `TimeZone`
(47 names) and ActiveRecord's record, relation and model-class methods (893). The evidence is the tree's, not a
`Gemfile.lock`: a constant written under a Rails namespace, with the framework's home constant never opened, so the Rails
gems keep their maps. Measured against R1 with `--pin-census`: app B lost 6,153 bound sites (6,087 declined, 66 external),
app A 3,005 (2,943 and 62), ActiveRecord's `lib/` 214 (192 and 22, all ActiveSupport names its own code uses);
ActiveSupport's census is identical. Sampled: the removed edges were wrong 20 of 20 on B and 19 of 20 on A, among generic
names 15 of 15 and 14 of 15, the new externals 12 of 12, ActiveRecord's 15 of 15. Measuring found one rule the first cut
lacked, now an arm: a name only a framework table holds never narrows a split to the file's own class (`column.name` had
bound `Migration#name`, 4 of 5 sampled on ActiveRecord). The stated cost: an object whose class the file never names loses
its edge until R4 types it (the two true edges among the 70 sampled were such).

**Ruby's rule.** An untyped receiver can be any object, so a call to `where` on it reaches the in-tree `where` only
if the receiver is an instance of that class. When the name is also a method Ruby or Rails defines on the classes the
receiver most plausibly is (`Object`, `ActiveRecord::Relation`, `Time`), the honest answer is a hedge, not an edge.

**Shape.** The mechanism exists: `BuiltinMethodGate` in `src/graph.h` reads `externalnames::kRubyBuiltinMethodNames`,
233 names generated from `Hash`, `Array` and `String` by a recorded `ruby -e` command. R2 adds framework tables
generated the same way: ActiveSupport's `Object` core extensions (`blank?`, `present?`, `try`), `ActiveRecord::Relation`
and `QueryMethods` (`where`, `pluck`, `find_by`, `reload`), and `Time`/`Date` class methods. Each table applies only
with evidence in the tree, such as a `Gemfile.lock` naming the gem or a class inheriting `ActiveRecord::Base`, so a
plain-Ruby gem keeps today's answers. Tables are data with their generating command recorded, never a branch.

**Expected:** app B ~4,546 and app A ~1,355 bound sites become hedged, if R0's sample confirms §2.2. Recall cost: an
in-tree class that really is the receiver loses its edge when nothing types the receiver. R4 is the recovery path,
and the gate pins both directions.

### R3: methods Ruby generates (M; recall)

Ruby code defines methods the source never spells as `def`:

- `delegate :name, to: :owner`, `def_delegator(s)`, `alias_method`, `alias`, `define_method( :literal )`;
- Rails associations (`has_many :posts` defines `posts`, `posts=`, `build_post` and others), `scope :active`,
  `enum status: { … }`, and the columns #339 already reads from `schema.rb`, as readers on their model.

An October attempt minted delegate definitions as `Var` and made receiver calls bind to them (388 wrong on app A,
reverted before #373 opened). So these definitions are **visible only to a lookup that already reached their class**: self, a typed
receiver, a class object. They never join the name tier. #373's typed-receiver round refused 625 (app A) and 1,370 (app B)
calls as `external=`, rightly, and the sampled refusals were mostly associations and columns: methods the tree never
defines. R0 re-measures that on today's corpora.

### R4: more evidence for a receiver's type (M)

**Status, 2026-11-02: done on `feat/ruby-rails-lookup`** (kParserVer placeholder 275, gate
`test/rubyrecvevidencecheck.sh`, `changelog.d/ruby-receiver-evidence.md`). Sized first with Prism over both applications,
joined to the census: the four sources below cover about 4% (app A) and 3% (app B) of the calls R2 left declined. Method
parameters (2,931 and 2,321 declined sites), association chains (5,626 and 6,512) and lets FactoryBot does not build (1,988
and 3,734) hold most of the rest. Neither application declares Sorbet signatures (17 `sig` blocks on A, none on B), so the
optional source was dropped. R2's losses were already sampled wrong 20 of 20 and 19 of 20, so "recovering R2's recall cost"
was a small target. What R4 adds is typed receivers: an ivar every assignment builds alike, a method whose value is one
thing, and a relation chain answered from its model's class side. Measured against R2: app A 117 calls newly bound, 21
retargeted, 61 bound to external and 803 declines to external; app B 38, 17, 19 and 871; ActiveRecord's `lib/` 29 newly
bound and 20 retargeted. Every sampled category was right (20 of 20 or all of a smaller one). Measuring found one rule the
first cut lacked: a relation answers ActiveRecord::Relation's own methods (`find_each`) before its class side. Floors: one
class body in one file, block parameters, and locals copied from a typed ivar. R3's associations and scopes are the next
recall, now that a relation and a typed instance can reach them.

#373 types a receiver from a local constructor, a FactoryBot `let` and RSpec builders. The next sources, in measured
order (R0 sizes them first):

- instance variables assigned once from a constructor or finder (`@client = Client.new` in `initialize`, `@x ||= …`);
- a method whose every return is one constructor (`def client = Client.new( … )`);
- ActiveRecord finders: `Model.find`/`find_by`/`first` return a `Model`; `where` returns a relation of it;
- optional and only on evidence: Sorbet `sig { returns( T ) }`, `T.let`, RBS files.

R4 is what recovers R2's recall cost, and it carries the same trust guards #373 used (one class tree-wide, the
class in the tree, no in-tree redefinition of the constructor).

### R5: files Ruby lives in (S, plus one decision that is not ours)

- **Extensionless Ruby** (`Gemfile`, `Rakefile`, `config.ru`, `*.gemspec`, `Guardfile`) is not crawled. The crawl
  maps languages by extension only (`kLangTable`), and no language is crawled by its whole filename yet. That
  makes this a shared crawl mechanism, a filename row in `kLangTable`, not a Ruby special case.
- **ERB** (147 and 128 files on apps A and B, counted 2026-10-02) needs a grammar. Vendoring
  `tree-sitter-embedded-template` is a G3 decision for the maintainers; an issue with the measured file counts is the
  right way to ask. HAML and Slim have no grammar of usable quality and stay disclosed as skipped.

### R6: the Ruby lookup moves out of `src/graph.h` (M; byte-identical)

`src/graph.h` is the repo's first hotspot (17,167 lines, churn 518). It carries about 1,800 lines of Ruby lookup:
`RubySelfReach`, `RubyTypedReceivers`, `RubyClassObjects`, the side lookup and `RubyTopSelf`, from line 3,831 to
5,612. Most of it is ours. It is an algorithm, so by `CONTRIBUTING.md`'s rule it belongs behind a hook in a
Ruby-owned file, as `src/elixir_resolve.h` holds Elixir's.

A pure move, byte-identical on every language, makes every later round land outside the hottest file. It also keeps
`--quality-delta`'s short-horizon-churn gate off the Ruby lookup, which gated edits to `buildRubyTypedReceivers`
during #373. **Ordering decision:** the move touches the file every open train touches. It goes first only if the
maintainers agree in an issue. Otherwise R1 and R2 put their new code straight into `src/ruby_resolve.h` and R6
moves the rest later.

### R7: common-code slices Ruby can lead (S–M each; claimed on the slice's issue)

- **1a, `require`/`require_relative`/`autoload` onto `@import.path`** (#358): the table lists Ruby as M because
  `autoload` carries more meaning. That deletes `rubyRequireTarget`'s arm in `directiveTargetOf`.
- **Ruby's name tables into `tags.scm`** once #426 lands (#355): `kRubyConstantDirectives`, `kRubyMixinDirectives`,
  `kRubyAttrFamilyNames`, `kRubyVisibilityNames`, `kRubyCallbackMacros`, `kRubyDelegationCalls`. These are keyword
  lists, which is exactly what the predicates are for.
- **Ruby's `captureTagsFacts` branches into the hook table** (#374, slice 3a).
- **Ruby's receiver predicates into `langfacts` columns** after #471 lands (slice 6c). Wait for it rather than
  racing it.

## 5. Order, and why

| order | round | effect | size | waits on |
| --- | --- | --- | --- | --- |
| 1 | R0 instruments | turns §2.2 into verified rows or drops them; Ruby gets a `LIMITS.md` and a matrix row | S | nothing |
| 2 | R6 lookup out of `graph.h` | later rounds land outside the hottest file | M | a maintainer yes; otherwise new code goes to the new file and R6 moves to 6 |
| 3 | R1 example-group self | −12,460 verified wrong edges on app B | M | R0 |
| 4 | R2 framework names | ~5,900 suspect edges hedged on A and B | M | R0's sample |
| 5 | R4 receiver evidence | recovers R2's recall cost | M | R2 |
| 6 | R3 generated methods | recall: associations, scopes, delegates | M | R4's typed receivers make them reachable |
| 7 | R5 files | Gemfile and friends; the ERB ask | S | a G3 decision for ERB |
| any | R7 slices | Ruby's shared-file debt falls | S–M each | #426, #471 |

Precision comes before recall on purpose. A new definition reachable from a wrong edge spreads the wrong edge.
`--impact`, `--dead-code` and `--for`'s callers hop all read the same graph.

## 6. Coordination

- **mpapis** owns the name-answer tower (#432, #440). R1 to R4 change call edges, not name answers, so they should
  not collide. Any round that touches `resolveFocus` or the tower goes through them first.
- **lennix1337's #471** is moving receiver predicates into `src/langfacts.h`. R2 reads them, so R2 rebases after it.
- **Maintainers:** slice 6a (refusing an unplaced module qualifier) is theirs, and R6 needs their yes. An umbrella
  issue listing these rounds, opened before R1, lets everyone see the lane is taken.

## 7. Out of scope, and decisions that are not ours

- **Other languages.** #373's review asked whether this lookup carries to Python's MRO, JS prototypes, Go embedding
  or Jest's `expect`. Left aside on 2026-10-04 and still aside. R2's evidence-gated framework tables and R1's
  "a test framework's DSL is a mixin" are the parts that would carry, if that decision changes.
- **Runtime metaprogramming** beyond literal symbols (`define_method( name )` with a computed name,
  `method_missing` bodies, `instance_eval` of a string) stays an open lookup, disclosed and never guessed.
- **ERB grammar vendoring** (R5) and **R6's ordering** are maintainer decisions.

## Corpora and method

| label | path on the measuring machine | notes |
| --- | --- | --- |
| ActiveRecord | `activerecord-7.2.3.2/lib` (Ruby 4.0.6 gems) | the corpus of the September tables |
| ActiveSupport | `activesupport-7.2.3.2/lib` (Ruby 4.0.6 gems) | |
| app A | a private Rails application, 3,618 Ruby files | aggregates and framework names only |
| app B | a private Rails application, 3,555 Ruby files, live | aggregates only; re-measure both sides on the same day |

```bash
ripwire <corpus> --no-cache --pin-census=OUT.tsv >/dev/null
python3 -I bench/ruby/census.py OUT.tsv 20
```

Binary: `ripwire 0.6.9 (dev, AppleClang 21.0.0, built_from=bf412fb6a)`, a plain dev build (no `NDEBUG`).
Runs: 2026-10-30 and 2026-10-31, one run per corpus. §2.1's verdicts were made by reading each name's target
definition and the spec helper's `config.include` lines. §2.2 has no verdict yet.
