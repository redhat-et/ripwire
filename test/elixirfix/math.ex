defmodule Sample.Math do
  @moduledoc "Exercise supported Elixir definitions, guards, defaults, and call-edge shapes."
  @spec square(integer()) :: integer()
  @doc "Return a square so callers can exercise a shared call target."
  def square(x), do: x * x
  @doc "Exercise a guarded definition with repeated calls to one target."
  def twice(x) when is_integer(x), do: square(x) + square(x)
  # Private call target used to verify no-parentheses definition bodies.
  defp secret(), do: 7
  @doc "Exercise a zero-argument definition without parentheses."
  def answer, do: secret()
  @doc "Return quoted syntax so extraction can exclude quoted call sites."
  defmacro literal(x), do: quote(do: unquote(x))
  @doc "Exercise a guard definition with word-form boolean operators."
  defguard positive(x) when is_integer(x) and x > 0
  @doc "Exercise parenthesized and bare call targets in a pipeline."
  def pipeline(x), do: x |> square() |> twice
  @doc "Exercise a keyword body containing one conditional branch."
  def branchy(x), do: if(x > 0, do: square(x), else: 0)
  @doc "Provide a call target for an ordinary nested-call negative fixture."
  def untouched(x), do: x
end
