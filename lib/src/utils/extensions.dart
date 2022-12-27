import 'dart:convert';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:collection/collection.dart';

extension StringBytesExtension on String {
  Uint8List get bytesUint8 => Uint8List.fromList(bytes);
  Uint8List get hexBytes => Uint8List.fromList(hex.decode(this));
  List<int> get bytes => utf8.encode(this);
}

extension Uint8ListExtension on Uint8List {
  String toHex() {
    return hex.encode(this);
  }

  bool equals(Object? other) {
    Uint8List otherList;
    if (other is ByteData) {
      otherList = other.buffer.asUint8List();
    } else if (other is List<int>) {
      otherList = Uint8List.fromList(other);
    } else {
      return false;
    }
    if (length != otherList.length) return false;
    return !IterableZip([this, otherList])
        .any((element) => element[0] != element[1]);
  }
}
