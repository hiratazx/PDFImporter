#!/bin/bash
# Build script for PDF Importer SketchUp Extension
# Creates a pdf_importer.rbz file ready for installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
OUTPUT_FILE="${SCRIPT_DIR}/pdf_importer.rbz"

echo "=== PDF Importer Build Script ==="
echo ""

# Clean previous build
if [ -d "$BUILD_DIR" ]; then
    rm -rf "$BUILD_DIR"
fi
if [ -f "$OUTPUT_FILE" ]; then
    rm -f "$OUTPUT_FILE"
fi

# Create build directory
mkdir -p "$BUILD_DIR"

# Copy registrar file
echo "Copying registrar file..."
cp "${SCRIPT_DIR}/pdf_importer.rb" "$BUILD_DIR/"

# Copy support folder
echo "Copying extension files..."
cp -r "${SCRIPT_DIR}/pdf_importer" "$BUILD_DIR/"

# Remove any __pycache__, .git, or other unwanted files
find "$BUILD_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find "$BUILD_DIR" -name ".DS_Store" -delete 2>/dev/null || true
find "$BUILD_DIR" -name "*.pyc" -delete 2>/dev/null || true

# Create the .rbz (which is just a .zip)
echo "Creating .rbz package..."
cd "$BUILD_DIR"
zip -r "$OUTPUT_FILE" pdf_importer.rb pdf_importer/ -x "*.git*"
cd "$SCRIPT_DIR"

# Clean up build directory
rm -rf "$BUILD_DIR"

# Show results
echo ""
echo "=== Build Complete ==="
echo "Output: $OUTPUT_FILE"
echo "Size: $(du -h "$OUTPUT_FILE" | cut -f1)"
echo ""
echo "To install:"
echo "  1. Open SketchUp"
echo "  2. Extensions > Extension Manager"
echo "  3. Install Extension"
echo "  4. Select: $OUTPUT_FILE"
