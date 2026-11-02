### Fixed — a Ruby call reaches the method a class body's Rails declaration generates

`workspace.bills` (a `has_many :bills`), `Workspace.active` (a `scope :active`), `workspace.email` (a `delegate :email, to:
:owner`) and a bare `bills` in one of Workspace's methods found nothing in the class's lookup: the source never spells those
methods as `def`. They were refused as external when the tree held a namesake elsewhere, left undefined when it held
none, and a class that wrote `delegate` bound its calls to self by name alone. A declaration written at a class body's level,
or in a concern's `included do`, now mints the methods Rails generates from it, as definitions of the class or concern:
associations (`has_many`, `has_one`, `belongs_to`, `has_and_belongs_to_many`: the reader and writer, and a singular one's
`build_`, `create_`, `reload_`, `reset_`), `scope`, `delegate` (with `prefix:`), an enum's attribute, predicate, bang and
value scopes (with `prefix:` / `suffix:`), `has_one_attached` and `has_many_attached`, `accepts_nested_attributes_for`,
`alias_method`, `alias` and `define_method( :name )` (`src/ruby_generated.h`). Such a definition is one only a lookup that
reached its class finds — a call to self, a receiver the code builds, a class object, a relation — and only when no written
method in that lookup answers: Rails includes its generated association and attribute modules as the class inherits, before
the body's own `include`s, so a written `def` in the class or a module it includes comes first. It never joins the name
tier: an untyped `record.bills` is decided as before. `test/rubygeneratedcheck.sh`; `test/rubyreachcheck.sh`'s floor (b)
arms for a delegating class now assert its delegated names are its own.

Measured with `--pin-census` on two Rails applications and the ActiveRecord and ActiveSupport `lib/` trees, Ruby call sites,
the receiver-evidence change vs this one (node ids dropped, since the new definitions renumber them):

| | refused → bound | none → bound | retargeted | bound → none or external |
| --- | ---: | ---: | ---: | ---: |
| application A | 1,441 | 732 | 132 | 0 |
| application B | 1,083 | 1,680 | 349 | 0 |
| ActiveRecord `lib/` | 9 | 61 | 104 | 0 |
| ActiveSupport `lib/` | 1 | 31 | 8 | 0 |

Every changed site now binds a generated method. Sampled by hand, 20 per category on each corpus and every site of a smaller
one, all were right: an association or scope of the receiver's class on both applications, a `delegate` list or an `alias`
in the calling class or one it inherits or includes on ActiveRecord and ActiveSupport. The retargets had bound a same-named
method of another class (one sharing the caller's class name in another namespace, a spec file's top-level `def`) or a
reopened `Object`'s. One sampled edge splits over two classes sharing a final segment, the right one among them (a FactoryBot
build keys its class by final segment, as before). One reaches an association beneath a concern's Sorbet abstract stub of the
same name, which sorbet-runtime's wrapper calls through to with `super`. `--quality-delta`, `langidentitycheck` (0 DIFF over
1,160 argv; its ratchet falls to 332, the byName skip reading a langfacts column now) and ASan on both applications and
ActiveRecord are clean. The generated definitions are `sec` symbols and take no row of the default map; its `est_tokens`
moved +0.6% and +1.1% on the applications and +1.3% on ActiveSupport as ranks shifted.

Not done, each pinned in the gate: an association's or a scope's value is not typed (`workspace.bills.first.total`,
`Workspace.active.recent`); a collection's `<singular>_ids` and an enum's pluralized class method are not minted (they need the
inflector); a declaration inside `with_options` is not read; a superclass's written method answers before the class's own
generated one; and `delegate`, `alias_method` and `define_method`, which Ruby defines on the class itself, answer after a
written method of a module the class includes. Forwardable's `def_delegator(s)` and `db/schema.rb` columns are not read as
methods yet (no corpus uses the first; the second is the next round).
