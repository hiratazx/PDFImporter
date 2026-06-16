# PDF Importer Extension for SketchUp
# SettingsDialog - Import settings UI using HtmlDialog
#
# Shows a dialog where the user can configure:
# - PDF type (Auto-detect / Vector / Raster)
# - Scale factor
# - Page number (for multi-page PDFs)
# - Whether to import strokes and/or fills (vector mode)
# - Raster mode (image / trace / both)
# - Bézier curve resolution / trace settings

module OpenSourceDev
  module PDFImporter
    module SettingsDialog

      @dialog = nil

      def self.show(pdf_info, &callback)
        @callback = callback

        options = {
          dialog_title: 'PDF Import Settings',
          width: 480,
          height: 680,
          resizable: false,
          style: UI::HtmlDialog::STYLE_DIALOG
        }

        @dialog = UI::HtmlDialog.new(options)

        # Callback: user clicks Import
        @dialog.add_action_callback('do_import') do |_ctx, data|
          settings = parse_settings(data)
          @dialog.close
          @callback.call(settings) if @callback
        end

        # Callback: user clicks Cancel
        @dialog.add_action_callback('do_cancel') do |_ctx|
          @dialog.close
        end

        # Set the HTML content
        html_path = File.join(File.dirname(__FILE__), 'html', 'settings.html')
        @dialog.set_file(html_path)

        @dialog.set_on_closed {
          @dialog = nil
        }

        @dialog.show

        # Send PDF info to the dialog after a short delay
        UI.start_timer(0.3, false) do
          if @dialog
            json = pdf_info_to_json(pdf_info)
            @dialog.execute_script("setPDFInfo(#{json})")
          end
        end
      end

      private

      def self.parse_settings(data)
        {
          scale: (data['scale'] || 1.0).to_f,
          page_number: (data['page'] || 1).to_i,
          import_strokes: data['strokes'] != false && data['strokes'] != 'false',
          import_fills: data['fills'] != false && data['fills'] != 'false',
          curve_segments: (data['segments'] || 16).to_i.clamp(4, 64),
          pdf_type: data['pdfType'] || 'auto',
          raster_mode: data['rasterMode'] || 'image',
          trace_threshold: (data['threshold'] || 128).to_i.clamp(1, 254),
          trace_simplify: (data['simplify'] || 2.0).to_f.clamp(0.5, 10.0)
        }
      end

      def self.pdf_info_to_json(info)
        pages_json = info[:pages].map { |p|
          "{\"index\":#{p[:index]},\"width\":#{p[:width]},\"height\":#{p[:height]}," \
          "\"width_inches\":#{p[:width_inches]},\"height_inches\":#{p[:height_inches]}}"
        }.join(',')

        detected = info[:detected_type] || :vector
        detected_str = detected.to_s

        "{\"page_count\":#{info[:page_count]},\"pages\":[#{pages_json}]," \
        "\"detected_type\":\"#{detected_str}\"}"
      end

    end
  end
end
