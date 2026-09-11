defmodule MyApp.Nested do
  if function_exported?(Code, :ensure_loaded?, 1) do
    alias MyApp.Foo
  end

  case :runtime do
    :runtime -> import MyApp.Bar
  end

  def inner do
    require MyApp.Baz
  end
end
