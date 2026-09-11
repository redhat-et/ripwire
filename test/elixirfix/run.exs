defmodule Sample.Run do
  @moduledoc "Exercise remote calls and negative definition-capture candidates."
  @doc "Exercise a remote call using a literal module name."
  def run(x), do: Sample.Math.square(x)
  @doc "Exercise an ordinary nested call that must not create a definition."
  def build(x), do: ordinary(untouched(x))
  @doc "Contain quoted definitions that must not become indexed symbols."
  def quoted do
    quote do
      def phantom(x), do: nonexistent(x)
    end
  end
end
