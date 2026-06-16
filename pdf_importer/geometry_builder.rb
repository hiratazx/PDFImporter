# PDF Importer Extension for SketchUp
# GeometryBuilder - Converts parsed PDF paths into SketchUp geometry
#
# Creates edges, faces, and curves inside a group on the ground plane.
# Handles coordinate conversion from PDF space (points, Y-up) to
# SketchUp space (inches, X-right/Y-depth/Z-up on ground plane).

module OpenSourceDev
  module PDFImporter
    module GeometryBuilder

      # PDF coordinate space:  origin bottom-left, Y goes up, units in points (1/72 inch)
      # SketchUp space:        origin at [0,0,0], X=right, Y=depth, Z=up
      # We map PDF onto the ground plane: PDF X → SU X, PDF Y → SU Y, Z=0
      POINTS_TO_INCHES = 1.0 / 72.0

      # Build SketchUp geometry from parsed paths
      # Returns the number of edges created
      def self.build(model, paths, settings)
        scale = (settings[:scale] || 1.0) * POINTS_TO_INCHES
        import_strokes = settings[:import_strokes] != false
        import_fills = settings[:import_fills] != false
        curve_segments = settings[:curve_segments] || 16

        # Create a group to contain all imported geometry
        group = model.active_entities.add_group
        group.name = 'PDF Import'
        entities = group.entities

        edge_count = 0

        paths.each do |path|
          path_type = path[:type]

          # Skip based on user settings
          next if path_type == :stroke && !import_strokes
          next if path_type == :fill && !import_fills

          path[:subpaths].each do |subpath|
            face_created = false

            # Optimization: Try direct face creation for closed fill paths
            if subpath[:closed] && import_fills && (path_type == :fill || path_type == :fill_and_stroke)
              pts = collect_subpath_points(subpath, scale, curve_segments)
              if pts.length >= 3
                begin
                  face = entities.add_face(pts)
                  if face
                    face_created = true
                    edge_count += face.edges.length
                  end
                rescue StandardError
                  # Fallback to drawing edges if direct face creation fails (e.g. non-planar points)
                end
              end
            end

            unless face_created
              edges = draw_subpath(entities, subpath, scale, curve_segments)
              edge_count += edges.length

              # Fallback: find faces if drawing edges succeeded and it is a filled path
              if subpath[:closed] && import_fills && (path_type == :fill || path_type == :fill_and_stroke) && edges.length >= 3
                begin
                  edges.first.find_faces if edges.first
                rescue StandardError
                end
              end
            end
          end
        end

        # Zoom to fit the imported group
        if edge_count > 0
          model.active_view.zoom(group)
        end

        edge_count
      end

      private

      # Collect all points for a subpath without creating any geometry
      def self.collect_subpath_points(subpath, scale, curve_segments)
        points = []
        current_point = nil

        subpath[:operations].each do |op|
          case op[:op]
          when :move_to
            pt = to_sketchup_point(op[:x], op[:y], scale)
            current_point = pt
            points << pt
          when :line_to
            pt = to_sketchup_point(op[:x], op[:y], scale)
            points << pt
            current_point = pt
          when :curve_to
            bezier_points = sample_bezier(
              op[:x0], op[:y0],
              op[:x1], op[:y1],
              op[:x2], op[:y2],
              op[:x3], op[:y3],
              curve_segments,
              scale
            )
            bezier_points.shift if !points.empty?
            points.concat(bezier_points)
            current_point = points.last
          end
        end

        # Filter out consecutive duplicate points
        filtered = []
        points.each do |pt|
          if filtered.empty?
            filtered << pt
          else
            prev = filtered.last
            next if (pt.x - prev.x).abs < 0.0001 &&
                    (pt.y - prev.y).abs < 0.0001 &&
                    (pt.z - prev.z).abs < 0.0001
            filtered << pt
          end
        end

        # For closed loops, remove duplicate end point for add_face compatibility
        if filtered.length >= 3 && filtered.first == filtered.last
          filtered.pop
        end

        filtered
      end

      # Draw a single subpath and return the array of edges created
      def self.draw_subpath(entities, subpath, scale, curve_segments)
        edges = []
        points_buffer = []

        subpath[:operations].each do |op|
          case op[:op]
          when :move_to
            edges.concat(flush_points(entities, points_buffer)) if points_buffer.length >= 2
            points_buffer = []

            pt = to_sketchup_point(op[:x], op[:y], scale)
            points_buffer << pt

          when :line_to
            pt = to_sketchup_point(op[:x], op[:y], scale)
            points_buffer << pt

          when :curve_to
            bezier_points = sample_bezier(
              op[:x0], op[:y0],
              op[:x1], op[:y1],
              op[:x2], op[:y2],
              op[:x3], op[:y3],
              curve_segments,
              scale
            )
            bezier_points.shift if !points_buffer.empty?
            points_buffer.concat(bezier_points)
          end
        end

        edges.concat(flush_points(entities, points_buffer)) if points_buffer.length >= 2
        edges
      end

      # Convert buffered points into edges using high-performance bulk add_edges API
      def self.flush_points(entities, points)
        return [] if points.length < 2

        # Filter out consecutive duplicate points
        filtered = []
        points.each do |pt|
          if filtered.empty?
            filtered << pt
          else
            prev = filtered.last
            next if (pt.x - prev.x).abs < 0.0001 &&
                    (pt.y - prev.y).abs < 0.0001 &&
                    (pt.z - prev.z).abs < 0.0001
            filtered << pt
          end
        end

        return [] if filtered.length < 2

        begin
          # add_edges returns an array of Edge objects in a single C++ operation
          entities.add_edges(filtered)
        rescue StandardError
          # Fallback to individual lines if add_edges fails
          edges = []
          (0...filtered.length - 1).each do |i|
            begin
              edge = entities.add_line(filtered[i], filtered[i + 1])
              edges << edge if edge
            rescue StandardError
            end
          end
          edges
        end
      end

      # Convert PDF coordinates to a SketchUp Point3d on the ground plane
      def self.to_sketchup_point(x, y, scale)
        Geom::Point3d.new(x * scale, y * scale, 0.0)
      end

      # Sample a cubic Bézier curve into discrete points
      # P(t) = (1-t)³·P0 + 3·(1-t)²·t·P1 + 3·(1-t)·t²·P2 + t³·P3
      def self.sample_bezier(x0, y0, x1, y1, x2, y2, x3, y3, segments, scale)
        points = []

        (0..segments).each do |i|
          t = i.to_f / segments
          t2 = t * t
          t3 = t2 * t
          mt = 1.0 - t
          mt2 = mt * mt
          mt3 = mt2 * mt

          x = mt3 * x0 + 3.0 * mt2 * t * x1 + 3.0 * mt * t2 * x2 + t3 * x3
          y = mt3 * y0 + 3.0 * mt2 * t * y1 + 3.0 * mt * t2 * y2 + t3 * y3

          points << to_sketchup_point(x, y, scale)
        end

        points
      end

    end
  end
end
