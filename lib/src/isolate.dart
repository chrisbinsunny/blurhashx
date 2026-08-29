import 'dart:isolate';
import 'dart:typed_data';

import 'encoder.dart';

/// Parameter bundle for running [encodeBlurHash] off the calling isolate.
///
/// Isolate entry points (both `Isolate.run` and Flutter's `compute()`)
/// require a single top-level/static function taking one argument, so
/// inputs are bundled here. [Uint8List] is transferred efficiently
/// (zero-copy where the platform supports it) across isolate boundaries.
class BlurHashEncodeParams {
  final Uint8List pixels;
  final int width;
  final int height;
  final int? componentX;
  final int? componentY;
  final int bytesPerPixel;
  final int? bytesPerRow;
  final int maxDimension;

  const BlurHashEncodeParams({
    required this.pixels,
    required this.width,
    required this.height,
    this.componentX,
    this.componentY,
    this.bytesPerPixel = 4,
    this.bytesPerRow,
    this.maxDimension = 100,
  });
}

/// Top-level entry point suitable for `Isolate.run()` or Flutter's
/// `compute()`.
///
/// Flutter usage (if you prefer Flutter's isolate pooling):
/// ```dart
/// import 'package:flutter/foundation.dart' show compute;
///
/// final hash = await compute(
///   computeBlurHash,
///   BlurHashEncodeParams(pixels: pixels, width: width, height: height),
/// );
/// ```
String computeBlurHash(BlurHashEncodeParams params) {
  return encodeBlurHash(
    pixels: params.pixels,
    width: params.width,
    height: params.height,
    componentX: params.componentX,
    componentY: params.componentY,
    bytesPerPixel: params.bytesPerPixel,
    bytesPerRow: params.bytesPerRow,
    maxDimension: params.maxDimension,
  );
}

/// Runs [encodeBlurHash] on a background isolate when supported.
///
/// On platforms without isolate support (currently: web), this falls
/// back to running synchronously on the calling isolate — encoding is
/// fast enough post-downsample that this is a reasonable degradation,
/// but callers on hot code paths on web may still want to throttle.
Future<String> encodeBlurHashAsync(BlurHashEncodeParams params) async {
  try {
    return await Isolate.run(() => computeBlurHash(params));
  } on UnsupportedError {
    return computeBlurHash(params);
  }
}