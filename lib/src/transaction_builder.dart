import 'dart:typed_data';
import 'dart:convert';

import 'package:bs58check/bs58check.dart' as bs58check;
import 'package:collection/collection.dart';
import 'package:hex/hex.dart';
import 'package:wallet_utils/src/utils/constants/op.dart';

import 'utils/script.dart' as bscript;
import 'ecpair.dart';
import 'models/networks.dart';
import 'transaction.dart';
import 'address.dart';
import 'payments/index.dart' show PaymentData;
import 'payments/p2pkh.dart';
import 'payments/p2wpkh.dart';
import 'classify.dart';
import 'assets.dart';

class TransactionBuilder {
  NetworkType network;
  String chainName;
  int maximumFeeRate;
  List<Input> _inputs = [];
  Transaction? _tx;
  Map _prevTxSet = {};

  TransactionBuilder({
    this.network = mainnet,
    this.chainName = 'ravencoin',
    this.maximumFeeRate = 2500,
    int version = 2,
  }) {
    this._inputs = [];
    this._tx = Transaction();
    this._tx!.version = version;
  }

  List<Input> get inputs => _inputs;

  factory TransactionBuilder.fromRawInfo(
      String rawHex,
      Iterable<Uint8List?> prevOutScripts,
      Iterable<String?> prevOutTypes,
      NetworkType network) {
    final tx = Transaction.fromHex(rawHex);
    final txb = TransactionBuilder(network: network);
    txb.setVersion(tx.version);
    txb.setLockTime(tx.locktime);

    tx.outs.forEach((txOut) {
      txb.addOutput(txOut.script, txOut.value);
    });

    IterableZip([tx.ins, prevOutScripts, prevOutTypes].cast()).forEach((input) {
      final Input txIn = input[0] as Input;
      final Uint8List? prevOutScript = input[1] as Uint8List?;
      final String? prevOutType = input[2] as String?;

      txb._addInputUnsafe(
          txIn.hash!,
          txIn.index,
          Input(
              sequence: txIn.sequence,
              witness: txIn.witness,
              prevOutScript: prevOutScript,
              prevOutType: prevOutType));
    });

    return txb;
  }

  factory TransactionBuilder.fromTransaction(Transaction transaction,
      [NetworkType network = mainnet]) {
    final txb = TransactionBuilder(network: network);
    // Copy transaction fields
    txb.setVersion(transaction.version);
    txb.setLockTime(transaction.locktime);

    // Copy outputs (done first to avoid signature invalidation)
    transaction.outs.forEach((txOut) {
      txb.addOutput(txOut.script, txOut.value);
    });

    transaction.ins.forEach((txIn) {
      txb._addInputUnsafe(
          txIn.hash!,
          txIn.index,
          Input(
              sequence: txIn.sequence,
              script: txIn.script,
              witness: txIn.witness));
    });

    // fix some things not possible through the public API
    // print(txb.toString());
    // txb.__INPUTS.forEach((input, i) => {
    //   fixMultisigOrder(input, transaction, i);
    // });

    return txb;
  }

  setVersion(int version) {
    if (version < 0 || version > 0xFFFFFFFF)
      throw ArgumentError('Expected Uint32');
    _tx!.version = version;
  }

  setLockTime(int locktime) {
    if (locktime < 0 || locktime > 0xFFFFFFFF)
      throw ArgumentError('Expected Uint32');
    // if any signatures exist, throw
    if (this._inputs.map((input) {
      if (input.signatures == null) return false;
      return input.signatures!.map((s) {
        return s != null;
      }).contains(true);
    }).contains(true)) {
      throw ArgumentError('No, this would invalidate signatures');
    }
    _tx!.locktime = locktime;
  }

  int addMemo(dynamic data, {int? offset}) {
    if (data is String) {
      data = utf8.encode(data);
    } else if (!(data is Uint8List)) {
      throw ArgumentError('Memo can only be ascii or bytes');
    }
    if (data.length > 80) {
      throw ArgumentError(
          'OP_RETURN trivial data cannot be more that 80 bytes');
    }

    var script = bscript.compile([
      OPS['OP_RETURN'],
      data,
    ]);

    return _tx!.addChangeForAssetCreationOrReissuance(
        (offset == null ? 0 : offset), script, 0);
  }

