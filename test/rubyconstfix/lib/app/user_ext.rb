# MONKEY PATCH of an in-tree class: reopens App::User with a method of its own, so it is a second REAL
# definer of the constant. A reference to App::User depends on BOTH files — change either and User changes —
# so it edges to both. This is multiplicity (every answer is right), not specifier ambiguity (one is).
module App
  class User
    def display_name
      name
    end
  end
end
