import 'dart:math' as math;
import 'dart:typed_data';

import 'base83.dart';
import 'color.dart';
import 'exception.dart';


/// Picks a sensible (componentX, componentY) pair for an image's aspect
/// ratio when the caller doesn't specify one explicitly.
///
/// Scales each axis by sqrt(aspectRatio) so the total component budget
/// (roughly baseComponents²) stays constant while detail is redistributed
/// toward whichever axis carries more of the image's extent — smoothly,
/// rather than snapping between fixed presets at arbitrary thresholds.
(int, int) _defaultComponents(double aspectRatio) {
  const baseComponents = 4.0;
  final sqrtRatio = math.sqrt(aspectRatio);
  final cx = (baseComponents * sqrtRatio).round().clamp(1, 9);
  final cy = (baseComponents / sqrtRatio).round().clamp(1, 9);
  return (cx, cy);
}


/// Encodes raw pixel data into a BlurHash string.
///
/// [pixels] contains raw pixel data (RGBA by default, where [bytesPerPixel] = 4).
/// [width] and [height] are the dimensions of the input image.
/// [componentX] and [componentY] specify the number of DCT components (1..9).
/// [bytesPerRow] can be specified if the pixel buffer has row padding.
/// [maxDimension] caps the long edge used for the DCT (default 100px, the
/// commonly recommended ceiling — BlurHash only resolves low-frequency
/// detail, so anything past this is wasted work).
String encodeBlurHash({
  required Uint8List pixels,
  required int width,
  required int height,
  int? componentX,
  int? componentY,
  int bytesPerPixel = 4,
  int? bytesPerRow,
  int maxDimension = 100,
}) {
  if (width < 1 || height < 1) {
    throw const BlurHashException('width and height must be greater than 0');
  }
  if (bytesPerPixel < 3) {
    throw const BlurHashException(
        'bytesPerPixel must be at least 3 (e.g. 3 for RGB, 4 for RGBA)');
  }

  final aspectRatio = width / height;
  final (defaultCx, defaultCy) = _defaultComponents(aspectRatio);
  final cx = componentX ?? defaultCx;
  final cy = componentY ?? defaultCy;

  if (cx < 1 || cx > 9 || cy < 1 || cy > 9) {
    throw const BlurHashException(
      'componentX and componentY must be between 1 and 9 (inclusive)',
    );
  }

  final actualBytesPerRow = bytesPerRow ?? (width * bytesPerPixel);
  final minLength = (height - 1) * actualBytesPerRow + width * bytesPerPixel;
  if (pixels.length < minLength) {
    throw BlurHashException(
      'Pixel buffer is too small (${pixels.length} bytes), expected at least $minLength bytes for ${width}x$height image with $bytesPerPixel bytes per pixel',
    );
  }

  int targetWidth = width;
  int targetHeight = height;
  if (width > maxDimension || height > maxDimension) {
    if (width >= height) {
      targetWidth = maxDimension;
      targetHeight = math.max(1, (maxDimension / aspectRatio).round());
    } else {
      targetHeight = maxDimension;
      targetWidth = math.max(1, (maxDimension * aspectRatio).round());
    }
  }

  // Box-filter downsample straight into *linear* light, in a single pass
  // over the source buffer. Every source pixel is linearised exactly once
  // and contributes to its target bucket's average — true area sampling,
  // not a single picked sample.
  final linR = Float64List(targetWidth * targetHeight);
  final linG = Float64List(targetWidth * targetHeight);
  final linB = Float64List(targetWidth * targetHeight);

  _boxDownsampleToLinear(
    pixels: pixels,
    width: width,
    height: height,
    bytesPerPixel: bytesPerPixel,
    bytesPerRow: actualBytesPerRow,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
    outR: linR,
    outG: linG,
    outB: linB,
  );

  // Precompute 1D cosine tables for the (now small) target dimensions.
  final cosX = List<Float64List>.generate(cx, (i) {
    final list = Float64List(targetWidth);
    for (var x = 0; x < targetWidth; x++) {
      list[x] = math.cos(math.pi * x * i / targetWidth);
    }
    return list;
  });

  final cosY = List<Float64List>.generate(cy, (j) {
    final list = Float64List(targetHeight);
    for (var y = 0; y < targetHeight; y++) {
      list[y] = math.cos(math.pi * y * j / targetHeight);
    }
    return list;
  });

  final totalComponents = cx * cy;
  final factorsR = Float64List(totalComponents);
  final factorsG = Float64List(totalComponents);
  final factorsB = Float64List(totalComponents);
  final scale = 1.0 / (targetWidth * targetHeight);

  // Separable 2D DCT: a row pass (O(cx*W*H)) followed by a column pass
  // (O(cx*cy*H)), instead of the naive O(cx*cy*W*H) nested loop. Same sum,
  // computed with far fewer multiply-adds — this is what makes the
  // box-filtered accuracy above affordable.
  final rowR = Float64List(cx * targetHeight);
  final rowG = Float64List(cx * targetHeight);
  final rowB = Float64List(cx * targetHeight);

  for (var y = 0; y < targetHeight; y++) {
    final rowOffset = y * targetWidth;
    for (var i = 0; i < cx; i++) {
      final cosXi = cosX[i];
      var r = 0.0, g = 0.0, b = 0.0;
      for (var x = 0; x < targetWidth; x++) {
        final c = cosXi[x];
        final idx = rowOffset + x;
        r += c * linR[idx];
        g += c * linG[idx];
        b += c * linB[idx];
      }
      final rIdx = i * targetHeight + y;
      rowR[rIdx] = r;
      rowG[rIdx] = g;
      rowB[rIdx] = b;
    }
  }

  for (var j = 0; j < cy; j++) {
    final cosYj = cosY[j];
    for (var i = 0; i < cx; i++) {
      final normalisation = (i == 0 && j == 0) ? 1.0 : 2.0;
      var r = 0.0, g = 0.0, b = 0.0;
      final base = i * targetHeight;
      for (var y = 0; y < targetHeight; y++) {
        final c = cosYj[y];
        r += c * rowR[base + y];
        g += c * rowG[base + y];
        b += c * rowB[base + y];
      }
      final factorIndex = j * cx + i;
      factorsR[factorIndex] = normalisation * r * scale;
      factorsG[factorIndex] = normalisation * g * scale;
      factorsB[factorIndex] = normalisation * b * scale;
    }
  }

  final hashBuffer = StringBuffer();

  // 1. Size flag (1 character)
  final sizeFlag = (cx - 1) + (cy - 1) * 9;
  hashBuffer.write(encode83(sizeFlag, 1));

  // 2. Maximum AC component value & 3. DC component
  final acCount = totalComponents - 1;
  final double maxAcScale;

  if (acCount > 0) {
    var actualMax = 0.0;
    for (var i = 1; i < totalComponents; i++) {
      actualMax = math.max(
        actualMax,
        math.max(
          factorsR[i].abs(),
          math.max(factorsG[i].abs(), factorsB[i].abs()),
        ),
      );
    }

    final quantisedMaxValue = math.max(
      0,
      math.min(82, (actualMax * 166.0 - 0.5).floor()),
    );
    maxAcScale = (quantisedMaxValue + 1) / 166.0;
    hashBuffer.write(encode83(quantisedMaxValue, 1));
  } else {
    maxAcScale = 1.0;
    hashBuffer.write(encode83(0, 1));
  }

  // Encode DC component (4 characters)
  final dcR = linearTosRGB(factorsR[0]);
  final dcG = linearTosRGB(factorsG[0]);
  final dcB = linearTosRGB(factorsB[0]);
  final dcValue = (dcR << 16) + (dcG << 8) + dcB;
  hashBuffer.write(encode83(dcValue, 4));

  // 4. Encode AC components (2 characters each)
  for (var i = 1; i < totalComponents; i++) {
    final qR = math.max(
      0,
      math.min(
          18, (signPow(factorsR[i] / maxAcScale, 0.5) * 9.0 + 9.5).floor()),
    );
    final qG = math.max(
      0,
      math.min(
          18, (signPow(factorsG[i] / maxAcScale, 0.5) * 9.0 + 9.5).floor()),
    );
    final qB = math.max(
      0,
      math.min(
          18, (signPow(factorsB[i] / maxAcScale, 0.5) * 9.0 + 9.5).floor()),
    );

    final acValue = qR * 361 + qG * 19 + qB;
    hashBuffer.write(encode83(acValue, 2));
  }

  return hashBuffer.toString();
}