  int generateCreateQualifierVouts(
      dynamic newAssetTo, int value, String assetName, Uint8List? ipfsData) {
    var assetScriptPubKey;
    if (newAssetTo is String) {
      assetScriptPubKey = Address.addressToOutputScript(newAssetTo, network);
    } else if (newAssetTo is Uint8List) {
      assetScriptPubKey = newAssetTo;
    } else {
      throw ArgumentError('newAssetTo Address invalid');
    }

    if (!_canModifyOutputs()) {
      throw ArgumentError('No, this would invalidate signatures');
    }
    if (_tx!.outs.isNotEmpty) {
      throw ArgumentError('This transaction already has outputs!');
    }

    final burnScriptPubKey = Address.addressToOutputScript(
        network.burnAddresses.issueQualifier, network);

    assetScriptPubKey = generateAssetCreateScript(
        assetScriptPubKey, chainName, assetName, value, 0, false, ipfsData);

    _tx!.addOutput(burnScriptPubKey, network.burnAmounts.issueQualifier);
    return _tx!.addOutput(assetScriptPubKey, 0);
  }

  int generateCreateSubQualifierVouts(dynamic newAssetTo, dynamic parentAssetTo,
      int value, String parentName, String assetName, Uint8List? ipfsData) {
    var assetScriptPubKey;
    var ownerScriptPubKey;
    if (newAssetTo is String) {
      assetScriptPubKey = Address.addressToOutputScript(newAssetTo, network);
    } else if (newAssetTo is Uint8List) {
      assetScriptPubKey = newAssetTo;
    } else {
      throw ArgumentError('newAssetTo Address invalid');
    }
    if (parentAssetTo is String) {
      ownerScriptPubKey = Address.addressToOutputScript(parentAssetTo, network);
    } else if (newAssetTo is Uint8List) {
      ownerScriptPubKey = parentAssetTo;
    } else {
      throw ArgumentError('newAssetTo Address invalid');
    }

    if (!_canModifyOutputs()) {
      throw ArgumentError('No, this would invalidate signatures');
    }
    if (_tx!.outs.isNotEmpty) {
      throw ArgumentError('This transaction already has outputs!');
    }

    final burnScriptPubKey = Address.addressToOutputScript(
        network.burnAddresses.issueSubQualifier, network);

    ownerScriptPubKey = generateAssetTransferScript(
        parentAssetTo, chainName, parentName, 100000000);
    assetScriptPubKey = generateAssetCreateScript(
        assetScriptPubKey, chainName, assetName, value, 0, false, ipfsData);

    _tx!.addOutput(burnScriptPubKey, network.burnAmounts.issueSubQualifier);
    _tx!.addOutput(ownerScriptPubKey, 0);
    return _tx!.addOutput(assetScriptPubKey, 0);
  }

  int generateCreateRestrictedVouts(
      dynamic newAssetTo,
      dynamic parentAssetTo,
      int value,
      int divisibility,
      bool reissuable,
      Uint8List? ipfsData,
      String assetName,
      String? verifier) {
    var assetScriptPubKey;
    var ownerScriptPubKey;

    if (newAssetTo is String) {
      assetScriptPubKey = Address.addressToOutputScript(newAssetTo, network);
    } else if (newAssetTo is Uint8List) {
      assetScriptPubKey = newAssetTo;
    } else {
      throw ArgumentError('newAssetTo Address invalid');
    }

    if (parentAssetTo is String) {
      ownerScriptPubKey = Address.addressToOutputScript(parentAssetTo, network);
    } else if (newAssetTo is Uint8List) {
      ownerScriptPubKey = parentAssetTo;
    } else {
      throw ArgumentError('newAssetTo Address invalid');
    }

    if (!_canModifyOutputs()) {
      throw ArgumentError('No, this would invalidate signatures');
    }
    if (_tx!.outs.isNotEmpty) {
      throw ArgumentError('This transaction already has outputs!');
    }

    final burnScriptPubKey = Address.addressToOutputScript(
        network.burnAddresses.issueRestricted, network);
    final verifierScriptPubKey = generateNullVerifierTag(
        (verifier == null || verifier.isEmpty) ? 'true' : verifier);
    assetScriptPubKey = generateAssetCreateScript(assetScriptPubKey, chainName,
        assetName, value, divisibility, reissuable, ipfsData);
    ownerScriptPubKey = generateAssetTransferScript(
        ownerScriptPubKey, chainName, assetName.substring(1) + '!', 100000000);

    _tx!.addOutput(burnScriptPubKey, network.burnAmounts.issueRestricted);
    _tx!.addOutput(ownerScriptPubKey, 0);
    _tx!.addOutput(verifierScriptPubKey, 0);
    return _tx!.addOutput(assetScriptPubKey, 0);
  }

