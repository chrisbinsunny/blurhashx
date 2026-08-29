/// A pure Dart, platform-independent implementation of the BlurHash algorithm.
///
/// Compatible with the official BlurHash and NPM `blurhash` specifications.
library blurhashx;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'src/decoder.dart';
import 'src/encoder.dart';
import 'src/exception.dart';
import 'src/isolate.dart';

export 'src/exception.dart' show BlurHashException, BlurHashValidationResult;
export 'src/isolate.dart' show BlurHashEncodeParams, computeBlurHash;

/// Public facade for encoding and decoding BlurHash strings.
abstract final class BlurHash {
  /// Encodes raw image file bytes (JPEG, PNG, WebP, GIF, etc.) directly into a BlurHash string.
  ///
  /// Uses Flutter's native C++ Skia hardware-accelerated decoder (`dart:ui.ImageDescriptor`)
  /// to decode and downscale the image during DCT decoding in ~2-5ms, avoiding expensive
  /// full-resolution memory allocations or slow pure-Dart software decoders.
  static Future<String> encodeImageBytes(
    Uint8List imageBytes, {
    int? componentX,
    int? componentY,
    int maxDimension = 100,
  }) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(imageBytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);

    int targetWidth = descriptor.width;
    int targetHeight = descriptor.height;
    if (targetWidth > maxDimension || targetHeight > maxDimension) {
      if (targetWidth >= targetHeight) {
        targetHeight =
            (targetHeight * maxDimension / targetWidth).round().clamp(1, maxDimension);
        targetWidth = maxDimension;
      } else {
        targetWidth =
            (targetWidth * maxDimension / targetHeight).round().clamp(1, maxDimension);
        targetHeight = maxDimension;
      }
    }

    final codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw const BlurHashException('Failed to extract raw RGBA pixel data from decoded image');
    }
    final pixels = byteData.buffer.asUint8List();

    return encode(
      pixels,
      targetWidth,
      targetHeight,
      componentX: componentX,
      componentY: componentY,
      maxDimension: maxDimension,
    );
  }
  /// Encodes raw pixel data into a BlurHash string.
  ///
  /// - [pixels]: Raw image bytes. By default RGBA (4 bytes per pixel).
  /// - [width]: Image width in pixels (must be > 0).
  /// - [height]: Image height in pixels (must be > 0).
  /// - [componentX]: Number of DCT components along X axis (1..9). Defaults
  ///   to a value derived from the image's aspect ratio if omitted.
  /// - [componentY]: Number of DCT components along Y axis (1..9). Defaults
  ///   to a value derived from the image's aspect ratio if omitted.
  /// - [bytesPerPixel]: Number of bytes per pixel (default: 4 for RGBA, 3 for RGB).
  /// - [bytesPerRow]: Stride/byte width of each row if padding is present.
  /// - [maxDimension]: Long-edge cap used internally before running the DCT
  ///   (default: 100px).
  ///
  /// Runs synchronously on the calling isolate. Prefer [encodeAsync] when
  /// calling from a Flutter UI isolate.
  static String encode(
      Uint8List pixels,
      int width,
      int height, {
        int? componentX,
        int? componentY,
        int bytesPerPixel = 4,
        int? bytesPerRow,
        int maxDimension = 100,
      }) {
    return encodeBlurHash(
      pixels: pixels,
      width: width,
      height: height,
      componentX: componentX,
      componentY: componentY,
      bytesPerPixel: bytesPerPixel,
      bytesPerRow: bytesPerRow,
      maxDimension: maxDimension,
    );
  }

  /// Encodes on a background isolate where supported (falls back to
  /// synchronous encoding on web). Recommended for use on the UI isolate
  /// in Flutter apps — e.g. hashing thumbnails inline in a scroll view —
  /// so the DCT and downsample work never blocks a frame.
  ///
  /// Takes the same parameters as [encode].
  static Future<String> encodeAsync(
      Uint8List pixels,
      int width,
      int height, {
        int? componentX,
        int? componentY,
        int bytesPerPixel = 4,
        int? bytesPerRow,
        int maxDimension = 100,
      }) {
    return encodeBlurHashAsync(BlurHashEncodeParams(
      pixels: pixels,
      width: width,
      height: height,
      componentX: componentX,
      componentY: componentY,
      bytesPerPixel: bytesPerPixel,
      bytesPerRow: bytesPerRow,
      maxDimension: maxDimension,
    ));
  }

  /// Decodes a BlurHash string into raw RGBA pixel data.
  ///
  /// - [blurHash]: The BlurHash string to decode.
  /// - [width]: Target image width in pixels.
  /// - [height]: Target image height in pixels.
  /// - [punch]: Contrast multiplier for AC components (default: 1.0).
  ///
  /// Returns a [Uint8List] containing RGBA pixels of length `width * height * 4`.
  static Uint8List decode(
      String blurHash, {
        required int width,
        required int height,
        double punch = 1.0,
      }) {
    return decodeBlurHash(
      blurHash: blurHash,
      width: width,
      height: height,
      punch: punch,
    );
  }

  /// Checks if a string is a valid BlurHash.
  static bool isValid(String blurHash) {
    return validateBlurHashString(blurHash).isValid;
  }

  /// Validates a BlurHash string and returns a [BlurHashValidationResult] with diagnostic details.
  static BlurHashValidationResult validate(String blurHash) {
    return validateBlurHashString(blurHash);
  }

  /// Decodes the average 24-bit sRGB color of the BlurHash without full image rendering.
  static ({int r, int g, int b}) decodeAverageColor(String blurHash) {
    return decodeAverageColorFromBlurHash(blurHash);
  }

  /// Extracts the number of X and Y components encoded in a BlurHash string.
  static ({int componentX, int componentY}) components(String blurHash) {
    return extractComponentsFromBlurHash(blurHash);
  }
}