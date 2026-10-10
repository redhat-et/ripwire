# false-binding arm (definitions only): an UNTYPED receiver calls a method spelled like a
# COLUMN-ONLY name (`ref`, the `id: false` table's one column, schema.rb). Nothing proves the
# receiver is that table's model, so the call is a use of the name and never the column's caller.
# Without buildGraph's Section-Ruby byName skip this site binds to the column by name alone.
class UnrelatedClient
  def fetch( response )
    response.ref
  end
end