  int generateReissueRestrictedVouts(
      dynamic newAssetTo,
      dynamic parentAssetTo,
      int originalSats,
      int satsAdded,
      int old_divisibility,
      int divisibility,
      bool reissuable,
      Uint8List? ipfsData,
      String assetName,
      String? verifier) {
    var assetScriptPubKey;
    var ownerScriptPubKey;

    if (newAssetTo is String) {
      assetScriptPubKey = Address.addressToOutputScript(newAssetTo, network);
    } else if (newAssetTo is Uint8List) {
      assetScriptPubKey = newAssetTo;
    } else {
      throw ArgumentError('newAssetTo Address invalid');
    }

    if (parentAssetTo is String) {
      ownerScriptPubKey = Address.addressToOutputScript(parentAssetTo, network);
    } else if (newAssetTo is Uint8List) {
      ownerScriptPubKey = parentAssetTo;
    } else {
      throw ArgumentError('newAssetTo Address invalid');
    }

    if (!_canModifyOutputs()) {
      throw ArgumentError('No, this would invalidate signatures');
    }
    if (_tx!.outs.isNotEmpty) {
      throw ArgumentError('This transaction already has outputs!');
    }

    final burnScriptPubKey =
        Address.addressToOutputScript(network.burnAddresses.reissue, network);
    final verifierScriptPubKey = generateNullVerifierTag(
        (verifier == null || verifier.isEmpty) ? 'true' : verifier);
    assetScriptPubKey = generateAssetReissueScript(
        assetScriptPubKey,
        chainName,
        assetName,
        originalSats,
        satsAdded,
        old_divisibility,
        divisibility,
        reissuable,
        ipfsData);
    ownerScriptPubKey = generateAssetTransferScript(
        ownerScriptPubKey, chainName, assetName.substring(1) + '!', 100000000);

    _tx!.addOutput(burnScriptPubKey, network.burnAmounts.reissue);
    _tx!.addOutput(ownerScriptPubKey, 0);
    if (verifier != null && verifier.isNotEmpty) {
      _tx!.addOutput(verifierScriptPubKey, 0);
    }
    return _tx!.addOutput(assetScriptPubKey, 0);
  }

  int generateQualifyAddressVouts(
      dynamic qualifierTo, String assetName, dynamic h160ToQualify, bool tag) {
    var qualifierPubKey;
    var modifiedh160;
    if (qualifierTo is String) {
      qualifierPubKey = Address.addressToOutputScript(qualifierTo, network);
    } else if (qualifierTo is Uint8List) {
      qualifierPubKey = qualifierTo;
    } else {
      throw ArgumentError('newAssetTo Address invalid');
    }
    if (h160ToQualify is String) {
      modifiedh160 = bs58check.base58.decode(h160ToQualify);
      modifiedh160 = modifiedh160.sublist(1, modifiedh160.length - 4);
    } else if (h160ToQualify is Uint8List) {
      modifiedh160 = h160ToQualify;
    } else {
      throw ArgumentError('h160ToQualify must be the h160 or an address');
    }

    if (!_canModifyOutputs()) {
      throw ArgumentError('No, this would invalidate signatures');
    }
    if (_tx!.outs.isNotEmpty) {
      throw ArgumentError('This transaction already has outputs!');
    }

    final verifierScriptPubKey =
        generateNullQualifierTag(assetName, modifiedh160, tag);
    final qualifierScriptPubKey = generateAssetTransferScript(
        qualifierPubKey,
        chainName,
        assetName[0] == '\$' ? assetName.substring(1) + '!' : assetName,
        100000000);
    final burnScriptPubKey =
        Address.addressToOutputScript(network.burnAddresses.addTag, network);

    _tx!.addOutput(qualifierScriptPubKey, 0);
    _tx!.addOutput(verifierScriptPubKey, 0);
    return _tx!.addOutput(burnScriptPubKey, network.burnAmounts.addTag);
  }

  // Note: this function generates all of the vouts for you. No other vouts may be added.
  // Last two vouts must be the asset generations.
  // Use Transaction.addChangeForAssetCreation to safely add.
  int generateCreateAssetVouts(
      dynamic newAssetTo,
      dynamic ownershipAssetTo,
      int value,
      String assetName,
      int divisibility,
      bool reissuable,
      Uint8List? ipfsData) {
    var assetScriptPubKey;
    var ownershipScriptPubKey;
    if (newAssetTo is String) {
      assetScriptPubKey = Address.addressToOutputScript(newAssetTo, network);
    } else if (newAssetTo is Uint8List) {
      assetScriptPubKey = newAssetTo;
    } else {
      throw ArgumentError('newAssetTo Address invalid');
    }
    if (ownershipAssetTo is String) {
      ownershipScriptPubKey =
          Address.addressToOutputScript(ownershipAssetTo, network);
    } else if (ownershipAssetTo is Uint8List) {
      ownershipScriptPubKey = ownershipAssetTo;
    } else {
      throw ArgumentError('ownershipAssetTo Address invalid');
    }
    if (!_canModifyOutputs()) {
      throw ArgumentError('No, this would invalidate signatures');
    }
    if (_tx!.outs.isNotEmpty) {
      throw ArgumentError('This transaction already has outputs!');
    }
    assetScriptPubKey = generateAssetCreateScript(assetScriptPubKey, chainName,
        assetName, value, divisibility, reissuable, ipfsData);
    ownershipScriptPubKey = generateAssetOwnershipScript(
        ownershipScriptPubKey, chainName, assetName);
    final burnScriptPubKey =
        Address.addressToOutputScript(network.burnAddresses.issueMain, network);

    _tx!.addOutput(burnScriptPubKey, network.burnAmounts.issueMain);
    _tx!.addOutput(ownershipScriptPubKey, 0);
    return _tx!.addOutput(assetScriptPubKey, 0);
  }

