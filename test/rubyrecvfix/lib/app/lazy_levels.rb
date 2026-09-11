module App
  class Levels
    Helper.fmt(0)                     # class-body level: LOAD-TIME (lazy=0)
    HANDLER = -> { Mailer.deliver }   # inside a lambda literal: LAZY (lazy=1) — a closure runs when called
    def self.run
      User.find(3)                    # inside a singleton method: LAZY
    end
    after_commit do
      Admin::User.find(4)             # inside a do-block: LAZY — a block is a closure the callee may or may not run
    end
  end
end
