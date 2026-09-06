defmodule Sample.Run do
  def run(x), do: Sample.Math.square(x)
  def build(x), do: ordinary(untouched(x))
  def quoted do
    quote do
      def phantom(x), do: nonexistent(x)
    end
  end
end