  int generateCreateSubAssetVouts(
      dynamic newAssetTo,
      dynamic ownershipAssetTo,
      dynamic parentOwnershipAssetTo,
      int value,
      String ownerName,
      String assetName,
      int divisibility,
      bool reissuable,
      Uint8List? ipfsData) {
    var assetScriptPubKey;
    var ownershipScriptPubKey;
    var parentOwnershipScriptPubKey;
    if (newAssetTo is String) {
      assetScriptPubKey = Address.addressToOutputScript(newAssetTo, network);
    } else if (newAssetTo is Uint8List) {
      assetScriptPubKey = newAssetTo;
    } else {
      throw ArgumentError('newAssetTo Address invalid');
    }
    if (ownershipAssetTo is String) {
      ownershipScriptPubKey =
          Address.addressToOutputScript(ownershipAssetTo, network);
    } else if (ownershipAssetTo is Uint8List) {
      ownershipScriptPubKey = ownershipAssetTo;
    } else {
      throw ArgumentError('ownershipAssetTo Address invalid');
    }
    if (parentOwnershipAssetTo is String) {
      parentOwnershipScriptPubKey =
          Address.addressToOutputScript(parentOwnershipAssetTo, network);
    } else if (parentOwnershipAssetTo is Uint8List) {
      parentOwnershipScriptPubKey = parentOwnershipAssetTo;
    } else {
      throw ArgumentError('ownershipAssetTo Address invalid');
    }
    if (!_canModifyOutputs()) {
      throw ArgumentError('No, this would invalidate signatures');
    }
    if (_tx!.outs.isNotEmpty) {
      throw ArgumentError('This transaction already has outputs!');
    }
    assetScriptPubKey = generateAssetCreateScript(assetScriptPubKey, chainName,
        assetName, value, divisibility, reissuable, ipfsData);
    ownershipScriptPubKey = generateAssetOwnershipScript(
        ownershipScriptPubKey, chainName, assetName);
    parentOwnershipScriptPubKey = generateAssetTransferScript(
        parentOwnershipScriptPubKey, chainName, ownerName + '!', 100000000);
    final burnScriptPubKey =
        Address.addressToOutputScript(network.burnAddresses.issueSub, network);

    _tx!.addOutput(burnScriptPubKey, network.burnAmounts.issueSub);
    _tx!.addOutput(parentOwnershipScriptPubKey, 0);
    _tx!.addOutput(ownershipScriptPubKey, 0);
    return _tx!.addOutput(assetScriptPubKey, 0);
  }

  // For unique and message assets
  int generateCreateChildAssetVouts(
      dynamic newAssetTo,
      dynamic parentOwnershipAssetTo,
      String ownerName,
      String assetName,
      Uint8List? ipfsData) {
    var assetScriptPubKey;
    var parentOwnershipScriptPubKey;
    if (newAssetTo is String) {
      assetScriptPubKey = Address.addressToOutputScript(newAssetTo, network);
    } else if (newAssetTo is Uint8List) {
      assetScriptPubKey = newAssetTo;
    } else {
      throw ArgumentError('newAssetTo Address invalid');
    }
    if (parentOwnershipAssetTo is String) {
      parentOwnershipScriptPubKey =
          Address.addressToOutputScript(parentOwnershipAssetTo, network);
    } else if (parentOwnershipAssetTo is Uint8List) {
      parentOwnershipScriptPubKey = parentOwnershipAssetTo;
    } else {
      throw ArgumentError('ownershipAssetTo Address invalid');
    }
    if (!_canModifyOutputs()) {
      throw ArgumentError('No, this would invalidate signatures');
    }
    if (_tx!.outs.isNotEmpty) {
      throw ArgumentError('This transaction already has outputs!');
    }
    // Message channels cannot have associated IPFS data
    var isMessage = assetName.contains('~');
    assetScriptPubKey = generateAssetCreateScript(assetScriptPubKey, chainName,
        assetName, 100000000, 0, false, isMessage ? null : ipfsData);
    parentOwnershipScriptPubKey = generateAssetTransferScript(
        parentOwnershipScriptPubKey, chainName, ownerName + '!', 100000000);
    final burnScriptPubKey = Address.addressToOutputScript(
        isMessage
            ? network.burnAddresses.issueMessage
            : network.burnAddresses.issueUnique,
        network);

    _tx!.addOutput(
        burnScriptPubKey,
        isMessage
            ? network.burnAmounts.issueMessage
            : network.burnAmounts.issueUnique);
    _tx!.addOutput(parentOwnershipScriptPubKey, 0);
    return _tx!.addOutput(assetScriptPubKey, 0);
  }

