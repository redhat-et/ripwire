defmodule Sample.Math do
  @spec square(integer()) :: integer()
  def square(x), do: x * x
  def twice(x) when is_integer(x), do: square(x) + square(x)
  defp secret(), do: 7
  def answer, do: secret()
  defmacro literal(x), do: quote(do: unquote(x))
  defguard positive(x) when is_integer(x) and x > 0
  def pipeline(x), do: x |> square() |> twice
  def branchy(x), do: if(x > 0, do: square(x), else: 0)
  def untouched(x), do: x
end
