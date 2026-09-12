defmodule Work do
  @doc "The function whose arity the edit-check arm changes."
  def run(x), do: x
  @doc "A same-module bare caller of run/1, and the exact-name --for target."
  def generate_app(x), do: run(x)
end
