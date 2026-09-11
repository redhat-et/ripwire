# DECOY, two jobs: (1) a TOP-LEVEL `Trackable` that lexical lookup inside `module App` must NOT prefer
# over App::Trackable; (2) on a case-insensitive filesystem a load-path probe for a target spelled
# "Trackable" would land here — a constant must never be probed as a path.
module Trackable
end
