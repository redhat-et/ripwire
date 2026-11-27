defmodule Heads do
  # #any-of? on @_keyword: each definition keyword names its function.
  def kept_def(x), do: x
  defp kept_defp(x), do: x
  defmacro kept_macro(x), do: x
  defguard kept_guard(x) when is_integer(x)
  defdelegate kept_delegate(x), to: Other

  # An ordinary call whose first argument is a call has the same shape as a definition head. It defines nothing.
  def caller(x) do
    ordinary(not_a_def(x))
    kept_def(x)
  end

  # #not-any-of? on @name: a generated head names nothing static.
  for name <- [:alpha, :beta] do
    def unquote(name)(), do: 1
    def unquote(name), do: 2
  end
end
