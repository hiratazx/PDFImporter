# PDF Importer Extension for SketchUp
# Main loader file - loaded when the extension is enabled.
#
# This file sets up the load path for vendored gems, adds the menu
# item, and orchestrates the import flow.

module OpenSourceDev
  module PDFImporter

    # Add vendored gems to load path
    LIB_PATH = File.join(File.dirname(__FILE__), 'lib')
    $LOAD_PATH.unshift(LIB_PATH) unless $LOAD_PATH.include?(LIB_PATH)

    require 'pdf-reader'
    require File.join(File.dirname(__FILE__), 'pdf_parser')
    require File.join(File.dirname(__FILE__), 'path_receiver')
    require File.join(File.dirname(__FILE__), 'geometry_builder')
    require File.join(File.dirname(__FILE__), 'raster_handler')
    require File.join(File.dirname(__FILE__), 'settings_dialog')

    # Default settings
    DEFAULT_SETTINGS = {
      scale: 1.0,
      page_number: 1,
      import_strokes: true,
      import_fills: true,
      curve_segments: 16,
      pdf_type: 'auto',         # 'auto', 'vector', 'raster'
      raster_mode: 'image',     # 'image', 'trace', 'both'
      trace_threshold: 128,
      trace_simplify: 2.0
    }.freeze

    class << self
      def import_pdf
        # Step 1: Let user pick a PDF file
        pdf_path = UI.openpanel(
          'Select PDF File',
          '',
          'PDF Files|*.pdf||'
        )
        return unless pdf_path

        begin
          # Step 2: Get PDF info (page count, dimensions, detected type)
          pdf_info = PDFParser.get_info(pdf_path)

          # Step 3: Show settings dialog
          SettingsDialog.show(pdf_info) do |settings|
            # Step 4: Parse and import
            do_import(pdf_path, settings, pdf_info)
          end
        rescue StandardError => e
          UI.messagebox("Error reading PDF:\n#{e.message}", MB_OK)
          puts "PDF Importer Error: #{e.message}"
          puts e.backtrace.first(10).join("\n")
        end
      end

      def do_import(pdf_path, settings, pdf_info)
        model = Sketchup.active_model

        # Determine effective PDF type
        pdf_type = settings[:pdf_type] || 'auto'
        if pdf_type == 'auto'
          # Re-detect for the selected page
          detected = PDFParser.detect_type(pdf_path, settings[:page_number])
          pdf_type = case detected
                     when :vector then 'vector'
                     when :raster then 'raster'
                     when :mixed  then 'vector'  # Try vector first for mixed
                     else 'vector'
                     end
        end

        # Add page dimensions to settings for raster handler
        page_idx = (settings[:page_number] || 1) - 1
        page_info = pdf_info[:pages][page_idx] || pdf_info[:pages][0]
        if page_info
          settings[:page_width] = page_info[:width]
          settings[:page_height] = page_info[:height]
        end

        if pdf_type == 'raster'
          do_raster_import(pdf_path, settings, model)
        else
          do_vector_import(pdf_path, settings, model)
        end
      end

      def do_vector_import(pdf_path, settings, model)
        model.start_operation('Import PDF (Vector)', true)

        begin
          paths = PDFParser.parse_page(
            pdf_path,
            settings[:page_number],
            settings[:curve_segments]
          )

          if paths.empty?
            model.abort_operation
            # Offer raster fallback
            result = UI.messagebox(
              "No vector paths found in this PDF page.\n\n" \
              "This might be a scanned/raster PDF.\n" \
              "Would you like to try importing it as an image instead?",
              MB_YESNO
            )
            if result == IDYES
              settings[:pdf_type] = 'raster'
              settings[:raster_mode] = 'image'
              do_raster_import(pdf_path, settings, model)
            end
            return
          end

          count = GeometryBuilder.build(model, paths, settings)
          model.commit_operation

          Sketchup.status_text = "PDF Importer: Created #{count} edges"
          UI.messagebox(
            "PDF imported successfully!\n\n" \
            "Created #{count} edges from #{paths.length} paths.\n" \
            "The geometry is inside a group on the ground plane.",
            MB_OK
          )
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Error importing PDF:\n#{e.message}", MB_OK)
          puts "PDF Importer Error: #{e.message}"
          puts e.backtrace.first(10).join("\n")
        end
      end

      def do_raster_import(pdf_path, settings, model)
        raster_mode = settings[:raster_mode] || 'image'

        # Extract image from PDF
        Sketchup.status_text = "PDF Importer: Extracting image..."
        image_path = RasterHandler.extract_image(pdf_path, settings[:page_number])

        unless image_path
          UI.messagebox(
            "Could not extract an image from this PDF.\n\n" \
            "Tips:\n" \
            "• Make sure the PDF contains a scanned image\n" \
            "• Try exporting the PDF page as a PNG/JPG first,\n" \
            "  then import that image directly into SketchUp",
            MB_OK
          )
          return
        end

        begin
          case raster_mode
          when 'image'
            import_as_image(model, image_path, settings)

          when 'trace'
            auto_trace(model, image_path, settings)

          when 'both'
            import_as_image(model, image_path, settings)
            auto_trace(model, image_path, settings)
          end
        ensure
          # Clean up temp file
          File.delete(image_path) if image_path && File.exist?(image_path)
        end
      end

      def import_as_image(model, image_path, settings)
        model.start_operation('Import PDF (Image)', true)
        begin
          success = RasterHandler.import_as_image(model, image_path, settings)
          if success
            model.commit_operation
            UI.messagebox(
              "PDF imported as reference image!\n\n" \
              "The image is placed on the ground plane.\n" \
              "You can trace over it manually with SketchUp drawing tools.",
              MB_OK
            )
          else
            model.abort_operation
            UI.messagebox("Failed to import image.", MB_OK)
          end
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Error importing image:\n#{e.message}", MB_OK)
        end
      end

      def auto_trace(model, image_path, settings)
        model.start_operation('Import PDF (Trace)', true)
        begin
          Sketchup.status_text = "PDF Importer: Tracing edges..."
          count = RasterHandler.auto_trace(model, image_path, settings)

          if count > 0
            model.commit_operation
            UI.messagebox(
              "PDF auto-traced successfully!\n\n" \
              "Created #{count} edges from edge detection.\n" \
              "The traced geometry is inside a group on the ground plane.\n\n" \
              "Note: Auto-trace works best with clean, high-contrast scans.\n" \
              "You may need to clean up the result manually.",
              MB_OK
            )
          else
            model.abort_operation
            UI.messagebox(
              "Auto-trace found no edges.\n\n" \
              "Try adjusting the threshold value, or import as\n" \
              "a reference image instead.",
              MB_OK
            )
          end
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Error tracing PDF:\n#{e.message}", MB_OK)
        end
      end
    end

    # Register the menu item (only once)
    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions')
      submenu = menu.add_submenu('PDF Importer')
      submenu.add_item('Import PDF...') { import_pdf }
      submenu.add_separator
      submenu.add_item('About') {
        UI.messagebox(
          "PDF Importer v#{PLUGIN_VERSION}\n\n" \
          "Free & Open Source SketchUp Extension\n" \
          "Import vector and raster PDF files as editable geometry.\n\n" \
          "License: MIT\n" \
          "GitHub: github.com/hiratazx/PDFImporter",
          MB_OK
        )
      }
      file_loaded(__FILE__)
    end

  end
end
