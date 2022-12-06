import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:tuple/tuple.dart';

import '../transaction.dart';
import './varuint.dart' as varuint;
import './push_data.dart' as pushdata;

Tuple2<Map<String?, int>, int> parseSendAmountAndFeeFromSerializedTransaction(
    Map<String, Tuple2<String?, int>> outputsForVins,
    Uint8List serializedTransaction) {
  serializedTransaction = serializedTransaction.sublist(4); // Ignore version
  if (serializedTransaction[0] == 0) {
    // Chop witness flag if any
    serializedTransaction = serializedTransaction.sublist(2);
  }

  final vinCount = varuint.decode(serializedTransaction);
  serializedTransaction =
      serializedTransaction.sublist(varuint.encodingLength(vinCount));

  final vins = <Input>[];
  for (var vinIdx = 0; vinIdx < vinCount; vinIdx++) {
    final hash = serializedTransaction.sublist(0, 32);
    serializedTransaction = serializedTransaction.sublist(32);
    final idxBytes = serializedTransaction.sublist(0, 4);
    serializedTransaction = serializedTransaction.sublist(4);
    final idx = idxBytes.buffer.asByteData().getUint32(0, Endian.little);
    final scriptLength = varuint.decode(serializedTransaction);
    serializedTransaction =
        serializedTransaction.sublist(varuint.encodingLength(scriptLength));
    final scriptBytes = serializedTransaction.sublist(0, scriptLength);
    serializedTransaction = serializedTransaction.sublist(scriptLength);
    final sequenceBytes = serializedTransaction.sublist(0, 4);
    serializedTransaction = serializedTransaction.sublist(4);
    final sequence =
        sequenceBytes.buffer.asByteData().getUint32(0, Endian.little);
    vins.add(
        Input(hash: hash, index: idx, script: scriptBytes, sequence: sequence));
  }

  final voutCount = varuint.decode(serializedTransaction);
  serializedTransaction =
      serializedTransaction.sublist(varuint.encodingLength(voutCount));

  final voutValues = <String?, int>{};
  for (var voutIdx = 0; voutIdx < voutCount; voutIdx++) {
    final satsBytes = serializedTransaction.sublist(0, 8);
    serializedTransaction = serializedTransaction.sublist(8);
    final sats = satsBytes.buffer.asByteData().getUint64(0, Endian.little);
    final scriptLength = varuint.decode(serializedTransaction);
    serializedTransaction =
        serializedTransaction.sublist(varuint.encodingLength(scriptLength));
    Uint8List scriptBytes = serializedTransaction.sublist(0, scriptLength);
    serializedTransaction = serializedTransaction.sublist(scriptLength);

    final asset_start = scriptBytes.indexOf(0xc0);
    // Where it will normally be at minimum asset txs
    if (asset_start > 0x16) {
      scriptBytes = scriptBytes.sublist(asset_start + 1);
      final push = pushdata.decode(scriptBytes, 0);
      scriptBytes = scriptBytes.sublist(push!.size! + 3);
      final scriptType = scriptBytes[0];
      scriptBytes = scriptBytes.sublist(1);
      final nameLength = scriptBytes[0];
      scriptBytes = scriptBytes.sublist(1);
      final nameBytes = scriptBytes.sublist(0, nameLength);
      scriptBytes = scriptBytes.sublist(nameLength);
      final assetName = utf8.decode(nameBytes);
      if (scriptType == 0x6f) {
        voutValues[assetName] = 100000000;
      } else {
        final satsBytes = scriptBytes.sublist(0, 8);
        final sats = satsBytes.buffer.asByteData().getUint64(0, Endian.little);
        voutValues[assetName] = (voutValues[assetName] ?? 0) + sats;
      }
    } else {
      voutValues[null] = (voutValues[null] ?? 0) + sats;
    }
  }
  // Don't care about rest.

  final vinValues = <String?, int>{};
  for (final vin in vins) {
    final amountTuple = outputsForVins[
        '${hex.encode(vin.hash!.reversed.toList())}:${vin.index!}']!;
    vinValues[amountTuple.item1] =
        (vinValues[amountTuple.item1] ?? 0) + amountTuple.item2;
  }

  // (output amounts, fee)
  return Tuple2(voutValues, vinValues[null]! - voutValues[null]!);
}
