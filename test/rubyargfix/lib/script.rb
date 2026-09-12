raise App::Errors::Boom if ARGV.empty?    # a FILE-LEVEL argument is load-time (lazy=0) → App::Errors::Boom via Object; `ARGV` is a shown, out-of-tree receiver
