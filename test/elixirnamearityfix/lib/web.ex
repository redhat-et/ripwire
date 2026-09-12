defmodule Web do
  @moduledoc "A `use` target whose __using__ injects an import the static resolver never expands."
  defmacro __using__(_opts) do
    quote do
      import Web.Helpers
    end
  end
end

defmodule Web.Helpers do
  @doc "Reachable only through `use Web` from a module that never imports this one lexically."
  def text(conn, body), do: {conn, body}
end
