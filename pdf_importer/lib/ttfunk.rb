# Minimal TTFunk stub for PDF Importer
#
# The pdf-reader gem uses TTFunk to parse TrueType fonts embedded in PDFs.
# Since we only care about vector path geometry (not text), we provide a
# minimal stub that prevents LoadError without vendoring the full ttfunk gem.

module TTFunk
  class File
    attr_reader :header, :cmap, :horizontal_metrics

    def initialize(data = nil)
      @header = Header.new
      @cmap = Cmap.new
      @horizontal_metrics = HorizontalMetrics.new
    end

    class Header
      def units_per_em
        1000
      end
    end

    class Cmap
      def unicode
        []
      end
    end

    class HorizontalMetrics
      def metrics
        {}
      end
    end

    class Metric
      attr_reader :advance_width
      def initialize
        @advance_width = 0
      end
    end
  end
end
