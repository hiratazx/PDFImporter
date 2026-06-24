<p align="center">
  <strong>🌐 Language / Bahasa:</strong>&nbsp;&nbsp;
  <a href="README.md">🇬🇧 English</a> ·
  <a href="README-ID.md">🇮🇩 Indonesia</a>
</p>

---

# PDF Importer for SketchUp

A **free and open-source** SketchUp extension that imports vector PDF files as editable geometry (edges, faces, curves).

No more paying for expensive PDF import plugins — this extension does it for free!

![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Platform: SketchUp](https://img.shields.io/badge/Platform-SketchUp-red.svg)

## Features

- **Import vector PDFs** as native SketchUp geometry (edges, faces)
- **Configurable scale** — set your own scale factor
- **Multi-page support** — choose which page to import
- **Bézier curve support** — cubic curves are approximated with configurable resolution
- **Stroke & fill control** — choose to import outlines, filled shapes, or both
- **Undo support** — single undo undoes the entire import
- **No external dependencies** — everything is bundled inside the extension

## What It Imports

| Element | Supported |
|---------|-----------|
| Lines | ✅ |
| Rectangles | ✅ |
| Polygons | ✅ |
| Cubic Bézier curves | ✅ (approximated) |
| Filled shapes | ✅ |
| Coordinate transforms | ✅ |
| Text | ❌ (text is not imported) |
| Images | ❌ |
| Gradients/transparency | ❌ |

> **Note:** The PDF must contain **vector data** (typically from CAD software, Illustrator, or similar). Scanned PDFs (which are essentially flat images) will not produce any geometry.

## Installation

### Method 1: Download the .rbz (Recommended)

1. Go to the [Releases](https://github.com/hiratazx/PDFImporter/releases) page
2. Download the latest `pdf_importer.rbz` file
3. Open SketchUp
4. Go to **Extensions → Extension Manager**
5. Click **Install Extension**
6. Select the downloaded `.rbz` file
7. Restart SketchUp

### Method 2: Build from Source

```bash
git clone https://github.com/hiratazx/PDFImporter.git
cd PDFImporter
chmod +x build.sh
./build.sh
```

Then install the generated `pdf_importer.rbz` file via Extension Manager.

## Usage

1. Open SketchUp
2. Go to **Extensions → PDF Importer → Import PDF...**
3. Select your PDF file
4. Configure import settings:
   - **Scale factor**: 1.0 = actual size (1 PDF point = 1/72 inch)
   - **Page**: Select which page to import (for multi-page PDFs)
   - **Import strokes**: Import path outlines
   - **Import fills**: Import filled shapes
   - **Bézier segments**: More segments = smoother curves
5. Click **Import**
6. The imported geometry appears as a group on the ground plane

### Setting the Correct Scale

After importing, if the scale isn't right:

1. Select the imported group
2. Use the **Tape Measure** tool
3. Click two points of a known dimension
4. Type the actual dimension and press Enter
5. Click **Yes** when asked to resize

## How It Works

The extension uses the [pdf-reader](https://github.com/yob/pdf-reader) Ruby gem (bundled inside the extension) to parse the PDF content stream. It:

1. Opens the PDF file and reads page metadata
2. Walks through the PDF content stream, intercepting drawing operations:
   - `move_to`, `line_to` — straight lines
   - `curve_to` — cubic Bézier curves
   - `append_rectangle` — rectangles
   - `stroke`, `fill` — path painting
   - `concatenate_matrix` — coordinate transformations
3. Transforms all coordinates through the Current Transformation Matrix (CTM)
4. Converts PDF coordinates (points, Y-up) to SketchUp coordinates (inches, ground plane)
5. Creates SketchUp edges, curves, and faces inside a group

## Requirements

- **SketchUp 2017+** (requires `UI::HtmlDialog`)
- Works on **Windows** and **macOS**

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Feel free to:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

## Credits

- [pdf-reader](https://github.com/yob/pdf-reader) — PDF parsing (MIT License)
- [Ascii85](https://github.com/DataWraith/ascii85gem) — Ascii85 encoding (MIT License)
- [Hashery](https://github.com/rubyworks/hashery) — LRU Hash (BSD License)
- [AFM](https://github.com/halfbyte/afm) — Adobe Font Metrics (MIT License)
