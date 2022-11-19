import 'dart:typed_data';
import 'dart:math';

//const SATOSHI_MAX = 21 * 1e14;
//21,000,000.00000000
//2,100,000,000,000,000
//->
const SATOSHI_MAX = 21 * 1e17;
//21,000,000,000.00000000
//2,100,000,000,000,000,000
//    9,007,199,254,740,991  // isUint(value, 53) < SATOSHI_MAX
//

bool isShatoshi(int value) {
  return /*isUint(value, 53) &&*/ value <= SATOSHI_MAX;
}

bool isUint(int value, int bit) {
  return (value >= 0 && value <= pow(2, bit) - 1);
}

bool isHash160bit(Uint8List value) {
  return value.length == 20;
}

bool isHash256bit(Uint8List value) {
  return value.length == 32;
}
