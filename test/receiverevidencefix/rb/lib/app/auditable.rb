module App
  # A concern calls a method its INCLUDER defines: Ruby's lookup proves it (self is an includer instance).
  module Auditable
    def log_audit
      audit_target
    end
  end
end
