defprotocol Shape do
  def area(x)
end

defmodule Disc do
  defstruct []
end

defmodule Box do
  defstruct []
end

defimpl Shape, for: [Disc, Box] do
  alias __MODULE__, as: Current
  @doc "`Current` is `__MODULE__` under another name: each implementation calls its OWN measure/1."
  def area(x), do: Current.measure(x)
  @doc "Control: the literal `__MODULE__` receiver resolves per implementation."
  def own(x), do: __MODULE__.measure(x)
  @doc "Control: a literal module name stays literal — both implementations call Shape.Disc.measure/1."
  def literal(x), do: Shape.Disc.measure(x)
  def measure(x), do: x
end
