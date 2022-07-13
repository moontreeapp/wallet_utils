class Derivation {
  static const accountNumber = 0;
  static const ravencoinNumber = 44;
  static const externalNumber = 0;
  static const internalNumber = 1;

  static String getPath(
    int index, {
    bool mainnet = true,
    bool external = true,
  }) =>
      "m/"
      "$ravencoinNumber'/"
      "${mainnetNumber(mainnet)}'/"
      "$accountNumber'/"
      "${receiveNumber(external)}/"
      "$index";

  static int receiveNumber([bool external = true]) =>
      external ? externalNumber : internalNumber;
  static int mainnetNumber([bool mainnet = true]) => mainnet ? 175 : 1;
}
