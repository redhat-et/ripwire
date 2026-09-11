require_relative 'lib/helper'      # file-relative, normalized to ./lib/helper
require_relative './sib'           # already dotted
require 'lib/helper'               # load-path form, same file, different rule
require 'json'                     # a gem: outside the tree, no edge
load 'tool.rb'                     # Kernel#load, same load-path rule
require 'shared'                   # AMBIGUOUS: ./shared.rb AND lib/shared.rb both answer
require some_variable              # not a string literal: nothing to read
autoload :Late, 'lib/helper'       # parser version 82: Kernel#autoload's PATH is the dependency (was a stated floor through 81)

module Wrapper
  require_relative 'nested/deep'   # inside a module body

  def self.run
    require_relative 'lib/lazy'    # inside a method body
  end
end

begin
  require 'optional_gem'           # the LoadError idiom: captured, resolves to nothing
rescue LoadError
  require_relative 'lib/fallback'  # the rescue arm is captured too (union over arms)
end

if RUBY_VERSION > '3'
  require_relative 'lib/modern'
end
