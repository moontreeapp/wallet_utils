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

  int get minimumFee => (0.01 * satsPer).floor(); // relevance?

  /// 100,000,000 sats per RVN
  static int get satsPer => 100000000;

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