  int generateCreateReissueVouts(
      dynamic newAssetTo,
      dynamic ownershipAssetTo,
      int originalSats,
      int satsAdded,
      String assetName,
      int original_divisibility,
      int new_divisibility,
      bool reissuable,
      Uint8List? ipfsData) {
    var assetScriptPubKey;
    var ownershipScriptPubKey;
    if (newAssetTo is String) {
      assetScriptPubKey = Address.addressToOutputScript(newAssetTo, network);
    } else if (newAssetTo is Uint8List) {
      assetScriptPubKey = newAssetTo;
    } else {
      throw ArgumentError('newAssetTo Address invalid');
    }
    if (ownershipAssetTo is String) {
      ownershipScriptPubKey =
          Address.addressToOutputScript(ownershipAssetTo, network);
    } else if (ownershipAssetTo is Uint8List) {
      ownershipScriptPubKey = ownershipAssetTo;
    } else {
      throw ArgumentError('ownershipAssetTo Address invalid');
    }
    if (!_canModifyOutputs()) {
      throw ArgumentError('No, this would invalidate signatures');
    }
    if (_tx!.outs.isNotEmpty) {
      throw ArgumentError('This transaction already has outputs!');
    }
    assetScriptPubKey = generateAssetReissueScript(
        assetScriptPubKey,
        chainName,
        assetName,
        originalSats,
        satsAdded,
        original_divisibility,
        new_divisibility,
        reissuable,
        ipfsData);

    // Transfer an ownership asset with a value of 1
    // (Ownership assets have a virtual value of 100000000 sats).
    ownershipScriptPubKey = generateAssetTransferScript(
        ownershipScriptPubKey, chainName, assetName + '!', 100000000);
    final burnScriptPubKey =
        Address.addressToOutputScript(network.burnAddresses.reissue, network);

    _tx!.addOutput(burnScriptPubKey, network.burnAmounts.reissue);
    _tx!.addOutput(ownershipScriptPubKey, 0);
    return _tx!.addOutput(assetScriptPubKey, 0);
  }

  // Note: this function only works with RVN vouts and asset (t)ransfer vouts
  // Other types of scripts must be manually input in the *data* parameter.
  int addOutput(dynamic data, int? value,
      {String? asset, Uint8List? memo, int? expiry}) {
    var scriptPubKey;
    if (data is String) {
      scriptPubKey = Address.addressToOutputScript(data, network);
      if (asset != null && value != null && scriptPubKey != null) {
        // Replace script with asset transfer and reset value to 0.
        scriptPubKey = generateAssetTransferScript(
            scriptPubKey, chainName, asset, value,
            ipfsData: memo, expireEpoch: expiry);
        value = 0;
      }
    } else if (data is Uint8List) {
      scriptPubKey = data;
    } else {
      throw ArgumentError('Address invalid');
    }
    if (!_canModifyOutputs()) {
      throw ArgumentError('No, this would invalidate signatures');
    }
    return _tx!.addOutput(scriptPubKey, value);
  }

  int addChangeToAssetCreationOrReissuance(int offset, dynamic data, int? value,
      {String? asset, Uint8List? memo, int? expiry}) {
    var scriptPubKey;
    if (data is String) {
      scriptPubKey = Address.addressToOutputScript(data, network);
    } else if (data is Uint8List) {
      scriptPubKey = data;
    } else {
      throw ArgumentError('Address invalid');
    }

    if (asset != null) {
      scriptPubKey = generateAssetTransferScript(
          scriptPubKey, chainName, asset, value!,
          ipfsData: memo, expireEpoch: expiry);
      value = 0;
    }

    if (!_canModifyOutputs()) {
      throw ArgumentError('No, this would invalidate signatures');
    }
    return _tx!
        .addChangeForAssetCreationOrReissuance(offset, scriptPubKey, value);
  }

