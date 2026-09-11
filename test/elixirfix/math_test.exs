defmodule Sample.MathTest do
  @moduledoc "Exercise literal ExUnit test discovery and its call edge to square/1."
  use ExUnit.Case, async: true

  test "squares" do
    assert Sample.Math.square(3) == 9
  end
end
