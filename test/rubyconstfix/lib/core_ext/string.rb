# MONKEY PATCH of a CORE class: the tree's only definer of String. `class Shouty < String` depends on it.
class String
  def shout
    upcase + "!"
  end
end
