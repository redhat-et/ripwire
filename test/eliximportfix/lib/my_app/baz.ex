defmodule MyApp.Baz do
  defmacro __using__(_opts), do: quote(do: :ok)
end
