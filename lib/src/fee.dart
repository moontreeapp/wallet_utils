import 'package:wallet_utils/src/utilities/validation.dart' show satsPerCoin;

/// calculates fees for transactions of various types

const double _cheapFee = 1.001;
const double _standardFee = 1.1;
const double _fastFee = 1.5;

class FeeRate {
  final double modifier;
  final double? rateOverride;
  final String? name;
  const FeeRate({
    this.modifier = _standardFee,
    this.rateOverride,
    this.name,
  });

  double get rate => rateOverride ?? (hardRelayFee * modifier);

  /// relevance? we were able to send with fees 4x lower than this before.
  /// I think it's more of a guideline than a minimum fee since we've
  /// successfully ignored it until server2. maybe it's retail, the fee that
  /// suckers pay
  static int get minimumFee => (0.01 * satsPerCoin).floor();

  /// 0.01 RVN = 1,000,000 sats
  /// example: https://rvn.cryptoscope.io/tx/?txid=3a880d09258075635e1565c06dce3f0091a67da987a63140a60f1d8f80a6625a
  /// 1.1 standard * 1000 * 192 bytes = 211,200 sats == 0.00211200 rvn
  static double hardRelayFee = 1000;

  @override
  bool operator ==(Object feeRate) =>
      feeRate is FeeRate && rate == feeRate.rate && name == feeRate.name;

  @override
  int get hashCode => Object.hash(rate, name);
}

const cheapFee = const FeeRate(modifier: _cheapFee, name: 'Cheap');
const standardFee = const FeeRate(modifier: _standardFee, name: 'Standard');
const fastFee = const FeeRate(modifier: _fastFee, name: 'Fast');

class FeeRates {
  static FeeRate cheap = cheapFee;
  static FeeRate standard = standardFee;
  static FeeRate fast = fastFee;
}
