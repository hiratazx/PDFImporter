# PDF Importer Extension for SketchUp
# RasterHandler - Handles raster/scanned PDF import
#
# When a PDF is detected as raster (contains images instead of vector paths),
# this module extracts embedded images and provides two import modes:
#   1. Import as reference image on the ground plane
#   2. Auto-trace edges to create vector geometry

module OpenSourceDev
  module PDFImporter
    module RasterHandler

      # Extract the largest image from a PDF page and save to a temp file.
      # Returns the path to the saved image, or nil if extraction failed.
      #
      # Tries native OS rendering first (PowerShell on Windows, PDFKit on macOS)
      # to guarantee high-fidelity rendering of all image formats (grayscale JPEG,
      # JBIG2, CCITT, etc.). Falls back to raw XObject extraction if unsupported.
      def self.extract_image(pdf_path, page_number)
        require 'tmpdir'
        temp_dir = Dir.tmpdir rescue '/tmp'
        output_png = File.join(temp_dir, "pdf_importer_page_#{page_number}.png")

        puts "PDF Importer: --- Starting Image Extraction ---"
        puts "PDF Importer: PDF Path = #{pdf_path}"
        puts "PDF Importer: Target Page = #{page_number}"
        puts "PDF Importer: Output PNG Path = #{output_png}"

        # 1. Try native OS rendering first
        if render_pdf_to_png(pdf_path, page_number, output_png)
          puts "PDF Importer: Native OS rendering succeeded. Returning PNG path."
          return output_png
        else
          puts "PDF Importer: Native OS rendering failed."
        end

        # 2. Fallback to extracting largest image XObject
        puts "PDF Importer: Falling back to raw XObject extraction..."

        reader = PDF::Reader.new(pdf_path)
        page = reader.pages[page_number - 1]
        objects = reader.objects

        # Collect all image XObjects from the page
        images = []
        xobjects = page.xobjects rescue {}
        xobjects.each do |name, xobj|
          next unless xobj.is_a?(PDF::Reader::Stream)
          # Dereference the hash to get subtype
          subtype = objects.deref_name(xobj.hash[:Subtype]) rescue xobj.hash[:Subtype]
          next unless subtype == :Image

          width = (objects.deref_integer(xobj.hash[:Width]) rescue xobj.hash[:Width]) || 0
          height = (objects.deref_integer(xobj.hash[:Height]) rescue xobj.hash[:Height]) || 0
          filter = xobj.hash[:Filter]
          filter = [filter] unless filter.is_a?(Array)

          images << {
            name: name,
            stream: xobj,
            width: width.to_i,
            height: height.to_i,
            filter: filter,
            pixels: width.to_i * height.to_i
          }
        end

        puts "PDF Importer: Found #{images.length} XObject images on this page."

        return nil if images.empty?

        # Pick the largest image (most likely the page scan)
        best = images.max_by { |img| img[:pixels] }
        return nil unless best && best[:pixels] > 0

        puts "PDF Importer: Extracting XObject '#{best[:name]}' (#{best[:width]}x#{best[:height]}, filter: #{best[:filter].inspect})..."
        save_image(best)
      rescue StandardError => e
        puts "PDF Importer: Image extraction error: #{e.message}"
        puts e.backtrace.first(10).join("\n")
        nil
      end

      # Render a PDF page directly to a PNG file using the OS's native PDF engine.
      # On Windows, uses PowerShell + Windows.Data.Pdf.
      # On macOS, uses Cocoa/PDFKit via osascript.
      # Returns true on success.
      def self.render_pdf_to_png(pdf_path, page_number, output_png_path)
        abs_pdf = File.expand_path(pdf_path)
        abs_png = File.expand_path(output_png_path)

        puts "PDF Importer: Attempting native OS rendering..."
        puts "PDF Importer: Platform detected = #{Sketchup.platform.inspect}"

        if Sketchup.platform == :platform_win
          abs_pdf = abs_pdf.gsub('/', '\\')
          abs_png = abs_png.gsub('/', '\\')

          # Create temporary PowerShell script
          temp_dir = Dir.tmpdir rescue 'C:/Temp'
          ps_script_path = File.join(temp_dir, 'pdf_render.ps1').gsub('/', '\\')
          stdout_log = File.join(temp_dir, 'pdf_render_out.log').gsub('/', '\\')
          stderr_log = File.join(temp_dir, 'pdf_render_err.log').gsub('/', '\\')

          # Delete pre-existing logs to avoid reading stale data
          File.delete(stdout_log) if File.exist?(stdout_log)
          File.delete(stderr_log) if File.exist?(stderr_log)

          # 0-indexed page number for WinRT
          page_idx = page_number - 1

          ps_content = <<~POWERSHELL
            $ErrorActionPreference = "Stop"
            $logPath = #{escape_ps_string(stdout_log)}
            $errPath = #{escape_ps_string(stderr_log)}

            function Log-Msg($msg) {
                Add-Content -Path $logPath -Value $msg
            }

            try {
                Log-Msg "Loading WinRT assemblies..."
                [void][System.Reflection.Assembly]::LoadWithPartialName("System.Runtime.WindowsRuntime")
                
                Log-Msg "Loading Windows.winmd..."
                $winmd = [IO.Path]::Combine($env:windir, "System32\\WinMetadata\\Windows.winmd")
                if (-not (Test-Path $winmd)) {
                    $winmd = [IO.Path]::Combine($env:windir, "Sysnative\\WinMetadata\\Windows.winmd")
                }
                if (-not (Test-Path $winmd)) {
                    throw "WinMetadata file not found in System32 or Sysnative at $env:windir\\*\\WinMetadata\\Windows.winmd"
                }
                [void][System.Reflection.Assembly]::LoadFile($winmd)

                $pdfPath = #{escape_ps_string(abs_pdf)}
                $outputPath = #{escape_ps_string(abs_png)}
                $pageIndex = #{page_idx}

                Log-Msg "PDF Path: $pdfPath"
                Log-Msg "Output Path: $outputPath"
                Log-Msg "Page Index: $pageIndex"

                if (-not (Test-Path $pdfPath)) {
                    throw "PDF source file does not exist at $pdfPath"
                }
                
                Log-Msg "Resolving StorageFile..."
                $storageFile = [Windows.Storage.StorageFile]::GetFileFromPathAsync($pdfPath).GetAwaiter().GetResult()
                
                Log-Msg "Loading PDF Document..."
                $pdfDoc = [Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($storageFile).GetAwaiter().GetResult()
                Log-Msg "PDF page count: $($pdfDoc.PageCount)"
                
                if ($pageIndex -ge $pdfDoc.PageCount) {
                    throw "Requested page index $pageIndex is out of range. Document has $($pdfDoc.PageCount) pages."
                }
                
                Log-Msg "Retrieving page $pageIndex..."
                $page = $pdfDoc.GetPage($pageIndex)
                
                Log-Msg "Creating in-memory stream..."
                $stream = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
                
                Log-Msg "Rendering page to stream..."
                $page.RenderToStreamAsync($stream).GetAwaiter().GetResult()

                Log-Msg "Saving stream to disk at $outputPath..."
                $fileStream = [System.IO.File]::Create($outputPath)
                $netStream = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
                $netStream.CopyTo($fileStream)
                $fileStream.Close()
                $netStream.Close()
                $stream.Close()
                $page.Dispose()
                $pdfDoc.Dispose()
                Log-Msg "Rendering finished successfully."
                exit 0
            } catch {
                $err = $_.Exception.ToString()
                Add-Content -Path $errPath -Value $err
                exit 1
            }
          POWERSHELL

          File.write(ps_script_path, ps_content)

          # Execute PowerShell script silently using WIN32OLE
          begin
            require 'win32ole'
            shell = WIN32OLE.new("WScript.Shell")
            
            # Run powershell directly without command-shell redirects, using double quotes for path
            cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File \"#{ps_script_path}\""
            
            puts "PDF Importer: Launching PowerShell rendering process..."
            exit_code = shell.Run(cmd, 0, true)
            
            # Read and print logs to SketchUp console
            out_content = File.read(stdout_log).strip rescue ""
            err_content = File.read(stderr_log).strip rescue ""
            
            puts "PDF Importer: PowerShell exit status: #{exit_code}"
            puts "PDF Importer: PowerShell stdout:\n#{out_content}" unless out_content.empty?
            puts "PDF Importer: PowerShell stderr:\n#{err_content}" unless err_content.empty?
            
            # Clean up temp files
            File.delete(stdout_log) if File.exist?(stdout_log)
            File.delete(stderr_log) if File.exist?(stderr_log)
            File.delete(ps_script_path) if File.exist?(ps_script_path)
            
            return exit_code == 0 && File.exist?(output_png_path)
          rescue StandardError => e
            puts "PDF Importer: Silent PowerShell execution failed: #{e.message}"
            # Clean up temp files
            File.delete(stdout_log) if File.exist?(stdout_log)
            File.delete(stderr_log) if File.exist?(stderr_log)
            File.delete(ps_script_path) if File.exist?(ps_script_path)
            
            # Last resort fallback: standard system call
            puts "PDF Importer: Trying fallback standard system call..."
            cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File \"#{ps_script_path}\""
            success = system(cmd)
            File.delete(ps_script_path) if File.exist?(ps_script_path)
            return success && File.exist?(output_png_path)
          end

        elsif Sketchup.platform == :platform_osx
          cmd = <<~APPLE
            osascript -e '
            use framework "Foundation"
            use framework "PDFKit"
            use framework "AppKit"

            set pdfURL to current application\x27s NSURL\x27s fileURLWithPath:"#{escape_applescript_string(abs_pdf)}"
            set pdfDoc to current application\x27s PDFDocument\x27s alloc()\x27s initWithURL:pdfURL
            set pdfPage to pdfDoc\x27s pageAtIndex:(#{page_number - 1})
            set bounds to pdfPage\x27s boundsForBox:(current application\x27s kPDFDisplayBoxMediaBox)
            set width to current application\x27s NSWidth(bounds)
            set height to current application\x27s NSHeight(bounds)

            # Render at 150 DPI (150/72 = 2.0833 scale)
            set scale to 2.0833
            set imgSize to current application\x27s NSMakeSize(width * scale, height * scale)
            set image to current application\x27s NSImage\x27s alloc()\x27s initWithSize:imgSize
            image\x27s lockFocus()
            set context to current application\x27s NSGraphicsContext\x27s currentContext()
            context\x27s setImageInterpolation:(current application\x27s NSImageInterpolationHigh)
            pdfPage\x27s drawWithBox:(current application\x27s kPDFDisplayBoxMediaBox) toContext:context
            image\x27s unlockFocus()

            set tiffData to image\x27s TIFFRepresentation()
            set imgRep to current application\x27s NSBitmapImageRep\x27s imageRepsWithData:tiffData\x27s objectAtIndex:0
            set pngData to imgRep\x27s representationUsingType:(current application\x27s NSPNGFileType) properties:(missing value)
            pngData\x27s writeToFile:"#{escape_applescript_string(abs_png)}" atomically:true
            '
          APPLE

          success = system(cmd)
          return success && File.exist?(output_png_path)
        end

        false
      end

      def self.escape_ps_string(str)
        "'" + str.gsub("'", "''") + "'"
      end

      def self.escape_applescript_string(str)
        str.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
      end

      # Import an image file onto the SketchUp ground plane
      # Returns true on success
      def self.import_as_image(model, image_path, settings)
        return false unless image_path && File.exist?(image_path)

        scale = (settings[:scale] || 1.0).to_f
        media_width = (settings[:page_width] || 612.0).to_f   # PDF points
        media_height = (settings[:page_height] || 792.0).to_f

        # Convert PDF points to inches, then apply user scale
        width_inches = (media_width / 72.0) * scale
        height_inches = (media_height / 72.0) * scale

        origin = Geom::Point3d.new(0, 0, 0)

        begin
          # add_image(path, origin, width, height)
          image = model.active_entities.add_image(image_path, origin, width_inches, height_inches)
          if image
            model.active_view.zoom(image)
            return true
          end
        rescue StandardError => e
          puts "PDF Importer: Image import error: #{e.message}"
        end

        false
      end

      # Auto-trace an image to create vector geometry in SketchUp.
      # Uses a simple edge detection and contour following approach.
      # Returns the number of edges created.
      def self.auto_trace(model, image_path, settings)
        return 0 unless image_path && File.exist?(image_path)

        scale = (settings[:scale] || 1.0).to_f
        threshold = (settings[:trace_threshold] || 128).to_i
        simplify = (settings[:trace_simplify] || 2.0).to_f
        media_width = (settings[:page_width] || 612.0).to_f
        media_height = (settings[:page_height] || 792.0).to_f

        # Load image using SketchUp's ImageRep (available since SU 2018)
        begin
          image_rep = Sketchup::ImageRep.new(image_path)
        rescue StandardError => e
          puts "PDF Importer: Cannot load image: #{e.message}"
          return 0
        end

        img_w = image_rep.width
        # Downsample resolution based on trace method (centerline needs more processing, outline can be larger)
        trace_method = settings[:trace_method] || 'centerline'
        max_dim = (trace_method == 'centerline') ? 900 : 1200

        if img_w > max_dim || img_h > max_dim
          downsample_factor = [img_w, img_h].max.to_f / max_dim
        else
          downsample_factor = 1.0
        end

        # Get raw pixel data (RGBA bytes as a String)
        pixel_data = image_rep.data
        row_padding = image_rep.row_padding

        # Build grayscale grid (downsampled)
        ds_w = (img_w / downsample_factor).to_i
        ds_h = (img_h / downsample_factor).to_i
        gray = Array.new(ds_h) { Array.new(ds_w, 255) }

        bytes_per_row = img_w * 4 + row_padding

        ds_h.times do |dy|
          start_y = (dy * downsample_factor).to_i
          end_y = ((dy + 1) * downsample_factor).to_i
          end_y = img_h if end_y > img_h
          
          ds_w.times do |dx|
            start_x = (dx * downsample_factor).to_i
            end_x = ((dx + 1) * downsample_factor).to_i
            end_x = img_w if end_x > img_w
            
            # Find the minimum (darkest) pixel in this block to preserve thin lines
            min_val = 255
            step = (downsample_factor / 3.0).clamp(1.0, 4.0).to_i
            
            (start_y...end_y).step(step) do |sy|
              (start_x...end_x).step(step) do |sx|
                offset = sy * bytes_per_row + sx * 4
                b = pixel_data.getbyte(offset) || 255
                g = pixel_data.getbyte(offset + 1) || 255
                r = pixel_data.getbyte(offset + 2) || 255
                val = (0.299 * r + 0.587 * g + 0.114 * b).to_i
                min_val = val if val < min_val
              end
            end
            
            gray[dy][dx] = min_val
          end
        end

        # Binary threshold
        binary = Array.new(ds_h) { |y|
          Array.new(ds_w) { |x|
            gray[y][x] < threshold ? 1 : 0
          }
        }

        # Edge or Centerline detection
        edges = []
        if trace_method == 'centerline'
          puts "PDF Importer: Running centerline thinning..."
          skeleton = zhang_suen_thinning(binary)
          (1...ds_h - 1).each do |y|
            (1...ds_w - 1).each do |x|
              edges << [x, y] if skeleton[y][x] == 1
            end
          end
        else
          puts "PDF Importer: Running outline edge detection..."
          (1...ds_h - 1).each do |y|
            (1...ds_w - 1).each do |x|
              if binary[y][x] == 1
                is_edge = binary[y-1][x] == 0 || binary[y+1][x] == 0 ||
                          binary[y][x-1] == 0 || binary[y][x+1] == 0
                edges << [x, y] if is_edge
              end
            end
          end
        end

        return 0 if edges.empty?

        # Convert edge pixels to SketchUp coordinates
        # Map image coordinates to PDF page size, then to inches
        x_scale = (media_width / 72.0 * scale) / ds_w
        y_scale = (media_height / 72.0 * scale) / ds_h

        # Group nearby edge pixels into chains using a simple scan-line approach
        chains = build_chains(edges, simplify)

        # Create geometry
        group = model.active_entities.add_group
        group.name = 'PDF Trace'
        entities = group.entities
        edge_count = 0

        chains.each do |chain|
          next if chain.length < 2

          # Simplify the chain
          simplified = douglas_peucker(chain, simplify)
          next if simplified.length < 2

          # Create edges
          (0...simplified.length - 1).each do |i|
            x1 = simplified[i][0] * x_scale
            y1 = (ds_h - simplified[i][1]) * y_scale  # Flip Y
            x2 = simplified[i+1][0] * x_scale
            y2 = (ds_h - simplified[i+1][1]) * y_scale

            pt1 = Geom::Point3d.new(x1, y1, 0)
            pt2 = Geom::Point3d.new(x2, y2, 0)

            dist = pt1.distance(pt2)
            next if dist < 0.01  # Skip tiny edges

            begin
              edge = entities.add_line(pt1, pt2)
              edge_count += 1 if edge
            rescue ArgumentError
              # Skip invalid edges
            end
          end
        end

        model.active_view.zoom(group) if edge_count > 0
        edge_count
      end

      private

      # Save a PDF image XObject to a temp file
      def self.save_image(img_info)
        stream = img_info[:stream]
        filter = img_info[:filter].compact

        # Determine the temp file extension and get data
        temp_dir = Dir.tmpdir rescue '/tmp'

        if filter.include?(:DCTDecode)
          # JPEG - the raw stream data IS the JPEG file
          ext = '.jpg'
          data = stream.data
        elsif filter.include?(:JPXDecode)
          # JPEG2000
          ext = '.jp2'
          data = stream.data
        else
          # Raw pixel data or other format - create BMP
          ext = '.bmp'
          begin
            data = create_bmp(stream, img_info[:width], img_info[:height])
          rescue StandardError => e
            puts "PDF Importer: BMP creation error: #{e.message}"
            return nil
          end
        end

        return nil unless data && data.length > 0

        temp_path = File.join(temp_dir, "pdf_importer_temp#{ext}")
        File.binwrite(temp_path, data)
        temp_path
      rescue StandardError => e
        puts "PDF Importer: Save image error: #{e.message}"
        nil
      end

      # Create a minimal BMP file from raw pixel data
      def self.create_bmp(stream, width, height)
        begin
          raw = stream.unfiltered_data
        rescue StandardError
          raw = stream.data
        end

        bpc = stream.hash[:BitsPerComponent] || 8
        cs = stream.hash[:ColorSpace]

        # Determine bytes per pixel
        case cs
        when :DeviceRGB
          bpp = 3
        when :DeviceGray
          bpp = 1
        when :DeviceCMYK
          bpp = 4
        else
          bpp = 3  # Assume RGB
        end

        # BMP format (bottom-up, BGR, padded to 4-byte boundary)
        row_size = ((width * 3 + 3) / 4) * 4
        pixel_data_size = row_size * height
        file_size = 54 + pixel_data_size

        bmp = String.new(encoding: 'ASCII-8BIT')

        # BMP File Header (14 bytes)
        bmp << 'BM'
        bmp << [file_size].pack('V')
        bmp << [0].pack('V')        # Reserved
        bmp << [54].pack('V')       # Pixel data offset

        # BMP Info Header (40 bytes)
        bmp << [40].pack('V')       # Header size
        bmp << [width].pack('V')    # Width
        bmp << [height].pack('V')   # Height (positive = bottom-up)
        bmp << [1].pack('v')        # Color planes
        bmp << [24].pack('v')       # Bits per pixel
        bmp << [0].pack('V')        # Compression (none)
        bmp << [pixel_data_size].pack('V')
        bmp << [2835].pack('V')     # H resolution (72 DPI)
        bmp << [2835].pack('V')     # V resolution
        bmp << [0].pack('V')        # Colors in palette
        bmp << [0].pack('V')        # Important colors

        # Pixel data (bottom-up)
        (height - 1).downto(0) do |y|
          width.times do |x|
            src_offset = (y * width + x) * bpp

            case bpp
            when 3
              r = raw.getbyte(src_offset) || 0
              g = raw.getbyte(src_offset + 1) || 0
              b = raw.getbyte(src_offset + 2) || 0
            when 1
              gray = raw.getbyte(src_offset) || 0
              r = g = b = gray
            when 4
              # CMYK to RGB (simplified)
              c = (raw.getbyte(src_offset) || 0) / 255.0
              m = (raw.getbyte(src_offset + 1) || 0) / 255.0
              yy = (raw.getbyte(src_offset + 2) || 0) / 255.0
              k = (raw.getbyte(src_offset + 3) || 0) / 255.0
              r = ((1 - c) * (1 - k) * 255).to_i
              g = ((1 - m) * (1 - k) * 255).to_i
              b = ((1 - yy) * (1 - k) * 255).to_i
            else
              r = g = b = 0
            end

            bmp << [b, g, r].pack('CCC')  # BMP is BGR
          end

          # Pad row to 4-byte boundary
          padding = row_size - width * 3
          bmp << "\0" * padding if padding > 0
        end

        bmp
      end

      # Build chains of connected edge pixels
      def self.build_chains(edges, min_dist)
        return [] if edges.empty?

        # Create a spatial index for fast neighbor lookup
        edge_set = {}
        edges.each { |e| edge_set[[e[0], e[1]]] = true }

        visited = {}
        chains = []

        edges.each do |start|
          next if visited[[start[0], start[1]]]

          chain = [start]
          visited[[start[0], start[1]]] = true
          current = start

          # Follow the chain in one direction
          loop do
            found_next = false
            # Check 8-connected neighbors
            [[-1,-1],[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0],[1,1]].each do |dx, dy|
              nx, ny = current[0] + dx, current[1] + dy
              if edge_set[[nx, ny]] && !visited[[nx, ny]]
                visited[[nx, ny]] = true
                chain << [nx, ny]
                current = [nx, ny]
                found_next = true
                break
              end
            end
            break unless found_next
          end

          chains << chain if chain.length >= 3
        end

        chains
      end

      # Douglas-Peucker line simplification
      def self.douglas_peucker(points, epsilon)
        return points if points.length <= 2

        # Find the point farthest from the line between first and last
        dmax = 0
        index = 0
        first = points.first
        last = points.last

        (1...points.length - 1).each do |i|
          d = perpendicular_distance(points[i], first, last)
          if d > dmax
            dmax = d
            index = i
          end
        end

        if dmax > epsilon
          left = douglas_peucker(points[0..index], epsilon)
          right = douglas_peucker(points[index..-1], epsilon)
          left[0...-1] + right
        else
          [first, last]
        end
      end

      def self.perpendicular_distance(point, line_start, line_end)
        x, y = point
        x1, y1 = line_start
        x2, y2 = line_end

        dx = x2 - x1
        dy = y2 - y1

        if dx == 0 && dy == 0
          return Math.sqrt((x - x1)**2 + (y - y1)**2)
        end

        ((dy * x - dx * y + x2 * y1 - y2 * x1).abs /
          Math.sqrt(dx**2 + dy**2))
      end

      # Thin a binary grid to a 1-pixel-wide skeleton using Zhang-Suen algorithm.
      def self.zhang_suen_thinning(binary)
        h = binary.length
        w = binary[0].length
        grid = binary.map(&:dup)
        
        # Limit iterations to prevent hanging on large/noisy images
        max_iterations = 25
        
        max_iterations.times do
          changed = false
          
          # Step 1: Mark pixels for deletion
          to_delete = []
          (1...h-1).each do |y|
            (1...w-1).each do |x|
              next if grid[y][x] == 0
              
              p2 = grid[y-1][x]
              p3 = grid[y-1][x+1]
              p4 = grid[y][x+1]
              p5 = grid[y+1][x+1]
              p6 = grid[y+1][x]
              p7 = grid[y+1][x-1]
              p8 = grid[y][x-1]
              p9 = grid[y-1][x-1]
              
              b = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9
              next unless b >= 2 && b <= 6
              
              # Number of 0-to-1 transitions in sequence p2 -> p3 -> p4 -> p5 -> p6 -> p7 -> p8 -> p9 -> p2
              seq = [p2, p3, p4, p5, p6, p7, p8, p9, p2]
              a = 0
              (0..7).each do |i|
                a += 1 if seq[i] == 0 && seq[i+1] == 1
              end
              next unless a == 1
              
              next unless p2 * p4 * p6 == 0
              next unless p4 * p6 * p8 == 0
              
              to_delete << [x, y]
            end
          end
          
          unless to_delete.empty?
            to_delete.each { |x, y| grid[y][x] = 0 }
            changed = true
          end
          
          # Step 2: Mark pixels for deletion
          to_delete = []
          (1...h-1).each do |y|
            (1...w-1).each do |x|
              next if grid[y][x] == 0
              
              p2 = grid[y-1][x]
              p3 = grid[y-1][x+1]
              p4 = grid[y][x+1]
              p5 = grid[y+1][x+1]
              p6 = grid[y+1][x]
              p7 = grid[y+1][x-1]
              p8 = grid[y][x-1]
              p9 = grid[y-1][x-1]
              
              b = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9
              next unless b >= 2 && b <= 6
              
              seq = [p2, p3, p4, p5, p6, p7, p8, p9, p2]
              a = 0
              (0..7).each do |i|
                a += 1 if seq[i] == 0 && seq[i+1] == 1
              end
              next unless a == 1
              
              next unless p2 * p4 * p8 == 0
              next unless p2 * p6 * p8 == 0
              
              to_delete << [x, y]
            end
          end
          
          unless to_delete.empty?
            to_delete.each { |x, y| grid[y][x] = 0 }
            changed = true
          end
          
          break unless changed
        end
        
        grid
      end

    end
  end
end
