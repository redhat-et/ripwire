### Fixed — a Ruby call reaches the db/schema.rb column its model reads

`parcel.label` on a receiver built as `Parcel.find( id )`, a bare `label` in one of Parcel's methods and `self.weight` found
nothing in Parcel's lookup: the column `t.string "label"` of `create_table "parcels"` is the reader Rails generates on every
Parcel, and #339 made it a definition with no call edges, leaving edges "behind an evidence rule (a receiver shown to be the
owning model)". That evidence now exists (the receiver typing and the generated-method lookup of the two changes above), so
a rendered schema's column answers its model's instance lookup as a reader, exactly as a declaration's generated method does:
only once a lookup reached the class, and only when no written method and no declaration's method of the name answers (a
written `def status`, an enum's `status`). A model's table is the one its class body names with `self.table_name =`; else,
for a class written `< ApplicationRecord`, its name underscored and pluralized by the regular English rules (+s, +es after
s/x/z/ch/sh, a consonant's y to ies). An STI subclass reads its base class's table through the same lookup walk. The name
tier is unchanged: an untyped `response.code` still binds no column, and 200 `name` columns still damp nothing
(`test/rubyschemacheck.sh`'s definitions-only arms for a typed receiver now assert the column, the rest are unchanged).
`test/rubycolumncheck.sh`.

Measured with `--pin-census` on two Rails applications and the ActiveRecord and ActiveSupport `lib/` trees, Ruby call sites,
the generated-methods change vs this one (node ids dropped, as above):

| | refused → bound | none → bound | retargeted | bound → none or external |
| --- | ---: | ---: | ---: | ---: |
| application A | 0 | 0 | 0 | 0 |
| application B | 2,712 | 2,170 | 123 | 0 |
| ActiveRecord `lib/` | 0 | 0 | 0 | 0 |
| ActiveSupport `lib/` | 0 | 0 | 0 | 0 |

Application A keeps its schema in `structure.sql` and the two `lib/` trees have no rendered schema: their census and default
map are byte-identical. On application B every changed site binds exactly one column. Sampled by hand, 20 per category, all
were right: the column of the receiver's own model's table, including a model whose `self.table_name` names a legacy table.
The retargets had bound a same-named method of an unrelated class (a mailer preview's mock, an importer, a spec file's
top-level `def`), or a concern the model does not include. A first cut that let a receiver known only by name (a FactoryBot
build of a class whose ancestor is one of several `Base` models) reach every same-named model's column split 3,177 sites;
those columns now answer nothing, which is floor (f). The default map's `est_tokens` moved −0.07% on application B and no
column takes a row. `--quality-delta`, `langidentitycheck` and ASan on application B are clean.

Not done, each pinned in the gate: a column's writer, predicate and dirty-tracking affixes; Rails' irregular, uncountable
and other special plurals (a class they name reads no table); a class under a module defining `table_name_prefix` or nested
in a model (whose table Rails prefixes); a subclass of an abstract intermediate class; a class written directly
`< ActiveRecord::Base`, whose inherit reference keeps only `Base`; and a receiver known only by a name several models share.
