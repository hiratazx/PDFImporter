<p align="center">
  <strong>🌐 Language / Bahasa:</strong>&nbsp;&nbsp;
  <a href="README.md">🇬🇧 English</a> ·
  <a href="README-ID.md">🇮🇩 Indonesia</a>
</p>

---

# PDF Importer untuk SketchUp

Ekstensi SketchUp **gratis dan open-source** yang mengimpor file PDF vektor sebagai geometri yang bisa diedit (edge, face, kurva).

Tidak perlu lagi membayar plugin impor PDF yang mahal — ekstensi ini melakukannya secara gratis!

![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Platform: SketchUp](https://img.shields.io/badge/Platform-SketchUp-red.svg)

## Fitur

- **Impor PDF vektor** sebagai geometri native SketchUp (edge, face)
- **Skala yang dapat dikonfigurasi** — atur faktor skala sesuai kebutuhan
- **Dukungan multi-halaman** — pilih halaman mana yang akan diimpor
- **Dukungan kurva Bézier** — kurva kubik diaproksimasi dengan resolusi yang dapat dikonfigurasi
- **Kontrol stroke & fill** — pilih untuk mengimpor outline, bentuk terisi, atau keduanya
- **Dukungan undo** — satu kali undo membatalkan seluruh impor
- **Tanpa dependensi eksternal** — semuanya sudah dibundel di dalam ekstensi

## Yang Dapat Diimpor

| Elemen | Didukung |
|--------|----------|
| Garis | ✅ |
| Persegi panjang | ✅ |
| Poligon | ✅ |
| Kurva Bézier kubik | ✅ (diaproksimasi) |
| Bentuk terisi | ✅ |
| Transformasi koordinat | ✅ |
| Teks | ❌ (teks tidak diimpor) |
| Gambar | ❌ |
| Gradien/transparansi | ❌ |

> **Catatan:** PDF harus mengandung **data vektor** (biasanya dari software CAD, Illustrator, atau sejenisnya). PDF hasil scan (yang pada dasarnya adalah gambar datar) tidak akan menghasilkan geometri apa pun.

## Instalasi

### Metode 1: Unduh file .rbz (Disarankan)

1. Buka halaman [Releases](https://github.com/hiratazx/PDFImporter/releases)
2. Unduh file `pdf_importer.rbz` terbaru
3. Buka SketchUp
4. Pergi ke **Extensions → Extension Manager**
5. Klik **Install Extension**
6. Pilih file `.rbz` yang sudah diunduh
7. Restart SketchUp

### Metode 2: Build dari Source

**Windows:**

```cmd
git clone https://github.com/hiratazx/PDFImporter.git
cd PDFImporter
build.bat
```

**Linux / macOS:**

```bash
git clone https://github.com/hiratazx/PDFImporter.git
cd PDFImporter
chmod +x build.sh
./build.sh
```

Kemudian instal file `pdf_importer.rbz` yang dihasilkan melalui Extension Manager.

## Penggunaan

1. Buka SketchUp
2. Pergi ke **Extensions → PDF Importer → Import PDF...**
3. Pilih file PDF Anda
4. Konfigurasi pengaturan impor:
   - **Faktor skala**: 1.0 = ukuran sebenarnya (1 PDF point = 1/72 inci)
   - **Halaman**: Pilih halaman yang akan diimpor (untuk PDF multi-halaman)
   - **Impor stroke**: Mengimpor outline path
   - **Impor fill**: Mengimpor bentuk terisi
   - **Segmen Bézier**: Lebih banyak segmen = kurva lebih halus
5. Klik **Import**
6. Geometri yang diimpor muncul sebagai grup di bidang tanah

### Mengatur Skala yang Benar

Setelah mengimpor, jika skalanya tidak tepat:

1. Pilih grup yang diimpor
2. Gunakan alat **Tape Measure**
3. Klik dua titik dengan dimensi yang diketahui
4. Ketik dimensi sebenarnya dan tekan Enter
5. Klik **Yes** ketika ditanya untuk mengubah ukuran

## Cara Kerja

Ekstensi ini menggunakan gem Ruby [pdf-reader](https://github.com/yob/pdf-reader) (dibundel di dalam ekstensi) untuk mem-parse content stream PDF. Prosesnya:

1. Membuka file PDF dan membaca metadata halaman
2. Menelusuri content stream PDF, menangkap operasi gambar:
   - `move_to`, `line_to` — garis lurus
   - `curve_to` — kurva Bézier kubik
   - `append_rectangle` — persegi panjang
   - `stroke`, `fill` — pewarnaan path
   - `concatenate_matrix` — transformasi koordinat
3. Mentransformasi semua koordinat melalui Current Transformation Matrix (CTM)
4. Mengkonversi koordinat PDF (point, Y-ke-atas) ke koordinat SketchUp (inci, bidang tanah)
5. Membuat edge, kurva, dan face SketchUp di dalam sebuah grup

## Persyaratan

- **SketchUp 2017+** (memerlukan `UI::HtmlDialog`)
- Berjalan di **Windows** dan **macOS**

## Lisensi

Proyek ini dilisensikan di bawah Lisensi MIT - lihat file [LICENSE](LICENSE) untuk detail.

## Kontribusi

Kontribusi sangat diterima! Silakan:

1. Fork repositori ini
2. Buat branch fitur (`git checkout -b feature/fitur-saya`)
3. Commit perubahan Anda (`git commit -am 'Tambahkan fitur saya'`)
4. Push ke branch (`git push origin feature/fitur-saya`)
5. Buka Pull Request

## Kredit

- [pdf-reader](https://github.com/yob/pdf-reader) — Parsing PDF (Lisensi MIT)
- [Ascii85](https://github.com/DataWraith/ascii85gem) — Encoding Ascii85 (Lisensi MIT)
- [Hashery](https://github.com/rubyworks/hashery) — LRU Hash (Lisensi BSD)
- [AFM](https://github.com/halfbyte/afm) — Adobe Font Metrics (Lisensi MIT)
