defmodule Client do
  import Work
  @doc "An imported bare caller of run/1."
  def go(x), do: run(x)
  @doc "A module-qualified caller of run/1."
  def remote(x), do: Work.run(x)
end
