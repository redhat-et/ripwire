module App
  class Order
    include Auditable

    def audit_target
      "order"
    end
  end

  # A template method: the base calls a hook only its subclass defines.
  class Report
    def render_report
      header_line
    end
  end

  class PdfReport < Report
    def header_line
      "pdf"
    end
  end
end
