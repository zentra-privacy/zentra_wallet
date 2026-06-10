import 'package:flutter_test/flutter_test.dart';
import 'package:zentra_wallet/core/transfer_list_merge.dart';
import 'package:zentra_wallet/models/wallet_models.dart';

WalletTransfer _tx(String id, {bool incoming = true, bool pending = false}) {
  return WalletTransfer(
    txid: id,
    amountAtomic: 100,
    isIncoming: incoming,
    timestamp: 1,
    height: 1,
    confirmations: 1,
    pending: pending,
  );
}

void main() {
  group('transfer list merge', () {
    test('mergeTransferHead keeps tail rows', () {
      final current = [_tx('a'), _tx('b'), _tx('c'), _tx('d')];
      final head = [_tx('n1'), _tx('n2')];
      final merged = mergeTransferHead(current, head);
      expect(merged.map((t) => t.txid).toList(), ['n1', 'n2', 'c', 'd']);
    });

    test('appendTransferPage skips duplicate txids', () {
      final current = [_tx('a'), _tx('b')];
      final page = [_tx('b'), _tx('c')];
      final merged = appendTransferPage(current, page);
      expect(merged.map((t) => t.txid).toList(), ['a', 'b', 'c']);
    });

    test('fingerprintTransferHead changes when pending count changes', () {
      final base = [
        {'txid': 'a', 'pending': false, 'amount': 1, 'timestamp': 1},
      ];
      final pending = [
        {'txid': 'a', 'pending': true, 'amount': 1, 'timestamp': 1},
      ];
      expect(
        fingerprintTransferHead(base, 1),
        isNot(fingerprintTransferHead(pending, 1)),
      );
    });
  });
}
