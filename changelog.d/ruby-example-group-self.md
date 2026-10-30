### Fixed — a Ruby call inside an RSpec example group no longer binds the one application method that shares its name

Inside `RSpec.describe … do`, `create( :user )` is FactoryBot's, `allow( x )` is rspec-mocks', and a nested `describe` is
RSpec's. A spec file's top level had no `self`, so such a receiver-less call fell to the name tier and bound whichever in-tree
method carried the name: an application service's `create`, a module's `def self.allow`, a service's `describe`. A group's
block now has a `self`, and Ruby's lookup for it answers the call. That lookup reaches the defs written in that file's
groups, a shared group's defs, top-level defs and a reopened `Object`. It also reaches the modules the groups mix in
(`config.include M` in `RSpec.configure`, `include M` in a group, and the helper a helper spec describes) and their
ancestors. Any other in-tree class's method, a def written inside another file's group, and another language's function are
out of reach. A call left with nothing is refused as `external=`. A block that hands `self` elsewhere (`instance_eval`,
`Class.new` and their kin) keeps the old reading. `test/rubygroupselfcheck.sh`.

Measured with `--pin-census` on two Rails applications, Ruby call sites, main vs this change:

| | bound | external | unresolved | declined |
| --- | ---: | ---: | ---: | ---: |
| application A, before | 39,594 | 39,749 | 7,869 | 39,263 |
| application A, after | 38,755 | 60,138 | 3,939 | 23,643 |
| application B, before | 76,631 | 72,827 | 450 | 47,770 |
| application B, after | 61,358 | 102,687 | 450 | 33,183 |

On application B, 15,302 bound sites became `external=`. 12,301 of them are `create`, `allow` and `describe`, and each
was read through its target. On application A, 874 became `external=`; 509 of those bound `response` to a `spec/support`
module that nothing includes. Sampled by hand: 20 of 20 losses right on each application. The gains, where a call now
binds the `config.include` helper Ruby runs (548 on B, 55 on A), were sampled at 10 of 10 and 8 of 8. ActiveRecord and
ActiveSupport `lib/` maps are byte-identical.

Known floors, each pinned in the gate: a spec file's top level outside every group, and a `FactoryBot.define` block, keep
the old reading. `config.include M, type: :request` mixes M into every group, because the `type:` filter is not read. A
`let` is not an indexed definition, so a call to one is `external=` rather than an edge.
