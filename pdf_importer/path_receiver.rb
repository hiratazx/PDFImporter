# PDF Importer Extension for SketchUp
# PathReceiver - Custom receiver for pdf-reader's page.walk()
#
# This is the heart of the extension. It intercepts PDF content stream
# drawing operations and builds a list of geometric paths.

module OpenSourceDev
  module PDFImporter
    class PathReceiver

      # Each completed path is a Hash:
      # {
      #   type: :stroke | :fill | :fill_and_stroke | :close_and_stroke | etc.,
      #   subpaths: [
      #     {
      #       closed: true/false,
      #       operations: [
      #         { op: :move_to, x:, y: },
      #         { op: :line_to, x:, y: },
      #         { op: :curve_to, x1:, y1:, x2:, y2:, x3:, y3: },
      #         { op: :rect, x:, y:, width:, height: }
      #       ]
      #     }
      #   ]
      # }

      attr_reader :completed_paths

      def initialize(curve_segments = 16)
        @curve_segments = curve_segments
        @completed_paths = []
        @current_subpaths = []
        @current_ops = []
        @current_point = { x: 0.0, y: 0.0 }
        @subpath_start = { x: 0.0, y: 0.0 }

        # CTM (Current Transformation Matrix) stack
        # Each matrix is [a, b, c, d, e, f] representing:
        #   | a b 0 |
        #   | c d 0 |
        #   | e f 1 |
        @ctm_stack = []
        @ctm = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0] # identity
      end

      # ─── Graphics State ───────────────────────────────────

      def save_graphics_state
        @ctm_stack.push(@ctm.dup)
      end

      def restore_graphics_state
        @ctm = @ctm_stack.pop || [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
      end

      def concatenate_matrix(a, b, c, d, e, f)
        # Multiply new matrix with current CTM
        # [a b 0] * [ctm_a ctm_b 0]
        # [c d 0]   [ctm_c ctm_d 0]
        # [e f 1]   [ctm_e ctm_f 1]
        ca, cb, cc, cd, ce, cf = @ctm
        @ctm = [
          a * ca + b * cc,           # new_a
          a * cb + b * cd,           # new_b
          c * ca + d * cc,           # new_c
          c * cb + d * cd,           # new_d
          e * ca + f * cc + ce,      # new_e
          e * cb + f * cd + cf       # new_f
        ]
      end

      # ─── Path Construction ────────────────────────────────

      def move_to(x, y)
        # Finish current subpath if it has operations
        finish_subpath unless @current_ops.empty?

        tx, ty = transform_point(x.to_f, y.to_f)
        @current_point = { x: tx, y: ty }
        @subpath_start = { x: tx, y: ty }
        @current_ops << { op: :move_to, x: tx, y: ty }
      end

      def line_to(x, y)
        tx, ty = transform_point(x.to_f, y.to_f)
        @current_ops << { op: :line_to, x: tx, y: ty }
        @current_point = { x: tx, y: ty }
      end

      def curve_to(x1, y1, x2, y2, x3, y3)
        # Cubic Bézier: current_point → (x1,y1) → (x2,y2) → (x3,y3)
        tx1, ty1 = transform_point(x1.to_f, y1.to_f)
        tx2, ty2 = transform_point(x2.to_f, y2.to_f)
        tx3, ty3 = transform_point(x3.to_f, y3.to_f)
        @current_ops << {
          op: :curve_to,
          x0: @current_point[:x], y0: @current_point[:y],
          x1: tx1, y1: ty1,
          x2: tx2, y2: ty2,
          x3: tx3, y3: ty3
        }
        @current_point = { x: tx3, y: ty3 }
      end

      # Bézier with first control point = current point (PDF operator 'v')
      def curve_to_initial(x2, y2, x3, y3)
        curve_to(@current_point[:x], @current_point[:y], x2, y2, x3, y3)
      end

      # Bézier with last control point = endpoint (PDF operator 'y')
      def curve_to_final(x1, y1, x3, y3)
        curve_to(x1, y1, x3, y3, x3, y3)
      end

      def append_rectangle(x, y, width, height)
        x = x.to_f
        y = y.to_f
        width = width.to_f
        height = height.to_f

        # Rectangle is defined as: move to corner, then 4 lines, then close
        # Transform all four corners
        x1, y1 = transform_point(x, y)
        x2, y2 = transform_point(x + width, y)
        x3, y3 = transform_point(x + width, y + height)
        x4, y4 = transform_point(x, y + height)

        # Finish any current subpath
        finish_subpath unless @current_ops.empty?

        # Build the rectangle as a closed subpath
        @current_ops = [
          { op: :move_to, x: x1, y: y1 },
          { op: :line_to, x: x2, y: y2 },
          { op: :line_to, x: x3, y: y3 },
          { op: :line_to, x: x4, y: y4 }
        ]
        @current_point = { x: x4, y: y4 }
        @subpath_start = { x: x1, y: y1 }

        finish_subpath(true) # close the rectangle
      end

      def close_subpath
        # Add a line back to the start of the subpath if needed
        unless @current_ops.empty?
          last = @current_point
          start = @subpath_start
          if (last[:x] - start[:x]).abs > 0.001 || (last[:y] - start[:y]).abs > 0.001
            @current_ops << { op: :line_to, x: start[:x], y: start[:y] }
          end
          @current_point = start.dup
        end
        finish_subpath(true)
      end

      # ─── Path Painting ────────────────────────────────────

      def stroke
        complete_path(:stroke)
      end

      def fill(params = nil)
        complete_path(:fill)
      end

      # pdf-reader calls this for the 'f*' operator (even-odd fill)
      def fill_with_even_odd
        complete_path(:fill)
      end

      def fill_and_stroke
        complete_path(:fill_and_stroke)
      end

      def fill_and_stroke_with_even_odd
        complete_path(:fill_and_stroke)
      end

      def close_and_stroke
        close_subpath
        complete_path(:stroke)
      end

      def close_and_fill_and_stroke
        close_subpath
        complete_path(:fill_and_stroke)
      end

      def close_and_fill_and_stroke_with_even_odd
        close_subpath
        complete_path(:fill_and_stroke)
      end

      def end_path
        # Discard the current path (used for clipping only)
        @current_ops = []
        @current_subpaths = []
      end

      # ─── Clipping (no-op, just consume) ───────────────────

      def clip(params = nil)
        # We don't implement clipping, just ignore
      end

      def clip_with_even_odd
        # We don't implement clipping, just ignore
      end

      # ─── Color/Graphics state we don't need ───────────────
      # Define these as no-ops so pdf-reader doesn't complain

      def set_line_width(w); end
      def set_line_cap(cap); end
      def set_line_join(join); end
      def set_miter_limit(limit); end
      def set_line_dash(dash, phase); end
      def set_flatness_tolerance(tolerance); end
      def set_graphics_state_parameters(dict); end

      def set_stroke_color_space(cs); end
      def set_nonstroke_color_space(cs); end
      def set_stroke_color(*args); end
      def set_stroke_color_n(*args); end
      def set_nonstroke_color(*args); end
      def set_nonstroke_color_n(*args); end
      def set_stroke_gray(gray); end
      def set_nonstroke_gray(gray); end
      def set_stroke_rgb_color(r, g, b); end
      def set_nonstroke_rgb_color(r, g, b); end
      def set_stroke_cmyk_color(c, m, y, k); end
      def set_nonstroke_cmyk_color(c, m, y, k); end

      # Text operators (we ignore text)
      def begin_text_object; end
      def end_text_object; end
      def set_character_spacing(spacing); end
      def move_text_position(x, y); end
      def move_text_position_and_set_leading(x, y); end
      def set_text_font_and_size(font, size); end
      def show_text(string); end
      def show_text_with_positioning(array); end
      def move_to_next_line_and_show_text(string); end
      def set_spacing_next_line_show_text(aw, ac, string); end
      def set_text_leading(leading); end
      def set_text_matrix_and_text_line_matrix(a, b, c, d, e, f); end
      def set_text_rendering_mode(mode); end
      def set_text_rise(rise); end
      def set_word_spacing(spacing); end
      def set_horizontal_text_scaling(scaling); end
      def move_to_start_of_next_line; end

      # XObject / inline image operators
      def invoke_xobject(name); end
      def begin_inline_image; end
      def begin_inline_image_data(*args); end
      def end_inline_image(data); end

      # Marked content operators
      def begin_marked_content(tag); end
      def begin_marked_content_with_pl(tag, properties); end
      def end_marked_content; end
      def define_marked_content_point(tag); end
      def define_marked_content_point_with_pl(tag, properties); end

      # Compatibility
      def begin_compatibility_section; end
      def end_compatibility_section; end

      private

      def transform_point(x, y)
        a, b, c, d, e, f = @ctm
        [
          a * x + c * y + e,
          b * x + d * y + f
        ]
      end

      def finish_subpath(closed = false)
        return if @current_ops.empty?
        @current_subpaths << {
          closed: closed,
          operations: @current_ops.dup
        }
        @current_ops = []
      end

      def complete_path(type)
        # Finish any remaining subpath
        finish_subpath unless @current_ops.empty?

        return if @current_subpaths.empty?

        @completed_paths << {
          type: type,
          subpaths: @current_subpaths.dup
        }

        @current_subpaths = []
        @current_ops = []
      end

    end
  end
end
