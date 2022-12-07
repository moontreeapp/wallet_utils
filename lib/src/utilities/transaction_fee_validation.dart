import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:tuple/tuple.dart';

import '../transaction.dart';
import '../utils/varuint.dart' as varuint;
import '../utils/push_data.dart' as pushdata;

Tuple2<Map<String?, int>, int> parseSendAmountAndFeeFromSerializedTransaction(
    Map<String, Tuple2<String?, int>> outputsForVins,
    Uint8List serializedTransaction) {
  serializedTransaction = serializedTransaction.sublist(4); // Ignore version
  if (serializedTransaction[0] == 0) {
    // Chop witness flag if any
    serializedTransaction = serializedTransaction.sublist(2);
  }

  final int vinCount = varuint.decode(serializedTransaction);
  serializedTransaction =
      serializedTransaction.sublist(varuint.encodingLength(vinCount));

  final List<Input> vins = <Input>[];
  for (int vinIdx = 0; vinIdx < vinCount; vinIdx++) {
    final Uint8List hash = serializedTransaction.sublist(0, 32);
    serializedTransaction = serializedTransaction.sublist(32);
    final Uint8List idxBytes = serializedTransaction.sublist(0, 4);
    serializedTransaction = serializedTransaction.sublist(4);
    final int idx = idxBytes.buffer.asByteData().getUint32(0, Endian.little);
    final int scriptLength = varuint.decode(serializedTransaction);
    serializedTransaction =
        serializedTransaction.sublist(varuint.encodingLength(scriptLength));
    final Uint8List scriptBytes =
        serializedTransaction.sublist(0, scriptLength);
    serializedTransaction = serializedTransaction.sublist(scriptLength);
    final Uint8List sequenceBytes = serializedTransaction.sublist(0, 4);
    serializedTransaction = serializedTransaction.sublist(4);
    final int sequence =
        sequenceBytes.buffer.asByteData().getUint32(0, Endian.little);
    vins.add(
        Input(hash: hash, index: idx, script: scriptBytes, sequence: sequence));
  }

  final int voutCount = varuint.decode(serializedTransaction);
  serializedTransaction =
      serializedTransaction.sublist(varuint.encodingLength(voutCount));

  final Map<String?, int> voutValues = <String?, int>{};
  for (int voutIdx = 0; voutIdx < voutCount; voutIdx++) {
    final Uint8List satsBytes = serializedTransaction.sublist(0, 8);
    serializedTransaction = serializedTransaction.sublist(8);
    final int sats = satsBytes.buffer.asByteData().getUint64(0, Endian.little);
    final int scriptLength = varuint.decode(serializedTransaction);
    serializedTransaction =
        serializedTransaction.sublist(varuint.encodingLength(scriptLength));
    Uint8List scriptBytes = serializedTransaction.sublist(0, scriptLength);
    serializedTransaction = serializedTransaction.sublist(scriptLength);

    final int assetStart = scriptBytes.indexOf(0xc0);
    // Where it will normally be at minimum asset txs
    if (assetStart > 0x16) {
      scriptBytes = scriptBytes.sublist(assetStart + 1);
      final pushdata.DecodedPushData? push = pushdata.decode(scriptBytes, 0);
      scriptBytes = scriptBytes.sublist(push!.size! + 3);
      final int scriptType = scriptBytes[0];
      scriptBytes = scriptBytes.sublist(1);
      final int nameLength = scriptBytes[0];
      scriptBytes = scriptBytes.sublist(1);
      final Uint8List nameBytes = scriptBytes.sublist(0, nameLength);
      scriptBytes = scriptBytes.sublist(nameLength);
      final String assetName = utf8.decode(nameBytes);
      if (scriptType == 0x6f) {
        voutValues[assetName] = 100000000;
      } else {
        final Uint8List satsBytes = scriptBytes.sublist(0, 8);
        final int sats =
            satsBytes.buffer.asByteData().getUint64(0, Endian.little);
        voutValues[assetName] = (voutValues[assetName] ?? 0) + sats;
      }
    } else {
      voutValues[null] = (voutValues[null] ?? 0) + sats;
    }
  }
  // Don't care about rest.

  final Map<String?, int> vinValues = <String?, int>{};
  for (final Input vin in vins) {
    final Tuple2<String?, int> amountTuple = outputsForVins[
        '${hex.encode(vin.hash!.reversed.toList())}:${vin.index!}']!;
    vinValues[amountTuple.item1] =
        (vinValues[amountTuple.item1] ?? 0) + amountTuple.item2;
  }

  // (output amounts, fee)
  return Tuple2<Map<String?, int>, int>(
      voutValues, vinValues[null]! - voutValues[null]!);
}
