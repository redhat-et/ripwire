module App
  class Report
    DEFAULT = Helper.fmt(1)       # a receiver in the CLASS BODY runs at load: lazy=0 → App::Helper

    def build
      User.find(1)                # a receiver inside a METHOD BODY: lazy=1 → App::User
      User.find(2)                # DEDUPED — same (file, nesting, written name); a constant loads once
      App::Mailer.deliver         # written `App::Mailer`: App::Report::App::Mailer, App::App::Mailer, App::Mailer ✓
      Time.now                    # out of tree: SHOWN as a directive, no edge
      Time.now.to_i               # deduped with `Time`
      ::Time.zone                 # a DIFFERENT spelling (absolute) is its own directive
      raise Errors::Boom          # a constant as an ARGUMENT is not a receiver — DISCLOSED FLOOR
    rescue Errors::Boom           # a rescue class is not a receiver — DISCLOSED FLOOR
      nil
    end
  end
end
