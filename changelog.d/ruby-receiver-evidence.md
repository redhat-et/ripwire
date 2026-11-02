### Fixed — a Ruby call on an instance variable, a memoised method or an Active Record relation answers from what built it

`@client.fetch`, `connection.close` (a `def connection; @connection ||= ApiClient.new; end`) and `User.where( … ).recent`
reached the name tier with their spelling as the only evidence, so they split over every class's `fetch`, declined, or bound
an unrelated namesake. Ruby's lookup on what built the receiver now answers them, as it already did for a local built by
`Client.new` or a finder. An instance variable is typed when every assignment to it in an instance method of its class body
builds the same thing (`C.new`, a finder, a relation, `@x ||= …`, another typed ivar or method). An `attr_writer` or
`attr_accessor` of the name, `@x += …`, a multiple assignment, a rescued exception, or anything inside a block whose self is
another object (`instance_eval` and kin) leaves it untyped. A bare-word receiver in an instance method is a call to self's
method. It is typed when the class body defines that method once, directly, with no parameters, no `return` and no rescue,
and its value builds one thing (an endless `def store = Store.new`, a memoising `@x ||= C.new`), or when an `attr_reader`
reads a typed ivar. `C.where( … )`, `C.all`, `C.order( … )` and chains of such links build a relation of C. A call on a
relation answers from C's class side (a scope or class method written as `def self.m`). A name ActiveRecord::Relation answers
itself (`find_each`, `count`, `map`: 347 names generated from the Rails 8.1.4 gem, `src/externalnames.h`) is Active Record's,
outside the tree. A finder at the end of a chain builds an instance. A class whose lookup defines any link of the chain
(`def self.where`) is left as before. `test/rubyrecvevidencecheck.sh`; `test/rubytypedrecvcheck.sh`'s floor (d) arms for
instance variables and return values now assert the gap is closed.

Measured with `--pin-census` on two Rails applications and the ActiveRecord and ActiveSupport `lib/` trees, Ruby call sites,
the framework-names change vs this one:

| | newly bound | retargeted | bound → external | declined → external |
| --- | ---: | ---: | ---: | ---: |
| application A | 117 | 21 | 61 | 803 |
| application B | 38 | 17 | 19 | 871 |
| ActiveRecord `lib/` | 29 | 20 | 1 | 0 |
| ActiveSupport `lib/` | 2 | 1 | 1 | 0 |

Sampled by hand, the new edges were right 20 of 20 on each application and on ActiveRecord. The retargets were right 21 of
21, 17 of 17 and 20 of 20: each moved from an unrelated namesake to the receiver's class. One of them narrowed to three test
doubles sharing a name, the right class among them. The edges lost to external were wrong before, 20 of 20 and 19 of 19: an
association, a column, an enum predicate or Active Record's own query method, not the in-tree namesake they had bound. The
declines now refused as external were 20 of 20 Active Record's or Enumerable's methods on a relation (`count`, `pluck`,
`where`, `find_each`). Measuring found one rule the first cut lacked, now an arm: a relation answers its own `find_each`
even where the model defines `def self.find_each` (4 sites on one application). Before choosing these sources the round sized
every receiver shape on both applications. These four cover about 4% and 3% of the calls declined there. Method parameters,
association chains and non-FactoryBot `let`s hold most of the rest, and neither application declares Sorbet signatures.

Known floors, each pinned in the gate: an ivar or a method is read from its own class body in its own file, so a subclass or
a reopening elsewhere that assigns it differently is not seen. A block parameter is not typed, even over a relation. A local
assigned from a typed ivar or method is not typed.
