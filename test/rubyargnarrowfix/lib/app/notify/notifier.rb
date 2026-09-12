module App
  class Notifier
    def run(record)
      notify(Dev::Config)             # a constant ARGUMENT: a dependency on dev/config.rb (--deps, --impact) …
      record.update!(state: 1)        # … but NOT import evidence for this bare call: `record` is not Dev::Config,
    end                               # and a narrow that read it as one would bind update! to Config#update!
  end
end
