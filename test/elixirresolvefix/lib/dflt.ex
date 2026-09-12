defmodule Dflt do
  @doc "Evaluated only when a caller omits the argument of f/1 or g/1."
  def default(), do: 1
  @doc "A bodyless head: the one place the default expression lives."
  def f(x \\ default())
  def f(0), do: :zero
  def f(x), do: x
  @doc "Omits the argument: default/0 runs on this path."
  def caller(), do: f()
  @doc "Control: supplies the argument, so default/0 never runs on this path."
  def caller_explicit(), do: f(1)
  @doc "Control: a head WITH a body keeps its default expression and its callers on one symbol."
  def g(x \\ default()), do: x
  def caller_g(), do: g()
end
