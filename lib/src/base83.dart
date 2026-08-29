import 'dart:typed_data';
import 'exception.dart';

/// Base83 character set according to the official BlurHash specification.
const String _base83Alphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#\$%*+,-.:;=?@[]^_{|}~';

/// Precomputed lookup table for character code to Base83 digit value (-1 if invalid).
final Int8List _charToValueTable = () {
  final table = Int8List(128)..fillRange(0, 128, -1);
  for (var i = 0; i < _base83Alphabet.length; i++) {
    final codeUnit = _base83Alphabet.codeUnitAt(i);
    if (codeUnit < 128) {
      table[codeUnit] = i;
    }
  }
  return table;
}();

/// Encodes an integer [value] into a Base83 string of exact [length].
String encode83(int value, int length) {
  final buffer = StringBuffer();
  for (var i = 1; i <= length; i++) {
    var divisor = 1;
    for (var d = 0; d < length - i; d++) {
      divisor *= 83;
    }
    final digit = (value ~/ divisor) % 83;
    buffer.write(_base83Alphabet[digit]);
  }
  return buffer.toString();
}

/// Decodes a Base83 [string] into an integer.
/// Throws a [BlurHashException] if any character is not in the Base83 alphabet.
int decode83(String string) {
  var value = 0;
  for (var i = 0; i < string.length; i++) {
    final codeUnit = string.codeUnitAt(i);
    final digit = codeUnit < 128 ? _charToValueTable[codeUnit] : -1;
    if (digit == -1) {
      throw BlurHashException(
        'Invalid Base83 character "${string[i]}" at index $i',
        string,
      );
    }
    value = value * 83 + digit;
  }
  return value;
}

/// Returns whether a character is valid Base83.
bool isValidBase83Char(int codeUnit) {
  return codeUnit >= 0 && codeUnit < 128 && _charToValueTable[codeUnit] != -1;
}
