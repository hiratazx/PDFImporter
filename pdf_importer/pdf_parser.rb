# PDF Importer Extension for SketchUp
# PDFParser - Wrapper around pdf-reader for parsing PDF files
#
# Provides methods to get PDF info, detect type, and parse individual pages.

module OpenSourceDev
  module PDFImporter
    module PDFParser

      # PDF type constants
      TYPE_VECTOR = :vector
      TYPE_RASTER = :raster
      TYPE_MIXED  = :mixed
      TYPE_EMPTY  = :empty

      # Get basic info about the PDF file, including auto-detected type
      # Returns: { page_count:, pages: [...], detected_type: }
      def self.get_info(pdf_path)
        reader = PDF::Reader.new(pdf_path)
        pages = reader.pages.each_with_index.map do |page, idx|
          media_box = page.attributes[:MediaBox] || [0, 0, 612, 792]
          {
            index: idx + 1,
            width: (media_box[2] - media_box[0]).to_f,
            height: (media_box[3] - media_box[1]).to_f,
            width_inches: ((media_box[2] - media_box[0]) / 72.0).round(2),
            height_inches: ((media_box[3] - media_box[1]) / 72.0).round(2)
          }
        end

        # Auto-detect type of the first page
        detected = detect_type(pdf_path, 1)

        {
          page_count: reader.page_count,
          pages: pages,
          pdf_version: reader.pdf_version,
          detected_type: detected
        }
      end

      # Detect whether a PDF page is vector, raster, or mixed
      def self.detect_type(pdf_path, page_number)
        reader = PDF::Reader.new(pdf_path)
        return TYPE_EMPTY if reader.page_count == 0

        page_number = [page_number, reader.page_count].min
        page = reader.pages[page_number - 1]

        # Count vector operations
        counter = OperationCounter.new
        begin
          page.walk(counter)
        rescue StandardError
          # If walking fails, try to check XObjects directly
        end

        has_vectors = counter.path_ops > 0
        has_images = counter.image_ops > 0

        # Also check XObjects for images
        begin
          objects = reader.objects
          xobjects = page.xobjects rescue {}
          xobjects.each do |_name, xobj|
            next unless xobj.is_a?(PDF::Reader::Stream)
            subtype = begin
              objects.deref_name(xobj.hash[:Subtype])
            rescue
              xobj.hash[:Subtype]
            end
            if subtype == :Image
              has_images = true
              break
            end
          end
        rescue StandardError
          # Ignore XObject errors
        end

        if has_vectors && has_images
          TYPE_MIXED
        elsif has_vectors
          TYPE_VECTOR
        elsif has_images
          TYPE_RASTER
        else
          TYPE_EMPTY
        end
      end

      # Parse a single page and return an array of completed paths
      def self.parse_page(pdf_path, page_number, curve_segments = 16)
        reader = PDF::Reader.new(pdf_path)

        if page_number < 1 || page_number > reader.page_count
          raise "Page #{page_number} does not exist. PDF has #{reader.page_count} page(s)."
        end

        page = reader.pages[page_number - 1]
        receiver = PathReceiver.new(curve_segments)
        page.walk(receiver)

        receiver.completed_paths
      end

      # Simple receiver that counts drawing operations to detect PDF type
      class OperationCounter
        attr_reader :path_ops, :image_ops, :text_ops

        def initialize
          @path_ops = 0
          @image_ops = 0
          @text_ops = 0
        end

        # Path construction
        def move_to(x, y); @path_ops += 1; end
        def line_to(x, y); @path_ops += 1; end
        def curve_to(*args); @path_ops += 1; end
        def curve_to_initial(*args); @path_ops += 1; end
        def curve_to_final(*args); @path_ops += 1; end
        def append_rectangle(x, y, w, h); @path_ops += 1; end

        # Path painting
        def stroke; @path_ops += 1; end
        def fill(*args); @path_ops += 1; end
        def fill_with_even_odd; @path_ops += 1; end
        def fill_and_stroke; @path_ops += 1; end
        def fill_and_stroke_with_even_odd; @path_ops += 1; end
        def close_and_stroke; @path_ops += 1; end
        def close_and_fill_and_stroke; @path_ops += 1; end
        def close_and_fill_and_stroke_with_even_odd; @path_ops += 1; end
        def close_subpath; end
        def end_path; end

        # Images
        def invoke_xobject(name); @image_ops += 1; end
        def begin_inline_image; @image_ops += 1; end
        def begin_inline_image_data(*args); end
        def end_inline_image(data); end

        # Text
        def show_text(string); @text_ops += 1; end
        def show_text_with_positioning(array); @text_ops += 1; end
        def move_to_next_line_and_show_text(string); @text_ops += 1; end
        def set_spacing_next_line_show_text(aw, ac, string); @text_ops += 1; end

        # Graphics state (no-op)
        def save_graphics_state; end
        def restore_graphics_state; end
        def concatenate_matrix(a, b, c, d, e, f); end

        # Catch-all for operators we don't care about
        def set_line_width(w); end
        def set_line_cap(c); end
        def set_line_join(j); end
        def set_miter_limit(l); end
        def set_line_dash(d, p); end
        def set_flatness_tolerance(t); end
        def set_graphics_state_parameters(d); end
        def set_stroke_color_space(cs); end
        def set_nonstroke_color_space(cs); end
        def set_stroke_color(*a); end
        def set_stroke_color_n(*a); end
        def set_nonstroke_color(*a); end
        def set_nonstroke_color_n(*a); end
        def set_stroke_gray(g); end
        def set_nonstroke_gray(g); end
        def set_stroke_rgb_color(r, g, b); end
        def set_nonstroke_rgb_color(r, g, b); end
        def set_stroke_cmyk_color(c, m, y, k); end
        def set_nonstroke_cmyk_color(c, m, y, k); end
        def begin_text_object; end
        def end_text_object; end
        def set_character_spacing(s); end
        def move_text_position(x, y); end
        def move_text_position_and_set_leading(x, y); end
        def set_text_font_and_size(f, s); end
        def set_text_leading(l); end
        def set_text_matrix_and_text_line_matrix(a, b, c, d, e, f); end
        def set_text_rendering_mode(m); end
        def set_text_rise(r); end
        def set_word_spacing(s); end
        def set_horizontal_text_scaling(s); end
        def move_to_start_of_next_line; end
        def clip(*a); end
        def clip_with_even_odd; end
        def begin_marked_content(t); end
        def begin_marked_content_with_pl(t, p); end
        def end_marked_content; end
        def define_marked_content_point(t); end
        def define_marked_content_point_with_pl(t, p); end
        def begin_compatibility_section; end
        def end_compatibility_section; end
      end

    end
  end
end
