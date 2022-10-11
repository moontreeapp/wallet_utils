/// calculates fees for transactions of various types

class TxGoal {
  final double rate;
  final String? name;
  const TxGoal(
    this.rate, [
    this.name,
  ]);

  int get minimumFee => (0.01 * satsPer).floor(); // relevance?

  /// 100,000,000 sats per RVN
  static int get satsPer => 100000000;
}

class TxGoals {
  static TxGoal cheap = TxGoal(hardRelayFee * 1.001, 'Cheap');
  static TxGoal standard = TxGoal(hardRelayFee * 1.1, 'Standard');
  static TxGoal fast = TxGoal(hardRelayFee * 1.5, 'Fast');

  /// 0.01 RVN = 1,000,000 sats
  /// example: https://rvn.cryptoscope.io/tx/?txid=3a880d09258075635e1565c06dce3f0091a67da987a63140a60f1d8f80a6625a
  /// 1.1 standard * 1000 * 192 bytes = 211,200 sats == 0.00211200 rvn
  static double get hardRelayFee => 1000;
}
