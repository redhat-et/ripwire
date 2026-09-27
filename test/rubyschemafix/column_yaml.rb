# pair arm (column, yaml): column only; the yaml source lives in config/spike_names.yml.
module Spike
  class ColumnYaml < ApplicationRecord
    self.table_name = "spike_column_yamls"
  end
end
