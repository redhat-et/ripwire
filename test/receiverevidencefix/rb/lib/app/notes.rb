# A top-level def is a private method of Object: every bare call can reach it.
def top_level_note(s)
  warn s
end
