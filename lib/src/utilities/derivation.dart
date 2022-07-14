class Derivation {
  static const accountNumber = 0;
  static const ravencoinNumber = 44;
  static const externalNumber = 0;
  static const internalNumber = 1;

  /// returns a full derivation path if the index is supplied
  static String getPath({
    int? index,
    int? chain,
    int? account,
    int? network,
    int? exposure,
    bool mainnet = true,
    bool external = true,
  }) =>
      "m/"
      "${chain ?? ravencoinNumber}'/"
      "${network ?? mainnetNumber(mainnet)}'/"
      "${account ?? accountNumber}'/"
      "${exposure ?? receiveNumber(external)}"
      "${index != null ? '/$index' : ''}";

  static int receiveNumber([bool external = true]) =>
      external ? externalNumber : internalNumber;
  static int mainnetNumber([bool mainnet = true]) => mainnet ? 175 : 1;
}
