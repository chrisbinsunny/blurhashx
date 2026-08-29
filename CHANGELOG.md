## 1.0.0

* Initial release of `blurhashx`:
  * High-performance BlurHash encoding and decoding with hardware-accelerated image decoding via `dart:ui.ImageDescriptor`.
  * Added `BlurHash.encodeImageBytes()` to directly encode raw file bytes (JPEG, PNG, WebP, GIF, etc.) in ~5ms.
  * Separable 2D Discrete Cosine Transform (DCT) and linear-light box-filter downsampling.
  * Precomputed 256-element sRGB-to-Linear RGB lookup tables (LUT) and 1D cosine lookup tables.
  * 100% compatible with the official BlurHash and NPM `blurhash` specifications.
  * Background isolate execution via `BlurHash.encodeAsync()`.
  * Support for customizable `componentX` and `componentY`.
  * Comprehensive validation, $O(1)$ average color decoding, and error diagnostics.