  int addInput(dynamic txHash, int vout,
      [int? sequence, Uint8List? prevOutScript]) {
    if (!_canModifyInputs()) {
      throw ArgumentError('No, this would invalidate signatures');
    }
    Uint8List hash;
    var value;
    if (txHash is String) {
      hash = Uint8List.fromList(HEX.decode(txHash).reversed.toList());
    } else if (txHash is Uint8List) {
      hash = txHash;
    } else if (txHash is Transaction) {
      final txOut = txHash.outs[vout];
      prevOutScript = txOut.script;
      value = txOut.value;
      hash = txHash.getHash();
    } else {
      throw ArgumentError('txHash invalid');
    }
    return _addInputUnsafe(hash, vout,
        Input(sequence: sequence, prevOutScript: prevOutScript, value: value));
  }

  /// TODO: WIP sign rewrite
  signRaw(
      {required int vin,
      required ECPair keyPair,
      int? hashType,
      Uint8List? prevOutScriptOverride,
      String? asset,
      int? assetAmount,
      required Uint8List assetLiteral}) {
    if (keyPair.network.toString().compareTo(network.toString()) != 0)
      throw ArgumentError('Inconsistent network');
    if (vin >= _inputs.length) throw ArgumentError('No input at index: $vin');
    hashType = hashType ?? SIGHASH_ALL;
    if (this._needsOutputs(hashType))
      throw ArgumentError('Transaction needs outputs');
    final input = _inputs[vin];
    final ourPubKey = keyPair.publicKey;
    if (!_canSign(input)) {
      if (input.prevOutScript != null && input.prevOutType != null) {
        var type = classifyOutput(input.prevOutScript!);
        if (type == SCRIPT_TYPES['P2WPKH']) {
          throw Exception('not implemented');
          /*
          input.prevOutType = SCRIPT_TYPES['P2WPKH'];
          input.hasWitness = true;
          input.signatures = [null];
          input.pubkeys = [ourPubKey];
          input.signScript =
              P2PKH(data: PaymentData(pubkey: ourPubKey), network: this.network)
                  .data
                  .output;
          */
        } else {
          // DRY CODE
          Uint8List? prevOutScript = prevOutScriptOverride ??
              pubkeyToOutputScript(ourPubKey, asset, assetAmount, assetLiteral);
          input.prevOutType = SCRIPT_TYPES['P2PKH'];
          input.signatures = [null];
          input.pubkeys = [ourPubKey];
          input.signScript = prevOutScript;
        }
      } else {
        Uint8List? prevOutScript = prevOutScriptOverride ??
            pubkeyToOutputScript(ourPubKey, asset, assetAmount, assetLiteral);
        input.prevOutType = SCRIPT_TYPES['P2PKH'];
        input.signatures = [null];
        input.pubkeys = [ourPubKey];
        input.signScript = prevOutScript;
      }
    }
    var signatureHash;
    if (input.hasWitness) {
      throw Exception('not implemented');
      /* comment to hide dead code
      signatureHash = this
          ._tx!
          .hashForWitnessV0(vin, input.signScript!, input.value!, hashType);
          */
    } else {
      signatureHash =
          this._tx!.hashForSignature(vin, input.signScript, hashType);
    }

    // enforce in order signing of public keys
    var signed = false;
    for (var i = 0; i < input.pubkeys!.length; i++) {
      if (HEX.encode(ourPubKey!).compareTo(HEX.encode(input.pubkeys![i]!)) !=
          0) {
        continue;
      }
      if (input.signatures![i] != null)
        throw ArgumentError('Signature already exists');
      final signature = keyPair.sign(signatureHash);
      input.signatures![i] = bscript.encodeSignature(signature, hashType);
      signed = true;
    }
    if (!signed) throw ArgumentError('Key pair cannot sign for this input');
  }

