# Ruby settings module — SCREAMING_SNAKE toplevel + class-level constants.

RB_PASSWORD_HASHERS = ["pbkdf2", "scrypt"].freeze

# CamelCase constant assignment — a class-ish alias, must stay unindexed
CamelAlias = Struct.new(:x)

class RubyCfg
  RB_TIMEOUT_SECONDS = 30

  def timeout
    RB_TIMEOUT_SECONDS
  end
end
