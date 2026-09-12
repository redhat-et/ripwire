defmodule Outer do
  defmodule Inner do
    @doc "A nested module another file names through `alias`."
    def render(x), do: x
  end
end

defmodule Attrs.A do
  @limit 3
  @doc "Reads its own module's attribute."
  def limit(), do: @limit
end

defmodule Attrs.B do
  @limit 4
  @doc "Reads a same-named attribute of a different module; the qualifier keeps the two apart."
  def limit(), do: @limit
end
