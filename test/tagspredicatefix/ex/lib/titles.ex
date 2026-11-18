defmodule Titles do
  use ExUnit.Case

  # A literal title names an ExUnit test; `def` with a string where its name belongs names nothing (invalid
  # Elixir). Before #355 the C++ keyword table also accepted the second as a function named "not a name"/0.
  test "a literal title" do
    :ok
  end

  def "not a name" do
    1
  end
end
