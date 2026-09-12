defmodule Page do
  use Web
  @doc "A call delivered by `use`: no alias, import or receiver names text/2 here."
  def index(conn), do: text(conn, "hi")
  @doc "A call no definition in the tree spells at all."
  def missing(conn), do: nowhere(conn)
end
