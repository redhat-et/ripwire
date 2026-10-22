defmodule Attrs do
  # #not-any-of? on @_attribute: a metadata attribute defines nothing; an ordinary one is a value.
  @moduledoc "Module attributes."
  @limit 10
  @enforce_keys [:id]
  @doc "Uses the ordinary attribute."
  @spec within(integer) :: boolean
  def within(x), do: x < @limit
  @type t :: integer
end
