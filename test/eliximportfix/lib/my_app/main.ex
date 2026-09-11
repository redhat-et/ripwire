defmodule MyApp.Main do
  alias MyApp.Foo
  alias MyApp.{Bar, Baz}
  alias MyApp.Foo, as: F
  import MyApp.Bar
  use MyApp.Baz
  require Logger
  alias Nested.Thing
  alias MyApp.Dup

  def go do
    Foo.run()
  end
end
