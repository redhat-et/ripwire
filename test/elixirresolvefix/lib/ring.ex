defmodule Ring.Core do
  @doc "The top-level decoy: what `Ring.Core.spin()` inside Shell names BEFORE the nested declaration, and never after it."
  def spin(), do: :top_level
end
