import 'dart:math' as math;
import 'dart:typed_data';

import 'base83.dart';
import 'color.dart';
import 'exception.dart';

/// Validates a BlurHash string and returns a [BlurHashValidationResult].
BlurHashValidationResult validateBlurHashString(String blurHash) {
  if (blurHash.length < 6) {
    return BlurHashValidationResult.invalid(
      'BlurHash string must be at least 6 characters long (got ${blurHash.length})',
    );
  }

  for (var i = 0; i < blurHash.length; i++) {
    final codeUnit = blurHash.codeUnitAt(i);
    if (!isValidBase83Char(codeUnit)) {
      return BlurHashValidationResult.invalid(
        'Invalid Base83 character "${blurHash[i]}" at index $i',
      );
    }
  }

  final sizeFlag = decode83(blurHash[0]);
  final componentY = sizeFlag ~/ 9 + 1;
  final componentX = (sizeFlag % 9) + 1;
  final expectedLength = 4 + 2 * componentX * componentY;

  if (blurHash.length != expectedLength) {
    return BlurHashValidationResult.invalid(
      'BlurHash length mismatch: got ${blurHash.length} characters, expected $expectedLength for ${componentX}x$componentY components',
    );
  }

  return BlurHashValidationResult.valid;
}

/// Decodes a BlurHash string into raw RGBA pixel data.
///
/// [blurHash] is the input BlurHash string.
/// [width] and [height] are the target image dimensions.
/// [punch] adjusts the contrast of the AC components (default is 1.0).
Uint8List decodeBlurHash({
  required String blurHash,
  required int width,
  required int height,
  double punch = 1.0,
}) {
  final validation = validateBlurHashString(blurHash);
  if (!validation.isValid) {
    throw BlurHashException(validation.errorReason!, blurHash);
  }

  if (width < 1 || height < 1) {
    throw const BlurHashException('width and height must be greater than 0');
  }

  final sizeFlag = decode83(blurHash[0]);
  final componentY = sizeFlag ~/ 9 + 1;
  final componentX = (sizeFlag % 9) + 1;
  final totalComponents = componentX * componentY;

  final quantisedMaxValue = decode83(blurHash[1]);
  final maxAcScale = (quantisedMaxValue + 1) / 166.0;

  final factorsR = Float64List(totalComponents);
  final factorsG = Float64List(totalComponents);
  final factorsB = Float64List(totalComponents);

  // Decode DC component
  final dcValue = decode83(blurHash.substring(2, 6));
  final dcR = dcValue >> 16;
  final dcG = (dcValue >> 8) & 255;
  final dcB = dcValue & 255;

  factorsR[0] = sRGBToLinear(dcR);
  factorsG[0] = sRGBToLinear(dcG);
  factorsB[0] = sRGBToLinear(dcB);

  // Decode AC components
  final punchScale = maxAcScale * punch;
  for (var i = 1; i < totalComponents; i++) {
    final acValue = decode83(blurHash.substring(4 + i * 2, 6 + i * 2));
    final qR = acValue ~/ 361;
    final qG = (acValue ~/ 19) % 19;
    final qB = acValue % 19;

    factorsR[i] = signPow((qR - 9) / 9.0, 2.0) * punchScale;
    factorsG[i] = signPow((qG - 9) / 9.0, 2.0) * punchScale;
    factorsB[i] = signPow((qB - 9) / 9.0, 2.0) * punchScale;
  }

  // Precompute 1D cosine tables for target dimensions
  final cosX = List<Float64List>.generate(componentX, (i) {
    final list = Float64List(width);
    for (var x = 0; x < width; x++) {
      list[x] = math.cos(math.pi * x * i / width);
    }
    return list;
  });

  final cosY = List<Float64List>.generate(componentY, (j) {
    final list = Float64List(height);
    for (var y = 0; y < height; y++) {
      list[y] = math.cos(math.pi * y * j / height);
    }
    return list;
  });

  final pixels = Uint8List(width * height * 4);

  // Separable inverse DCT. For each row, first collapse the Y-frequency
  // terms into `componentX` intermediates (cheap: componentY terms each),
  // then expand those intermediates across the row's width. This avoids
  // recomputing the full componentX*componentY basis sum per pixel.
  final interR = Float64List(componentX);
  final interG = Float64List(componentX);
  final interB = Float64List(componentX);

  for (var y = 0; y < height; y++) {
    for (var i = 0; i < componentX; i++) {
      var r = 0.0;
      var g = 0.0;
      var b = 0.0;
      for (var j = 0; j < componentY; j++) {
        final cosYVal = cosY[j][y];
        final factorIndex = j * componentX + i;
        r += factorsR[factorIndex] * cosYVal;
        g += factorsG[factorIndex] * cosYVal;
        b += factorsB[factorIndex] * cosYVal;
      }
      interR[i] = r;
      interG[i] = g;
      interB[i] = b;
    }

    final rowOffset = y * width * 4;
    for (var x = 0; x < width; x++) {
      var r = 0.0;
      var g = 0.0;
      var b = 0.0;
      for (var i = 0; i < componentX; i++) {
        final cosXVal = cosX[i][x];
        r += interR[i] * cosXVal;
        g += interG[i] * cosXVal;
        b += interB[i] * cosXVal;
      }

      final pixelIndex = rowOffset + x * 4;
      pixels[pixelIndex] = linearTosRGB(r);
      pixels[pixelIndex + 1] = linearTosRGB(g);
      pixels[pixelIndex + 2] = linearTosRGB(b);
      pixels[pixelIndex + 3] = 255;
    }
  }

  return pixels;
}

/// Decodes the average 24-bit sRGB color of a BlurHash without full rendering.
({int r, int g, int b}) decodeAverageColorFromBlurHash(String blurHash) {
  final validation = validateBlurHashString(blurHash);
  if (!validation.isValid) {
    throw BlurHashException(validation.errorReason!, blurHash);
  }

  final dcValue = decode83(blurHash.substring(2, 6));
  return (
    r: dcValue >> 16,
    g: (dcValue >> 8) & 255,
    b: dcValue & 255,
  );
}

/// Extracts the number of X and Y components from a BlurHash string.
({int componentX, int componentY}) extractComponentsFromBlurHash(
  String blurHash,
) {
  final validation = validateBlurHashString(blurHash);
  if (!validation.isValid) {
    throw BlurHashException(validation.errorReason!, blurHash);
  }

  final sizeFlag = decode83(blurHash[0]);
  return (
    componentX: (sizeFlag % 9) + 1,
    componentY: sizeFlag ~/ 9 + 1,
  );
}