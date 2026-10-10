module Rake
  class Task
    def invoke
    end
  end

  class FileTask < Task
    def needed?
      true
    end
  end

  class MultiTask < Task
  end

  class FileCreationTask < FileTask
  end
end
