# PDF Importer Extension for SketchUp
# Free and Open Source - MIT License
# https://github.com/hiratazx/PDFImporter
#
# Registrar file - registers the extension with SketchUp.

require 'sketchup.rb'
require 'extensions.rb'

module OpenSourceDev
  module PDFImporter
    PLUGIN_DIR = File.dirname(__FILE__)
    PLUGIN_NAME = 'PDF Importer'.freeze
    PLUGIN_VERSION = '1.0.0'.freeze
    PLUGIN_DESCRIPTION = 'Import vector PDF files as editable SketchUp geometry (edges, faces, curves). Free and open source.'.freeze
    PLUGIN_CREATOR = 'hiratazx'.freeze

    path = File.join(PLUGIN_DIR, 'pdf_importer', 'main')
    extension = SketchupExtension.new(PLUGIN_NAME, path)
    extension.creator     = PLUGIN_CREATOR
    extension.version     = PLUGIN_VERSION
    extension.description = PLUGIN_DESCRIPTION
    extension.copyright   = "#{PLUGIN_CREATOR} - MIT License"

    Sketchup.register_extension(extension, true)
  end
end
