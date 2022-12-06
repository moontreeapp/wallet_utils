import 'validation.dart' as validation;

extension StringValidationExtension on String {
  bool get isIpfs => validation.isIpfs(this);
  bool get isAddressRVN => validation.isAddressRVN(this);
  bool get isAddressRVNt => validation.isAddressRVNt(this);
  bool get isAddressEVR => validation.isAddressEVR(this);
  bool get isAddressEVRt => validation.isAddressEVRt(this);
  bool get isTxIdRVN => validation.isTxIdRVN(this);
  bool get isAdmin => validation.isAdmin(this);
  bool get isAssetPath => validation.isAssetPath(this);
  bool get isMainAsset => validation.isMainAsset(this);
  bool get isSubAsset => validation.isSubAsset(this);
  bool get isNFT => validation.isNFT(this);
  bool get isChannel => validation.isChannel(this);
  bool get isQualifier => validation.isQualifier(this);
  bool get isSubQualifier => validation.isSubQualifier(this);
  bool get isQualifierString => validation.isQualifierString(this);
  bool get isRestricted => validation.isRestricted(this);
  bool get isMemo => validation.isMemo(this);
  bool get isAssetData => validation.isAssetData(this);
}

extension AmountValidationNumericExtension on num {
  bool get isRVNAmount => validation.isRVNAmount(this);
}

extension AmountValidationIntExtension on int {
  bool get isRVNAmount => validation.isRVNAmount(this);
}

extension AmountValidationDoubleExtension on double {
  bool get isRVNAmount => validation.isRVNAmount(this);
}

extension RVNNumericValidationExtension on String {
  bool get isInt {
    if (length > 19 || contains('.')) {
      return false;
    }
    try {
      int.parse(this);
      return true;
    } catch (e) {
      return false;
    }
  }

  bool get isDouble {
    if (contains('.')) {
      final List<String> num = split('.');
      final String whole = num.first;
      final String remainder = num.sublist(1).join();
      if ((whole.length > 14 && whole.contains(',')) ||
          (whole.length > 11 && !whole.contains(',')) ||
          remainder.length > 8) {
        return false;
      }
    }
    try {
      double.parse(this);
      return true;
    } catch (e) {
      return false;
    }
  }

  bool get isNumeric => isInt || isDouble;
  num? toNum() {
    num? amount;
    if (isInt) {
      amount = int.parse(this);
    } else if (isDouble) {
      amount = double.parse(this);
    }
    return amount;
  }

  num? toRVNAmount() {
    num? amount;
    if (isInt) {
      amount = int.parse(this);
    } else if (isDouble) {
      amount = double.parse(this);
    }
    if (amount == null) {
      return null;
    }
    if (amount.isRVNAmount) {
      return amount;
    }
    return null;
  }
}