  /*
  sign(
      {required int vin,
      required ECPair keyPair,
      Uint8List? redeemScript,
      int? witnessValue,
      Uint8List? witnessScript,
      int? hashType,
      Uint8List? prevOutScriptOverride,
      String? asset,
      Uint8List? assetLiteral}) {
    if (keyPair.network.toString().compareTo(network.toString()) != 0)
      throw ArgumentError('Inconsistent network');
    if (vin >= _inputs.length) throw ArgumentError('No input at index: $vin');
    hashType = hashType ?? SIGHASH_ALL;
    if (this._needsOutputs(hashType))
      throw ArgumentError('Transaction needs outputs');
    final input = _inputs[vin];
    final ourPubKey = keyPair.publicKey;
    if (!_canSign(input)) {
      if (witnessValue != null) {
        input.value = witnessValue;
      }
      if (redeemScript != null && witnessScript != null) {
        // ignore: todo
        // TODO p2wsh
      }
      if (redeemScript != null) {
        // ignore: todo
        // TODO
      }
      if (witnessScript != null) {
        // ignore: todo
        // TODO
      }
      if (input.prevOutScript != null && input.prevOutType != null) {
        var type = classifyOutput(input.prevOutScript!);
        if (type == SCRIPT_TYPES['P2WPKH']) {
          throw Exception('not implemented');
          input.prevOutType = SCRIPT_TYPES['P2WPKH'];
          input.hasWitness = true;
          input.signatures = [null];
          input.pubkeys = [ourPubKey];
          input.signScript =
              P2PKH(data: PaymentData(pubkey: ourPubKey), network: this.network)
                  .data
                  .output;
        } else {
          // DRY CODE
          Uint8List? prevOutScript =
              prevOutScriptOverride ?? pubkeyToOutputScript(ourPubKey);
          input.prevOutType = SCRIPT_TYPES['P2PKH'];
          input.signatures = [null];
          input.pubkeys = [ourPubKey];
          input.signScript = prevOutScript;
        }
      } else {
        Uint8List? prevOutScript =
            prevOutScriptOverride ?? pubkeyToOutputScript(ourPubKey);
        input.prevOutType = SCRIPT_TYPES['P2PKH'];
        input.signatures = [null];
        input.pubkeys = [ourPubKey];
        input.signScript = prevOutScript;
      }
    }
    var signatureHash;
    if (input.hasWitness) {
      throw Exception('not implemented');
      signatureHash = this
          ._tx!
          .hashForWitnessV0(vin, input.signScript!, input.value!, hashType);
    } else {
      signatureHash =
          this._tx!.hashForSignature(vin, input.signScript, hashType);
    }

    // enforce in order signing of public keys
    var signed = false;
    for (var i = 0; i < input.pubkeys!.length; i++) {
      if (HEX.encode(ourPubKey!).compareTo(HEX.encode(input.pubkeys![i]!)) !=
          0) {
        continue;
      }
      if (input.signatures![i] != null)
        throw ArgumentError('Signature already exists');
      final signature = keyPair.sign(signatureHash);
      input.signatures![i] = bscript.encodeSignature(signature, hashType);
      signed = true;
    }
    if (!signed) throw ArgumentError('Key pair cannot sign for this input');
  }
  */

  Transaction build() {
    return _build(false);
  }

  Transaction buildIncomplete() {
    return _build(true);
  }

  Transaction buildSpoofedSigs() {
    return _build(false, spoof_p2pkh_signature: true);
  }

  Transaction _build(bool allowIncomplete, {bool? spoof_p2pkh_signature}) {
    if (!allowIncomplete) {
      if (_tx!.ins.length == 0)
        throw ArgumentError('Transaction has no inputs');
      if (_tx!.outs.length == 0)
        throw ArgumentError('Transaction has no outputs');
    }

    final tx = Transaction.clone(_tx!);

    for (var i = 0; i < _inputs.length; i++) {
      if (_inputs[i].pubkeys != null &&
          _inputs[i].signatures != null &&
          _inputs[i].pubkeys!.length != 0 &&
          _inputs[i].signatures!.length != 0) {
        if (_inputs[i].prevOutType == SCRIPT_TYPES['P2PKH']) {
          P2PKH payment = P2PKH(
              data: PaymentData(
                  pubkey: _inputs[i].pubkeys![0],
                  signature: _inputs[i].signatures![0]),
              asset: null,
              assetAmount: null,
              assetLiteral: Uint8List(0),
              network: network);
          tx.setInputScript(i, payment.data.input);
          tx.setWitness(i, payment.data.witness);
        } else if (_inputs[i].prevOutType == SCRIPT_TYPES['P2WPKH']) {
          P2WPKH payment = P2WPKH(
              data: PaymentData(
                  pubkey: _inputs[i].pubkeys![0],
                  signature: _inputs[i].signatures![0]),
              network: network);
          tx.setInputScript(i, payment.data.input);
          tx.setWitness(i, payment.data.witness);
        }
      } else if (spoof_p2pkh_signature != null && spoof_p2pkh_signature) {
        // For P2PKH, the unlocking script is 106-107 bytes long
        tx.setInputScript(i, Uint8List.fromList(List<int>.filled(107, 0)));
      } else if (!allowIncomplete) {
        throw ArgumentError('Transaction is not complete');
      }
    }

    if (!allowIncomplete) {
      // do not rely on this, its merely a last resort
      if (_overMaximumFees(tx.virtualSize())) {
        throw ArgumentError('Transaction has absurd fees');
      }
    }

    return tx;
  }

