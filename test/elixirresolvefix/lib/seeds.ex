defmodule Seeds do
  @doc "An underscore-named function: a legal name a named capture may spell."
  def _seed(), do: 1
  @doc "A bare named capture of the underscore function."
  def by_capture(), do: &_seed/0
  @doc "Control: the module-qualified capture."
  def by_remote_capture(), do: &Seeds._seed/0
  @doc "Control: the plain call."
  def by_call(), do: _seed()
  @doc "Control: an underscore-named parameter read is a variable, never a call of _seed/0."
  def by_parameter(_seed), do: _seed
end
