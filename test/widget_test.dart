import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zentra_wallet/models/wallet_models.dart';
import 'package:zentra_wallet_core/zentra_wallet_core.dart';

bool _nativeAvailable() {
  try {
    if (Platform.isLinux) {
      ffi.DynamicLibrary.open('libzentra_wallet_core_plugin.so');
      return true;
    }
  } catch (_) {}
  return false;
}

void main() {
  test('C++ core amount round-trip', () {
    if (!_nativeAvailable()) {
      return;
    }
    final core = ZentraCore.instance;
    expect(core.displayToAtomic('1.5'), 1500000000);
    expect(core.atomicToDisplay(1500000000), '1');
    expect(core.atomicToDisplay(1999999999), '1');
    expect(core.coinTicker, 'ZTRA');
  });

  test('transfer from embedded wallet2 JSON', () {
    final tx = WalletTransfer.fromNative({
      'txid': 'abc123',
      'amount': 1000,
      'incoming': false,
      'timestamp': 1,
      'height': 100,
      'confirmations': 5,
      'payment_id': '',
      'pending': true,
      'failed': false,
    });
    expect(tx.isIncoming, isFalse);
    expect(tx.pending, isTrue);
    expect(tx.amountAtomic, 1000);

    final incoming = WalletTransfer.fromNative({
      'txid': 'def456',
      'amount': 2000,
      'incoming': true,
      'timestamp': 2,
      'height': 101,
      'confirmations': 10,
      'pending': false,
      'failed': false,
    });
    expect(incoming.isIncoming, isTrue);
  });

  test('address prefix validation mainnet', () {
    if (!_nativeAvailable()) {
      return;
    }
    final core = ZentraCore.instance;
    expect(
      core.validateAddress(
        'Z7i2zfb8jc9PmBBodytkH5YaSW47CK3X2JhMxdPLvqxHjmuRQMwJLVgDtFkU3h5jgFVSS5evJfmVWbNUeAdHspG82MaXVnZmS',
        ZentraNetwork.mainnet,
      ),
      isTrue,
    );
    expect(core.validateAddress('4invalid', ZentraNetwork.mainnet), isFalse);
  });
}
