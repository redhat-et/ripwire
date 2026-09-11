module App
  class Dynamic
    include Object.const_get(:Trackable)
    autoload :Later, some_path
    require some_variable
  end
end
