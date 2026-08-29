import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:blurhashx/blurhashx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlurHashX Core Tests', () {
    test('Validates official sample BlurHash strings', () {
      const sample = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
      expect(BlurHash.isValid(sample), isTrue);

      final val = BlurHash.validate(sample);
      expect(val.isValid, isTrue);
      expect(val.errorReason, isNull);
    });

    test('Rejects invalid BlurHash strings with accurate diagnostics', () {
      expect(BlurHash.isValid(''), isFalse);
      expect(BlurHash.isValid('123'), isFalse);

      final emptyVal = BlurHash.validate('');
      expect(emptyVal.isValid, isFalse);
      expect(emptyVal.errorReason, isNotNull);

      // Invalid character outside base83
      final invalidCharVal = BlurHash.validate('LEHV6nWB2yk8pyo0adR*.7kCMdn!');
      expect(invalidCharVal.isValid, isFalse);
    });

    test('Extracts correct component counts', () {
      const sample = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
      final comps = BlurHash.components(sample);
      expect(comps.componentX, equals(4));
      expect(comps.componentY, equals(3));
    });

    test('Decodes average color in O(1)', () {
      const sample = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
      final avg = BlurHash.decodeAverageColor(sample);
      expect(avg.r, inInclusiveRange(0, 255));
      expect(avg.g, inInclusiveRange(0, 255));
      expect(avg.b, inInclusiveRange(0, 255));
    });

    test('Encodes and decodes flat color image', () {
      // 32x32 solid red RGBA image
      const int w = 32;
      const int h = 32;
      final pixels = Uint8List(w * h * 4);
      for (int i = 0; i < pixels.length; i += 4) {
        pixels[i] = 255;     // R
        pixels[i + 1] = 0;   // G
        pixels[i + 2] = 0;   // B
        pixels[i + 3] = 255; // A
      }

      final hash = BlurHash.encode(
        pixels,
        w,
        h,
        componentX: 3,
        componentY: 3,
      );

      expect(hash.isNotEmpty, isTrue);
      expect(BlurHash.isValid(hash), isTrue);

      final decoded = BlurHash.decode(hash, width: 16, height: 16);
      expect(decoded.length, equals(16 * 16 * 4));
      // First pixel should be predominantly red
      expect(decoded[0], greaterThan(200));
      expect(decoded[1], lessThan(50));
      expect(decoded[2], lessThan(50));
    });

    test('Encodes asynchronously via isolate', () async {
      const int w = 20;
      const int h = 20;
      final pixels = Uint8List(w * h * 4);
      for (int i = 0; i < pixels.length; i += 4) {
        pixels[i] = 100;
        pixels[i + 1] = 150;
        pixels[i + 2] = 200;
        pixels[i + 3] = 255;
      }

      final hash = await BlurHash.encodeAsync(
        pixels,
        w,
        h,
        componentX: 4,
        componentY: 3,
      );

      expect(hash.isNotEmpty, isTrue);
      expect(BlurHash.isValid(hash), isTrue);
    });

    test('Decodes with custom punch (contrast)', () {
      const sample = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
      final decodedNormal = BlurHash.decode(sample, width: 16, height: 16, punch: 1.0);
      final decodedPunched = BlurHash.decode(sample, width: 16, height: 16, punch: 1.5);

      expect(decodedNormal.length, equals(16 * 16 * 4));
      expect(decodedPunched.length, equals(16 * 16 * 4));
    });
  });
}
