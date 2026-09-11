module App
  class UsesNs
    # `App` is OPENED by 20 files; only lib/app.rb gives it a body of its own (VERSION). The other opens are
    # namespace wrappers — a body holding nothing but nested definitions defines nothing — so this edges to
    # lib/app.rb alone.
    include ::App
  end
end
