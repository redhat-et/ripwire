defmodule Shell do
  @doc "Before the nested declaration no alias is in force: Ring.Core is the top-level module in ring.ex."
  def early(), do: Ring.Core.spin()
  defmodule Ring.Core do
    @doc "Declared as Shell.Ring.Core; from here on the first segment `Ring` means Shell.Ring inside Shell."
    def spin(), do: :nested
  end
  @doc "After the declaration Ring.Core names Shell.Ring.Core, not the top-level module."
  def late(), do: Ring.Core.spin()
  @doc "Control: the full name names the nested module before and after."
  def full(), do: Shell.Ring.Core.spin()
  defmodule Plain do
    @doc "Control: an undotted nested module, aliased as a whole."
    def spin(), do: :plain
  end
  @doc "Control: the undotted nested module resolves through its implicit alias."
  def plain(), do: Plain.spin()
end
