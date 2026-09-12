defmodule Channel do
  defstruct [:topic]
  @doc "The decoy a variable read mistaken for a bare call would bind to."
  def socket(), do: :decoy
  @doc "A variable bound on the RIGHT of `=` in a function head, then read in the body."
  def join(%Channel{} = socket, _payload), do: socket
  @doc "The same binding shape inside a case clause pattern."
  def pick(x) do
    case x do
      %Channel{} = socket -> socket
      _ -> nil
    end
  end
  @doc "The same binding shape inside a with generator pattern."
  def unwrap(x) do
    with {:ok, %Channel{} = socket} <- x do
      socket
    end
  end
  @doc "Control: the right side of a body match IS a call, and the edge must stay."
  def rhs(), do: socket = socket()
  @doc "Control: a bare identifier on the right of a body match is a zero-arity call, and the edge must stay."
  def bare_rhs(), do: socket = socket
end
