### Added — `--for` lists who imports the model of an add-a-new task

A `--for` task that adds a new thing modeled on a named one ("add a new X, use Foo as the model") now carries `<importers>`: the source files importing Foo's file, with a file that only lists imports marked `aggregator="1"` and shown first. Present only when the model resolves and has a source importer; capped at 6 rows with `next=--impact=`.
