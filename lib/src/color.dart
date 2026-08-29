import 'dart:math' as math;
import 'dart:typed_data';

/// Precomputed lookup table for sRGB (0..255) to Linear RGB (0.0..1.0).
final Float64List _sRGBToLinearTable = () {
  final table = Float64List(256);
  for (var i = 0; i < 256; i++) {
    final v = i / 255.0;
    if (v <= 0.04045) {
      table[i] = v / 12.92;
    } else {
      table[i] = math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }
  }
  return table;
}();

/// Converts an 8-bit sRGB color value (0..255) to a linear RGB float (0.0..1.0).
double sRGBToLinear(int value) {
  if (value <= 0) return 0.0;
  if (value >= 255) return 1.0;
  return _sRGBToLinearTable[value];
}

/// Converts a linear RGB float value (0.0..1.0) back to an 8-bit sRGB color (0..255).
int linearTosRGB(double value) {
  final v = value < 0.0 ? 0.0 : (value > 1.0 ? 1.0 : value);
  final double srgb;
  if (v <= 0.0031308) {
    srgb = v * 12.92;
  } else {
    srgb = 1.055 * math.pow(v, 1.0 / 2.4) - 0.055;
  }
  final int byte = (srgb * 255.0 + 0.5).floor();
  return byte < 0 ? 0 : (byte > 255 ? 255 : byte);
}

/// Calculates [sign(val) * (|val| ^ exp)], preserving the sign of [val].
double signPow(double val, double exp) {
  if (val == 0.0) return 0.0;
  final sign = val < 0.0 ? -1.0 : 1.0;
  return sign * math.pow(val.abs(), exp).toDouble();
}
