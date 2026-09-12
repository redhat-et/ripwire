defmodule User do
  alias Outer.Inner
  @doc "Names the nested module through its alias."
  def show(x), do: Inner.render(x)
end
