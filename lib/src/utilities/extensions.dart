import 'package:wallet_utils/src/utilities/validation.dart' show satsPerCoin;

extension AmountToSatsExtension on double {
  int get asSats => (this * satsPerCoin).floor();
}

extension SatsToAmountExtension on int {
  double get asCoin => this / satsPerCoin;
}
