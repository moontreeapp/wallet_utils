import 'package:ravencoin_wallet/ravencoin_wallet.dart'
    show HDWallet, mainnet, testnet;

class Derive {
  static HDWallet getHDWallet(String pubkey, {bool useMainet = false}) =>
      HDWallet.fromBase58(pubkey, network: useMainet ? mainnet : testnet);

  static HDWallet deriveHDWallet(
    String pubkey,
    String path,
    int index, {
    bool useMainet = false,
  }) =>
      getHDWallet(pubkey, useMainet: useMainet).derivePath('$path/$index');
}