/// Downsamples [pixels] into linear-light float buffers via true box-filter
/// area averaging: every source pixel is linearised exactly once and
/// accumulated into its target bucket, then buckets are divided by their
/// sample count. This is a single O(width*height) pass regardless of how
/// aggressive the shrink is.
void _boxDownsampleToLinear({
  required Uint8List pixels,
  required int width,
  required int height,
  required int bytesPerPixel,
  required int bytesPerRow,
  required int targetWidth,
  required int targetHeight,
  required Float64List outR,
  required Float64List outG,
  required Float64List outB,
}) {
  if (targetWidth == width && targetHeight == height) {
    for (var y = 0; y < height; y++) {
      final rowOffset = y * bytesPerRow;
      final dstRow = y * targetWidth;
      for (var x = 0; x < width; x++) {
        final idx = rowOffset + x * bytesPerPixel;
        final d = dstRow + x;
        outR[d] = sRGBToLinear(pixels[idx]);
        outG[d] = sRGBToLinear(pixels[idx + 1]);
        outB[d] = sRGBToLinear(pixels[idx + 2]);
      }
    }
    return;
  }

  final counts = Uint32List(targetWidth * targetHeight);

  for (var y = 0; y < height; y++) {
    final ty = (y * targetHeight ~/ height).clamp(0, targetHeight - 1);
    final rowOffset = y * bytesPerRow;
    final dstRowBase = ty * targetWidth;
    for (var x = 0; x < width; x++) {
      final tx = (x * targetWidth ~/ width).clamp(0, targetWidth - 1);
      final idx = rowOffset + x * bytesPerPixel;
      final d = dstRowBase + tx;
      outR[d] += sRGBToLinear(pixels[idx]);
      outG[d] += sRGBToLinear(pixels[idx + 1]);
      outB[d] += sRGBToLinear(pixels[idx + 2]);
      counts[d]++;
    }
  }

  for (var i = 0; i < outR.length; i++) {
    final n = counts[i];
    if (n > 0) {
      final inv = 1.0 / n;
      outR[i] *= inv;
      outG[i] *= inv;
      outB[i] *= inv;
    }
  }
}