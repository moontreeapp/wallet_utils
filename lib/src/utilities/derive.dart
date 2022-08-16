import 'package:ravencoin_wallet/ravencoin_wallet.dart'
    show HDWallet, mainnet, testnet;

class Derive {
  static HDWallet walletFromPubkey(String pubkey, {bool useMainet = false}) =>
      HDWallet.fromBase58(pubkey, network: useMainet ? mainnet : testnet);

  static HDWallet subWallet({
    String? pubkey,
    HDWallet? hdWallet,
    required String path,
    required int index,
    bool useMainet = false,
  }) =>
      hdWallet != null
          ? hdWallet.derivePath('$path/$index')
          : walletFromPubkey(pubkey!, useMainet: useMainet)
              .derivePath('$path/$index');

  /// returns the next HD wallet in the derivation path,
  /// along with its derivation path as the key to the map.
  static Map<String, HDWallet> subHdWallet({
    String? pubkey,
    HDWallet? hdWallet,
    required String path,
    required int index,
    bool useMainet = false,
  }) =>
      hdWallet != null
          ? hdWallet.deriveNextHD('$path/$index')
          : walletFromPubkey(pubkey!, useMainet: useMainet)
              .deriveNextHD('$path/$index');
}
