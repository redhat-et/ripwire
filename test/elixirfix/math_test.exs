defmodule Sample.MathTest do
  use ExUnit.Case, async: true

  test "squares" do
    assert Sample.Math.square(3) == 9
  end
end