  bool _overMaximumFees(int bytes) {
    int incoming = _inputs.fold(0, (cur, acc) => cur + (acc.value ?? 0));
    int outgoing = _tx!.outs.fold(0, (cur, acc) => cur + (acc.value ?? 0));
    int fee = incoming - outgoing;
    int feeRate = fee ~/ bytes;
    return feeRate > maximumFeeRate;
  }

  bool _canModifyInputs() {
    return _inputs.every((input) {
      if (input.signatures == null) return true;
      return input.signatures!.every((signature) {
        if (signature == null) return true;
        return _signatureHashType(signature) & SIGHASH_ANYONECANPAY != 0;
      });
    });
  }

  bool _canModifyOutputs() {
    final nInputs = _tx!.ins.length;
    final nOutputs = _tx!.outs.length;
    return _inputs.every((input) {
      if (input.signatures == null) return true;
      return input.signatures!.every((signature) {
        if (signature == null) return true;
        final hashType = _signatureHashType(signature);
        final hashTypeMod = hashType & 0x1f;
        if (hashTypeMod == SIGHASH_NONE) return true;
        if (hashTypeMod == SIGHASH_SINGLE) {
          // if SIGHASH_SINGLE is set, and nInputs > nOutputs
          // some signatures would be invalidated by the addition
          // of more outputs
          return nInputs <= nOutputs;
        }
        return false;
      });
    });
  }

  bool _needsOutputs(int signingHashType) {
    if (signingHashType == SIGHASH_ALL) {
      return this._tx!.outs.length == 0;
    }
    // if inputs are being signed with SIGHASH_NONE, we don't strictly need outputs
    // .build() will fail, but .buildIncomplete() is OK
    return (this._tx!.outs.length == 0) &&
        _inputs.map((input) {
          if (input.signatures == null || input.signatures!.length == 0)
            return false;
          return input.signatures!.map((signature) {
            if (signature == null) return false; // no signature, no issue
            final hashType = _signatureHashType(signature);
            if (hashType & SIGHASH_NONE != 0)
              return false; // SIGHASH_NONE doesn't care about outputs
            return true; // SIGHASH_* does care
          }).contains(true);
        }).contains(true);
  }

  bool _canSign(Input input) {
    return input.pubkeys != null &&
        input.signScript != null &&
        input.signatures != null &&
        input.signatures!.length == input.pubkeys!.length &&
        input.pubkeys!.length > 0;
  }

  _addInputUnsafe(Uint8List hash, int? vout, Input options, {String? type}) {
    String txHash = HEX.encode(hash);
    Input input;
    if (isCoinbaseHash(hash)) {
      throw ArgumentError('coinbase inputs not supported');
    }
    final prevTxOut = '$txHash:$vout';
    if (_prevTxSet[prevTxOut] != null)
      throw ArgumentError('Duplicate TxOut: ' + prevTxOut);
    if (options.script != null) {
      input = Input.expandInput(
          options.script, options.witness ?? EMPTY_WITNESS, type);
    } else {
      input = Input();
    }
    if (options.value != null) input.value = options.value;
    if (input.prevOutScript == null && options.prevOutScript != null) {
      if (input.pubkeys == null && input.signatures == null) {
        var expanded = Output.expandOutput(options.prevOutScript);
        if (expanded.pubkeys != null && !expanded.pubkeys!.isEmpty) {
          input.pubkeys = expanded.pubkeys;
          input.signatures = expanded.signatures;
        }
      }
      input.prevOutScript = options.prevOutScript;
      input.prevOutType = type ?? classifyOutput(options.prevOutScript!);
    }
    int vin = _tx!.addInput(hash, vout, options.sequence, options.script);
    _inputs.add(input);
    _prevTxSet[prevTxOut] = true;
    return vin;
  }

  int _signatureHashType(Uint8List buffer) {
    return buffer.buffer.asByteData().getUint8(buffer.length - 1);
  }

  Transaction? get tx => _tx;

  Map get prevTxSet => _prevTxSet;
}

Uint8List? pubkeyToOutputScript(
    Uint8List? pubkey, String? asset, int? assetAmount, Uint8List assetLiteral,
    [NetworkType network = mainnet]) {
  P2PKH p2pkh = P2PKH(
      data: PaymentData(pubkey: pubkey),
      asset: asset,
      assetAmount: assetAmount,
      assetLiteral: assetLiteral,
      network: network);
  return p2pkh.data.output;
}
