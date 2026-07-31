# b.rb — Ruby ingest fixture for javarubycheck.sh.
# Two methods where sum_of_squares calls square → one intra-file call edge
# sum_of_squares -> square.

def square( x )
  x * x
end

def sum_of_squares( a, b )
  square( a ) + square( b )
end

puts sum_of_squares( 3, 4 )
