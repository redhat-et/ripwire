defmodule Toolbox do
  @doc "Named by both import filters below."
  def flatten(x), do: x
  @doc "Named by the `only:` list and left alone by the later `except:`."
  def keyfind(x), do: x
  @doc "Never imported into Narrowed: absent from its `only:` list."
  def never(x), do: x
end

defmodule Narrowed do
  import Toolbox, only: [flatten: 1, keyfind: 1]
  import Toolbox, except: [flatten: 1]
  @doc "The later `except:` subtracts from the `only:` list in force; it does not replace it. never/1 is not imported here."
  def c_never(x), do: never(x)
  @doc "Imported by `only:`, then removed by `except:`."
  def c_flatten(x), do: flatten(x)
  @doc "Imported by `only:` and untouched by `except:`."
  def c_keyfind(x), do: keyfind(x)
end

defmodule Widened do
  import Toolbox, except: [flatten: 1]
  @doc "Control: an `except:` with no earlier import of the module applies to every function, so never/1 IS imported."
  def c_never(x), do: never(x)
  @doc "Control: the excluded flatten/1 stays out."
  def c_flatten(x), do: flatten(x)
end
